"""Refresh all data: SEC fundamentals + latest price -> metrics -> SQLite database.

Run from the backend folder:
    python -m pipeline.refresh

SEC data is cached in backend/data/raw/; only files of companies with new filings are downloaded
again (see sec_updates.py). Delete that folder to download everything fresh.
Prices: the latest closing prices from Polygon (one request for all companies, see prices.py);
Yahoo Finance only for tickers Polygon has no price for.
"""
import csv
from datetime import datetime

from pipeline import db
from pipeline.extract import extract_company
from pipeline.metrics import METRIC_KEYS, NOT_APPLICABLE_FOR_FINANCIALS, compute_all, explain_missing
from config import BACKEND_DIR
from pipeline.prices import latest_closes, yahoo_price_and_shares
from pipeline.sec_client import load_companyfacts, load_ticker_to_cik, sec_ticker
from pipeline.sec_updates import remove_outdated_files
from pipeline.shares import extract_shares

UNIVERSE_CSV = BACKEND_DIR / "data" / "universe.csv"


def load_universe():
    """The companies to process. Lines starting with "#" are comments (the date the list was read)."""
    with open(UNIVERSE_CSV, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(line for line in f if not line.startswith("#")))


def choose_price_and_shares(ticker, polygon_closes, polygon_day, sec_shares, yahoo=yahoo_price_and_shares):
    """Pick the price and the share count, and say where each comes from.

    Price: Polygon's close if it has one, else Yahoo. Shares: the SEC filings (sec_shares), else Yahoo.
    Yahoo is only asked when something is missing, so a normal run makes almost no Yahoo requests.
    Returns a dict with price, price_source, price_fetched_at, shares_outstanding, shares_source, shares_as_of.
    """
    result = {"price": None, "price_source": None, "price_fetched_at": None,
              "shares_outstanding": None, "shares_source": None, "shares_as_of": None}
    if ticker in polygon_closes:
        result.update(price=polygon_closes[ticker], price_source="Polygon close",
                      price_fetched_at=polygon_day.isoformat())
    if sec_shares is not None:
        result.update(shares_outstanding=sec_shares["value"], shares_source=sec_shares["source"],
                      shares_as_of=sec_shares["as_of"])

    if result["price"] is None or result["shares_outstanding"] is None:
        yahoo_price, yahoo_shares = yahoo(ticker)
        if result["price"] is None and yahoo_price is not None:
            print(f"    NOTE: no Polygon price for {ticker}, using Yahoo's")
            result.update(price=yahoo_price, price_source="Yahoo Finance (backup)",
                          price_fetched_at=datetime.now().isoformat(timespec="seconds"))
        if result["shares_outstanding"] is None and yahoo_shares is not None:
            print(f"    NOTE: no recent SEC share count for {ticker}, using Yahoo's")
            result.update(shares_outstanding=yahoo_shares, shares_source="Yahoo Finance (backup)")
    return result


def build_company(row, cik, polygon_closes, polygon_day):
    ticker = row["ticker"]
    companyfacts = load_companyfacts(cik)
    years = extract_company(companyfacts)
    if not years:
        print(f"    WARNING: no annual 10-K data found for {ticker}, skipping")
        return None

    latest_year = max(years)
    sec_shares = extract_shares(companyfacts, years[latest_year]["end_date"])
    market = choose_price_and_shares(ticker, polygon_closes, polygon_day, sec_shares)
    price, shares = market["price"], market["shares_outstanding"]

    is_financial = row["sector"] == "Financials"

    company = {
        "ticker": ticker,
        "name": row["name"],
        "sector": row["sector"],
        "cik": cik,
        **market,  # price, price_source, price_fetched_at, shares_outstanding, shares_source, shares_as_of
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
    remove_outdated_files()  # so only companies with new 10-K/10-Q filings are downloaded again
    ticker_to_cik = load_ticker_to_cik()
    polygon_closes, polygon_day = latest_closes()  # one request for all companies

    companies = []
    for number, row in enumerate(universe, start=1):
        ticker = row["ticker"]
        print(f"[{number}/{len(universe)}] {ticker}")
        # The optional "cik" column in universe.csv overrides the SEC ticker list
        cik = int(row["cik"]) if row.get("cik") else ticker_to_cik.get(sec_ticker(ticker))
        if cik is None:
            print(f"    WARNING: {ticker} not found in the SEC ticker list, skipping")
            continue
        company = build_company(row, cik, polygon_closes, polygon_day)
        if company is not None:
            companies.append(company)

    db.write_database(companies)
    print()
    print(f"Wrote {len(companies)} companies to {db.DB_PATH}")
    print_coverage(companies)


if __name__ == "__main__":
    main()
