"""Refresh all data: SEC fundamentals + latest price -> metrics -> SQLite database.

Run from the backend folder:
    python -m pipeline.refresh

SEC data is cached in backend/data/raw/. Delete that folder to download fresh 10-K data.
Prices are fetched fresh from Yahoo Finance (via yfinance) on every run.
"""
import csv
import warnings
from datetime import datetime

import yfinance as yf

from pipeline import db
from pipeline.extract import extract_company
from pipeline.metrics import METRIC_KEYS, NOT_APPLICABLE_FOR_FINANCIALS, compute_all, explain_missing
from config import BACKEND_DIR
from pipeline.sec_client import load_companyfacts, load_ticker_to_cik

UNIVERSE_CSV = BACKEND_DIR / "data" / "universe.csv"

# yfinance prints pandas deprecation warnings that are not our concern
warnings.filterwarnings("ignore", module="yfinance")


def load_universe():
    with open(UNIVERSE_CSV, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def fetch_price_and_shares(ticker):
    """Return (latest price, shares outstanding) from Yahoo Finance, or (None, None) on failure.

    fast_info["shares"] counts all share classes (e.g. Alphabet's A, B and C shares),
    unlike info["sharesOutstanding"], which only counts one class.
    """
    try:
        info = yf.Ticker(ticker).fast_info
        return info["last_price"], info["shares"]
    except Exception as error:  # network problems, unknown ticker, Yahoo changes, ...
        print(f"    WARNING: no price for {ticker}: {error}")
        return None, None


def build_company(row, cik):
    ticker = row["ticker"]
    years = extract_company(load_companyfacts(cik))
    if not years:
        print(f"    WARNING: no annual 10-K data found for {ticker}, skipping")
        return None

    price, shares = fetch_price_and_shares(ticker)
    is_financial = row["sector"] == "Financials"
    latest_year = max(years)

    company = {
        "ticker": ticker,
        "name": row["name"],
        "sector": row["sector"],
        "cik": cik,
        "price": price,
        "shares_outstanding": shares,
        "price_fetched_at": datetime.now().isoformat(timespec="seconds") if price is not None else None,
        "latest_fiscal_year": latest_year,
        "latest_fiscal_year_end": years[latest_year]["end_date"],
        "not_applicable": NOT_APPLICABLE_FOR_FINANCIALS if is_financial else [],
        "years": years,
    }
    values = compute_all(years, price, shares, is_financial)
    company.update(values)
    company["missing_reasons"] = explain_missing(values, years, price, shares, is_financial)
    return company


def print_coverage(companies):
    total = len(companies)
    print()
    print(f"=== Coverage per metric ({total} companies) ===")
    print(f"{'metric':<20}{'has value':>10}{'n/a':>6}   missing for")
    for key in METRIC_KEYS:
        not_applicable = [c["ticker"] for c in companies if key in c["not_applicable"]]
        missing = [c["ticker"] for c in companies if c[key] is None and key not in c["not_applicable"]]
        have = total - len(missing) - len(not_applicable)
        print(f"{key:<20}{f'{have}/{total}':>10}{len(not_applicable):>6}   {', '.join(missing)}")


def main():
    universe = load_universe()
    ticker_to_cik = load_ticker_to_cik()

    companies = []
    for number, row in enumerate(universe, start=1):
        ticker = row["ticker"]
        print(f"[{number}/{len(universe)}] {ticker}")
        # The optional "cik" column in universe.csv overrides the SEC ticker list
        cik = int(row["cik"]) if row.get("cik") else ticker_to_cik.get(ticker)
        if cik is None:
            print(f"    WARNING: {ticker} not found in the SEC ticker list, skipping")
            continue
        company = build_company(row, cik)
        if company is not None:
            companies.append(company)

    db.write_database(companies)
    print()
    print(f"Wrote {len(companies)} companies to {db.DB_PATH}")
    print_coverage(companies)


if __name__ == "__main__":
    main()
