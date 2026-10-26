"""Print the raw SEC fields for a few companies, so the extraction can be checked by eye.

Run from the backend folder:
    python -m pipeline.preview              (default: AAPL MSFT JNJ KO JPM)
    python -m pipeline.preview NVDA XOM     (any tickers you like)

Dollar amounts are printed in millions, like in a 10-K. EPS is in dollars per share.
"""
import sys

from pipeline.extract import FIELDS, extract_company
from pipeline.sec_client import load_companyfacts, load_ticker_to_cik

DEFAULT_TICKERS = ["AAPL", "MSFT", "JNJ", "KO", "JPM"]

FIELD_WIDTH = 21
YEAR_WIDTH = 12


def format_value(field, cell):
    if cell is None:
        return "—"
    unit = FIELDS[field][1]
    if unit == "USD/shares":
        return f"{cell['value']:.2f}"
    return f"{cell['value'] / 1_000_000:,.0f}"


def describe_tags(years, field):
    """Return the tag used, or "TagA [2021-2022], TagB [2023-2025]" if it changed over the years."""
    tag_years = {}
    for year, data in years.items():
        cell = data["fields"][field]
        if cell is not None:
            tag_years.setdefault(cell["tag"], []).append(year)
    if len(tag_years) <= 1:
        return next(iter(tag_years), "")
    parts = []
    for tag, tag_year_list in tag_years.items():
        first, last = min(tag_year_list), max(tag_year_list)
        year_range = str(first) if first == last else f"{first}-{last}"
        parts.append(f"{tag} [{year_range}]")
    return ", ".join(parts)


def print_company_table(ticker, cik, years):
    print()
    print(f"=== {ticker} (CIK {cik}) — USD millions, EPS in USD ===")
    year_list = sorted(years)

    header = "Field".ljust(FIELD_WIDTH) + "".join(f"FY{y}".rjust(YEAR_WIDTH) for y in year_list) + "   XBRL tag used"
    end_row = "Fiscal year end".ljust(FIELD_WIDTH) + "".join(years[y]["end_date"].rjust(YEAR_WIDTH) for y in year_list)
    print(header)
    print(end_row)
    print("-" * len(header))
    for field in FIELDS:
        row = field.ljust(FIELD_WIDTH)
        row += "".join(format_value(field, years[y]["fields"][field]).rjust(YEAR_WIDTH) for y in year_list)
        row += "   " + describe_tags(years, field)
        print(row)


def find_missing(years):
    """Return {field: [years where it is missing]} for fields missing in at least one year."""
    missing = {}
    for field in FIELDS:
        missing_years = [y for y in sorted(years) if years[y]["fields"][field] is None]
        if missing_years:
            missing[field] = missing_years
    return missing


def print_missing_summary(missing_by_ticker):
    print()
    print("=== Missing fields ===")
    for ticker, missing in missing_by_ticker:
        if not missing:
            print(f"{ticker}: nothing missing")
            continue
        print(f"{ticker}:")
        for field, missing_years in missing.items():
            print(f"    {field.ljust(FIELD_WIDTH)} missing in {', '.join(f'FY{y}' for y in missing_years)}")


def main():
    tickers = [t.upper() for t in sys.argv[1:]] or DEFAULT_TICKERS
    ticker_to_cik = load_ticker_to_cik()

    missing_by_ticker = []
    for ticker in tickers:
        cik = ticker_to_cik.get(ticker)
        if cik is None:
            print(f"{ticker}: not found in the SEC ticker list")
            continue
        years = extract_company(load_companyfacts(cik))
        print_company_table(ticker, cik, years)
        missing_by_ticker.append((ticker, find_missing(years)))

    print_missing_summary(missing_by_ticker)


if __name__ == "__main__":
    main()
