"""Tests for prices from Polygon with Yahoo as backup. Nothing here goes online or sleeps."""
from datetime import date

import pytest

import config
from pipeline import prices
from pipeline.prices import latest_closes, parse_grouped_daily
from pipeline.refresh import choose_price_and_shares

FRIDAY = date(2026, 10, 30)
SUNDAY = date(2026, 11, 1)
SEC_SHARES = {"value": 1000.0, "as_of": "2026-07-17", "source": "SEC cover page (10-Q)"}


@pytest.fixture
def key(monkeypatch):
    monkeypatch.setattr(config, "POLYGON_API_KEY", "secret-test-key")


def test_parse_grouped_daily():
    data = {"resultsCount": 3, "results": [
        {"T": "AAPL", "c": 338.32, "o": 335.0}, {"T": "BRK.B", "c": 478.1}, {"T": "ZERO", "c": 0},
    ]}
    assert parse_grouped_daily(data) == {"AAPL": 338.32, "BRK.B": 478.1}  # a close of 0 is not a price
    assert parse_grouped_daily({"resultsCount": 0}) == {}  # weekend or holiday


def test_steps_back_over_the_weekend(key):
    asked, waits = [], []

    def fake_download(day):
        asked.append(day)
        return {"results": [{"T": "AAPL", "c": 338.32}]} if day == FRIDAY else {"resultsCount": 0}

    closes, day = latest_closes(today=SUNDAY, download=fake_download, wait=waits.append)
    assert (closes, day) == ({"AAPL": 338.32}, FRIDAY)
    assert asked == [date(2026, 10, 31), FRIDAY]  # Saturday first (nothing), then Friday
    assert waits == [prices.SECONDS_BETWEEN_REQUESTS]  # waited once, between the two requests


def test_errors_are_skipped_and_never_show_the_key(key, capsys):
    def failing_download(day):
        raise RuntimeError(f"Polygon answered 403 for {day}")

    assert latest_closes(today=SUNDAY, download=failing_download, wait=lambda s: None) == ({}, None)
    assert "secret-test-key" not in capsys.readouterr().out


def test_without_a_key_polygon_is_not_asked(monkeypatch):
    monkeypatch.setattr(config, "POLYGON_API_KEY", "")

    def must_not_be_called(day):
        raise AssertionError("no request without a key")

    assert latest_closes(today=SUNDAY, download=must_not_be_called) == ({}, None)


def test_polygon_price_and_sec_shares_need_no_yahoo():
    def must_not_be_called(ticker):
        raise AssertionError("Yahoo should not be asked")

    result = choose_price_and_shares("AAPL", {"AAPL": 338.32}, FRIDAY, SEC_SHARES, yahoo=must_not_be_called)
    assert result == {
        "price": 338.32, "price_source": "Polygon close", "price_fetched_at": "2026-10-30",
        "shares_outstanding": 1000.0, "shares_source": "SEC cover page (10-Q)", "shares_as_of": "2026-07-17",
    }


def test_yahoo_fills_only_what_is_missing():
    # Polygon has no price for this ticker; the SEC share count is kept.
    result = choose_price_and_shares("NEWCO", {}, FRIDAY, SEC_SHARES, yahoo=lambda t: (12.5, 999.0))
    assert result["price"] == 12.5
    assert result["price_source"] == "Yahoo Finance (backup)"
    assert result["shares_outstanding"] == 1000.0  # SEC, not Yahoo's 999
    assert result["shares_source"] == "SEC cover page (10-Q)"

    # Visa-like: Polygon price, but no SEC share count -> shares from Yahoo.
    result = choose_price_and_shares("V", {"V": 330.0}, FRIDAY, None, yahoo=lambda t: (331.0, 1877.0))
    assert (result["price"], result["price_source"]) == (330.0, "Polygon close")
    assert (result["shares_outstanding"], result["shares_source"]) == (1877.0, "Yahoo Finance (backup)")


def test_nothing_anywhere_stays_missing():
    result = choose_price_and_shares("GONE", {}, None, None, yahoo=lambda t: (None, None))
    assert result["price"] is None and result["shares_outstanding"] is None  # shown as "—", never 0
