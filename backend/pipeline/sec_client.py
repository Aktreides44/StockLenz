"""Download data from SEC EDGAR, with caching and polite rate limiting.

SEC rules: every request must send a User-Agent that identifies us (read from
backend/.env), and we must stay under 10 requests per second.
Downloaded JSON is cached in backend/data/raw/ so reruns don't refetch it.
"""
import json
import os
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent.parent
RAW_DIR = BACKEND_DIR / "data" / "raw"

TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
COMPANYFACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json"

SECONDS_BETWEEN_REQUESTS = 0.2  # at most 5 requests/second, well under the SEC limit of 10


def get_user_agent():
    load_dotenv(BACKEND_DIR / ".env")
    user_agent = os.getenv("SEC_USER_AGENT")
    if not user_agent or "example.com" in user_agent:
        raise RuntimeError(
            "SEC_USER_AGENT is not set. Copy backend/.env.example to backend/.env "
            "and put your email address in it."
        )
    return user_agent


def download_json(url):
    response = requests.get(url, headers={"User-Agent": get_user_agent()}, timeout=30)
    time.sleep(SECONDS_BETWEEN_REQUESTS)
    response.raise_for_status()
    return response.json()


def get_cached_json(url, cache_file):
    """Return the JSON stored in cache_file, downloading it first if it isn't there yet."""
    if not cache_file.exists():
        data = download_json(url)
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        cache_file.write_text(json.dumps(data), encoding="utf-8")
    return json.loads(cache_file.read_text(encoding="utf-8"))


def load_ticker_to_cik():
    """Return a dict like {"AAPL": 320193, ...} from the SEC's official ticker list."""
    data = get_cached_json(TICKERS_URL, RAW_DIR / "company_tickers.json")
    return {entry["ticker"].upper(): int(entry["cik_str"]) for entry in data.values()}


def load_companyfacts(cik):
    """Return the full XBRL companyfacts JSON for one company."""
    url = COMPANYFACTS_URL.format(cik=cik)
    return get_cached_json(url, RAW_DIR / f"CIK{cik:010d}.json")
