"""Daily closing prices for the last year, for the price chart on the company page.

Polygon's "grouped daily" request returns the closes of all US stocks for one day, and we already ask
for the latest day every run (prices.py). Here we KEEP those closes instead of throwing them away:

  1. Each run starts from yesterday's database (the workflow downloads the published one first), so
     the history carries over from run to run.
  2. Today's closes are added.
  3. Backfill: up to `budget` older trading days that are still missing are fetched, newest first,
     12 seconds apart (free plan: 5 requests per minute). After a few daily runs the year is complete.
  4. Stock splits: when a company splits its shares (1 old share -> 10 new ones), its old stored prices
     would show a false crash. Polygon lists recent splits in one request; for every company of ours
     that split, its whole year is fetched again, already adjusted for the split.

`fetched_days` remembers which days were already asked for, including holidays without trading,
so they are not asked for again.
"""
import time
from datetime import date, datetime, timedelta, timezone

import requests

import config
from pipeline.prices import download_grouped_daily, is_trading_day, parse_grouped_daily

HISTORY_DAYS = 366  # how far back the chart goes (calendar days)
SPLITS_URL = "https://api.polygon.io/v3/reference/splits"
TICKER_RANGE_URL = "https://api.polygon.io/v2/aggs/ticker/{ticker}/range/1/day/{start}/{end}"
SPLIT_LOOKBACK_DAYS = 7  # re-adjusting is harmless, so look back a week in case a run was missed
SECONDS_BETWEEN_REQUESTS = 12


def load_history(conn):
    """Read the price history from an existing database: ({ticker: {day: close}}, set of fetched days).

    An older database without these tables simply gives an empty history. Weekend days are dropped:
    a few weekend trades once slipped in as a "trading day" (7 Nov 2026).
    """
    history, fetched_days = {}, set()
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if "prices" in tables:
        for ticker, day, close in conn.execute("SELECT ticker, day, close FROM prices"):
            if date.fromisoformat(day).weekday() < 5:
                history.setdefault(ticker, {})[day] = close
    if "price_days" in tables:
        fetched_days = {row[0] for row in conn.execute("SELECT day FROM price_days")}
    return history, fetched_days


def missing_days(fetched_days, today, history_days=HISTORY_DAYS):
    """Weekdays of the last `history_days` (before today) not asked for yet, newest first."""
    days = []
    for back in range(1, history_days + 1):
        day = today - timedelta(days=back)
        if day.weekday() < 5 and day.isoformat() not in fetched_days:
            days.append(day)
    return days


def add_closes(history, closes, day, tickers):
    """Store one day's closes for our tickers: closes {ticker: close} -> history[ticker][day]."""
    for ticker in tickers:
        if ticker in closes:
            history.setdefault(ticker, {})[day.isoformat()] = closes[ticker]


def backfill(history, fetched_days, tickers, today, budget, download=download_grouped_daily, wait=time.sleep):
    """Fetch up to `budget` missing older days. Returns how many days were asked for."""
    asked = 0
    for day in missing_days(fetched_days, today)[:budget]:
        wait(SECONDS_BETWEEN_REQUESTS)
        try:
            closes = parse_grouped_daily(download(day))
        except Exception as error:  # e.g. 403 for a day the plan doesn't cover: try again next run
            print(f"    Price history: no data for {day} ({error})")
            continue
        if is_trading_day(day, closes):  # a holiday (no or only a few prices) adds nothing
            add_closes(history, closes, day, tickers)
        fetched_days.add(day.isoformat())
        asked += 1
    return asked


def split_tickers(splits_json, tickers):
    """Which of our tickers split recently, from Polygon's split list."""
    return sorted({s["ticker"] for s in splits_json.get("results") or [] if s.get("ticker") in tickers})


def parse_ticker_range(data):
    """{"results": [{"t": <ms since 1970>, "c": 123.4}, ...]} -> {"2026-11-03": 123.4, ...}"""
    closes = {}
    for row in data.get("results") or []:
        day = datetime.fromtimestamp(row["t"] / 1000, tz=timezone.utc).date()
        closes[day.isoformat()] = float(row["c"])
    return closes


def polygon_json(url, params):
    """GET a Polygon URL with the key. Error messages never contain the key (it is in the URL)."""
    response = requests.get(url, params={**params, "apiKey": config.POLYGON_API_KEY}, timeout=60)
    if response.status_code != 200:
        raise RuntimeError(f"Polygon answered {response.status_code}")
    return response.json()


def readjust_splits(history, tickers, today, get_json=polygon_json, wait=time.sleep):
    """Fetch the whole year again, split-adjusted, for every ticker of ours that split recently."""
    wait(SECONDS_BETWEEN_REQUESTS)
    try:
        since = (today - timedelta(days=SPLIT_LOOKBACK_DAYS)).isoformat()
        splits = get_json(SPLITS_URL, {"execution_date.gte": since, "execution_date.lte": today.isoformat(),
                                       "limit": 1000})
    except Exception as error:
        print(f"    Price history: could not check for stock splits ({error})")
        return []
    split = split_tickers(splits, tickers)
    for ticker in split:
        wait(SECONDS_BETWEEN_REQUESTS)
        start = (today - timedelta(days=HISTORY_DAYS)).isoformat()
        try:
            closes = parse_ticker_range(get_json(TICKER_RANGE_URL.format(ticker=ticker, start=start,
                                                                          end=today.isoformat()),
                                                 {"adjusted": "true", "limit": 5000}))
        except Exception as error:
            print(f"    Price history: could not re-adjust {ticker} after its split ({error})")
            continue
        if closes:
            history[ticker] = closes
            print(f"    Price history: {ticker} split recently, its year was fetched again (adjusted)")
    return split


def trim(history, tickers, today):
    """Keep only our tickers and the last HISTORY_DAYS days, so the database stays small."""
    oldest = (today - timedelta(days=HISTORY_DAYS)).isoformat()
    return {t: {d: c for d, c in days.items() if d >= oldest} for t, days in history.items() if t in tickers}


def update_history(previous_conn, tickers, latest_closes, latest_day, today=None, budget=None):
    """The whole yearly price history after this run: ({ticker: {day: close}}, fetched days)."""
    today = today or date.today()
    budget = config.PRICE_BACKFILL_DAYS if budget is None else budget
    history, fetched_days = load_history(previous_conn) if previous_conn is not None else ({}, set())
    tickers = set(tickers)
    if latest_day is not None:
        add_closes(history, latest_closes, latest_day, tickers)
        fetched_days.add(latest_day.isoformat())
    if config.POLYGON_API_KEY:
        asked = backfill(history, fetched_days, tickers, today, budget)
        readjust_splits(history, tickers, today)
        still_missing = len(missing_days(fetched_days, today))
        print(f"Price history: {asked} older days fetched, {still_missing} weekdays of the last year still missing")
    oldest = (today - timedelta(days=HISTORY_DAYS)).isoformat()
    return trim(history, tickers, today), {d for d in fetched_days if d >= oldest}
