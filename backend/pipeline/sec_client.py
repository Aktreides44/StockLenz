"""Download data from SEC EDGAR, with caching and polite rate limiting.

SEC rules: every request must send a User-Agent that identifies us (the SEC_USER_AGENT
setting, see config.py), and we must stay under 10 requests per second.
Downloaded JSON is cached in backend/data/raw/ so reruns don't refetch it.
"""
import json
import time
from datetime import date

import requests

import config
from config import BACKEND_DIR

RAW_DIR = BACKEND_DIR / "data" / "raw"
MANIFEST = RAW_DIR / "downloaded.json"  # when each saved file was downloaded (used by sec_updates.py)

TICKERS_URL = "https://www.sec.gov/files/company_tickers.json"
COMPANYFACTS_URL = "https://data.sec.gov/api/xbrl/companyfacts/CIK{cik:010d}.json"

SECONDS_BETWEEN_REQUESTS = 0.2  # at most 5 requests/second, well under the SEC limit of 10


def get_user_agent():
    user_agent = config.SEC_USER_AGENT
    if not user_agent or "example.com" in user_agent:
        raise RuntimeError(
            "SEC_USER_AGENT is not set. Locally: copy backend/.env.example to backend/.env "
            "and put your email address in it. On a server: set it as an environment variable."
        )
    return user_agent


def download(url):
    response = requests.get(url, headers={"User-Agent": get_user_agent()}, timeout=30)
    time.sleep(SECONDS_BETWEEN_REQUESTS)
    response.raise_for_status()
    return response


def download_json(url):
    return download(url).json()


def download_text(url):
    return download(url).text


def load_manifest():
    """{"CIK0000320193.json": "2026-11-04", ...}: when each saved file was downloaded."""
    return json.loads(MANIFEST.read_text(encoding="utf-8")) if MANIFEST.exists() else {}


def save_manifest(manifest):
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(manifest, indent=1, sort_keys=True), encoding="utf-8")


def get_cached_json(url, cache_file):
    """Return the JSON stored in cache_file, downloading it first if it isn't there yet."""
    if not cache_file.exists():
        data = download_json(url)
        cache_file.parent.mkdir(parents=True, exist_ok=True)
        cache_file.write_text(json.dumps(data), encoding="utf-8")
        # Remember when it was downloaded, so sec_updates.py can tell when it is out of date.
        manifest = load_manifest()
        manifest[cache_file.name] = date.today().isoformat()
        save_manifest(manifest)
    return json.loads(cache_file.read_text(encoding="utf-8"))


def sec_ticker(ticker):
    """universe.csv writes share classes with a dot (BRK.B, like Wikipedia and Polygon);
    the SEC and Yahoo use a dash (BRK-B)."""
    return ticker.replace(".", "-")


def load_ticker_to_cik():
    """Return a dict like {"AAPL": 320193, ...} from the SEC's official ticker list."""
    data = get_cached_json(TICKERS_URL, RAW_DIR / "company_tickers.json")
    return {entry["ticker"].upper(): int(entry["cik_str"]) for entry in data.values()}


def load_companyfacts(cik):
    """Return the full XBRL companyfacts JSON for one company."""
    url = COMPANYFACTS_URL.format(cik=cik)
    return get_cached_json(url, RAW_DIR / f"CIK{cik:010d}.json")
