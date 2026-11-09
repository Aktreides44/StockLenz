"""Tests for the yearly price history behind the price chart. Nothing here goes online or sleeps."""
from datetime import date

import config
from pipeline import db, prices
from pipeline.price_history import (
    backfill, load_history, missing_days, parse_ticker_range, readjust_splits, trim, update_history,
)

MONDAY = date(2026, 11, 9)
TICKERS = {"AAPL", "NVDA"}


def no_wait(seconds):
    pass


def test_missing_days_skips_weekends_and_known_days_newest_first():
    fetched = {"2026-11-06"}  # Friday already done
    days = missing_days(fetched, MONDAY, history_days=10)
    assert days[:3] == [date(2026, 11, 5), date(2026, 11, 4), date(2026, 11, 3)]  # Thu, Wed, Tue
    assert all(day.weekday() < 5 for day in days)
    assert date(2026, 11, 8) not in days  # Sunday


def full_day(**closes):
    """A grouped daily answer of a real trading day: thousands of closes (other tickers) plus `closes`."""
    results = [{"T": f"T{i}", "c": 10.0} for i in range(prices.MIN_TRADING_DAY_PRICES)]
    return {"results": results + [{"T": t, "c": c} for t, c in closes.items()]}


def test_backfill_keeps_to_the_budget_and_remembers_holidays():
    answers = {
        date(2026, 11, 6): full_day(AAPL=331.9),
        date(2026, 11, 5): {"results": [{"T": "AAPL", "c": 1.0}]},  # a holiday: only a stray trade
    }

    def download(day):
        if day == date(2026, 11, 4):
            raise RuntimeError("Polygon answered 500")
        return answers.get(day, full_day(NVDA=200.0))

    history, fetched = {}, set()
    asked = backfill(history, fetched, TICKERS, MONDAY, budget=3, download=download, wait=no_wait)
    assert asked == 2  # the failed day does not count
    assert history == {"AAPL": {"2026-11-06": 331.9}}  # only our tickers are kept
    assert fetched == {"2026-11-06", "2026-11-05"}  # the holiday is remembered, the failed day is not


def test_history_carries_over_from_the_previous_database(tmp_path):
    path = tmp_path / "old.db"
    db.write_database([], path=path, price_history={"AAPL": {"2026-11-05": 330.0}}, price_days={"2026-11-05"})
    conn = db.connect(path)
    assert load_history(conn) == ({"AAPL": {"2026-11-05": 330.0}}, {"2026-11-05"})
    conn.close()


def test_weekend_days_are_dropped_when_loading(tmp_path):
    # 7 Nov 2026 was a Saturday that once slipped in with a few weekend trades.
    path = tmp_path / "old.db"
    db.write_database([], path=path, price_history={"AAPL": {"2026-11-06": 331.9, "2026-11-07": 340.0}})
    conn = db.connect(path)
    assert load_history(conn)[0] == {"AAPL": {"2026-11-06": 331.9}}
    conn.close()


def test_a_database_from_before_the_price_chart_gives_an_empty_history(tmp_path):
    conn = db.connect(tmp_path / "older.db")
    conn.execute("CREATE TABLE companies (ticker TEXT)")
    assert load_history(conn) == ({}, set())
    conn.close()


def test_update_history_adds_todays_closes(tmp_path, monkeypatch):
    monkeypatch.setattr(config, "POLYGON_API_KEY", "")  # no key: no backfill, no network
    path = tmp_path / "old.db"
    db.write_database([], path=path, price_history={"AAPL": {"2026-11-05": 330.0}}, price_days={"2026-11-05"})
    conn = db.connect(path)
    history, days = update_history(conn, TICKERS, {"AAPL": 331.9, "NVDA": 200.0}, date(2026, 11, 6), today=MONDAY)
    conn.close()
    assert history == {"AAPL": {"2026-11-05": 330.0, "2026-11-06": 331.9}, "NVDA": {"2026-11-06": 200.0}}
    assert days == {"2026-11-05", "2026-11-06"}


def test_parse_ticker_range():
    data = {"results": [{"t": 1762732800000, "c": 269.43}]}  # 2025-11-10 00:00 UTC
    assert parse_ticker_range(data) == {"2025-11-10": 269.43}


def test_a_split_replaces_only_that_tickers_history():
    history = {"AAPL": {"2026-11-05": 330.0}, "NVDA": {"2026-11-05": 2000.0}}  # NVDA before a 10:1 split

    def get_json(url, params):
        if "splits" in url:
            return {"results": [{"ticker": "NVDA", "split_from": 1, "split_to": 10}, {"ticker": "XYZ"}]}
        assert "/NVDA/" in url and params["adjusted"] == "true"
        return {"results": [{"t": 1762732800000, "c": 200.0}]}

    assert readjust_splits(history, TICKERS, MONDAY, get_json=get_json, wait=no_wait) == ["NVDA"]
    assert history["NVDA"] == {"2025-11-10": 200.0}  # the whole year again, adjusted
    assert history["AAPL"] == {"2026-11-05": 330.0}  # untouched


def test_trim_keeps_one_year_and_only_our_tickers():
    history = {"AAPL": {"2025-11-01": 1.0, "2026-11-06": 2.0}, "GONE": {"2026-11-06": 3.0}}
    assert trim(history, TICKERS, MONDAY) == {"AAPL": {"2026-11-06": 2.0}}
