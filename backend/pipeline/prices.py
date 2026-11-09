"""Share prices: Polygon.io (now also called Massive) first, Yahoo Finance only as a backup.

Polygon's "grouped daily" endpoint returns the closing price of every US stock for one trading day
in a single request (~12,600 tickers). On weekends and holidays there is no data, so we step back
one day at a time. The free plan allows 5 requests per minute, so we wait between tries.

The API key comes from POLYGON_API_KEY (backend/.env locally, a GitHub secret in Actions).
It is never printed: error messages only show the date and the HTTP status.
"""
import time
import warnings
from datetime import date, timedelta

import requests
import yfinance as yf

import config
from pipeline.sec_client import sec_ticker

GROUPED_DAILY_URL = "https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/{day}"
MAX_DAYS_BACK = 5  # enough to get past a long weekend
SECONDS_BETWEEN_REQUESTS = 12  # free plan: 5 requests per minute

# A real trading day has ~11,000-12,600 closes. On weekends Polygon sometimes lists a few hundred
# off-exchange trades (271 on Saturday 7 Nov 2026); such a day must not count as a trading day.
MIN_TRADING_DAY_PRICES = 1000


def is_trading_day(day, closes):
    """Weekdays with a full list of closes only."""
    return day.weekday() < 5 and len(closes) >= MIN_TRADING_DAY_PRICES


# yfinance prints pandas deprecation warnings that are not our concern
warnings.filterwarnings("ignore", module="yfinance")


def parse_grouped_daily(data):
    """{"results": [{"T": "AAPL", "c": 338.32, ...}, ...]} -> {"AAPL": 338.32, ...}"""
    return {row["T"]: float(row["c"]) for row in data.get("results") or [] if row.get("c")}


def download_grouped_daily(day):
    """The grouped daily JSON for one day (a date). Raises on HTTP errors."""
    response = requests.get(
        GROUPED_DAILY_URL.format(day=day.isoformat()),
        params={"adjusted": "true", "apiKey": config.POLYGON_API_KEY},
        timeout=60,
    )
    if response.status_code != 200:
        # Not raise_for_status(): its message would contain the URL, and the URL contains the key.
        raise RuntimeError(f"Polygon answered {response.status_code} for {day}")
    return response.json()


def latest_closes(today=None, download=download_grouped_daily, wait=time.sleep):
    """Closing prices of the latest trading day before today: ({ticker: close}, that day).

    Returns ({}, None) when there is no key or no day with data (the pipeline then uses Yahoo).
    `download` and `wait` can be replaced in tests, so tests never go online or sleep.
    """
    if not config.POLYGON_API_KEY:
        print("WARNING: POLYGON_API_KEY is not set, all prices come from Yahoo Finance")
        return {}, None
    today = today or date.today()
    requests_made = 0
    for days_back in range(1, MAX_DAYS_BACK + 1):  # the free plan has no prices for today yet
        day = today - timedelta(days=days_back)
        if day.weekday() >= 5:  # Saturday, Sunday: no trading, no request
            continue
        if requests_made > 0:
            wait(SECONDS_BETWEEN_REQUESTS)
        requests_made += 1
        try:
            closes = parse_grouped_daily(download(day))
        except Exception as error:  # network problem, 403 for a day the plan doesn't cover, ...
            print(f"    Polygon: no data for {day} ({error})")
            continue
        if is_trading_day(day, closes):
            print(f"Polygon: {len(closes)} closing prices for {day}")
            return closes, day
        print(f"    Polygon: no trading on {day} ({len(closes)} prices)")
    print(f"WARNING: Polygon had no prices in the last {MAX_DAYS_BACK} days, all prices come from Yahoo Finance")
    return {}, None


def yahoo_price_and_shares(ticker):
    """Return (latest price, shares outstanding) from Yahoo Finance, or (None, None) on failure.

    fast_info["shares"] counts all share classes (e.g. Alphabet's A, B and C shares),
    unlike info["sharesOutstanding"], which only counts one class.
    """
    try:
        info = yf.Ticker(sec_ticker(ticker)).fast_info  # Yahoo also writes BRK-B
        return info["last_price"], info["shares"]
    except Exception as error:  # network problems, unknown ticker, Yahoo changes, ...
        print(f"    WARNING: no Yahoo data for {ticker}: {error}")
        return None, None
