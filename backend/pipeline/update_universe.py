"""Write data/universe.csv from Wikipedia's "List of S&P 500 companies".

Run it by hand when the index changes (a few times a year), from the backend folder:
    python -m pipeline.update_universe

The daily pipeline never calls Wikipedia: it reads the universe.csv saved in git, so git history
shows exactly when the list changed. What this script does:
  1. reads the table on the Wikipedia page (ticker, name, sector, CIK)
  2. keeps one row per company (Alphabet has two tickers in the index: GOOGL and GOOG)
  3. checks every ticker and CIK against the SEC's official ticker list
  4. keeps the manual CIK overrides from the old universe.csv (e.g. Exxon Mobil)
  5. writes universe.csv with the date in its first line, and prints a report
"""
import csv
from datetime import date
from io import StringIO

import pandas as pd
import requests

from pipeline.refresh import UNIVERSE_CSV, load_universe
from pipeline.sec_client import RAW_DIR, load_ticker_to_cik, sec_ticker

WIKIPEDIA_URL = "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"
# Wikipedia asks for a User-Agent with a way to contact us; the repository link does that.
WIKIPEDIA_USER_AGENT = "StockLens student project (https://github.com/Aktreides44/StockLenz)"


def download_wikipedia_page():
    response = requests.get(WIKIPEDIA_URL, headers={"User-Agent": WIKIPEDIA_USER_AGENT}, timeout=30)
    response.raise_for_status()
    return response.text


def readable_name(name):
    """Wikipedia writes some names for sorting: "Coca-Cola Company (The)" -> "The Coca-Cola Company",
    "Lilly (Eli)" -> "Eli Lilly"."""
    if name.endswith(" (The)"):
        return "The " + name[: -len(" (The)")]
    if name.endswith(")") and " (" in name and "Class" not in name:
        main, first = name[:-1].split(" (", 1)
        return f"{first} {main}"
    return name


def parse_constituents(html):
    """Return the rows of the table with id="constituents" as dicts: ticker, name, sector, cik."""
    table = pd.read_html(StringIO(html), attrs={"id": "constituents"})[0]
    rows = []
    for _, line in table.iterrows():
        rows.append({
            "ticker": str(line["Symbol"]).strip().upper(),
            "name": readable_name(str(line["Security"]).strip()),
            "sector": str(line["GICS Sector"]).strip(),
            "cik": int(line["CIK"]) if pd.notna(line["CIK"]) else None,
        })
    return rows


def one_row_per_company(rows, previous_tickers):
    """Companies with several share classes in the index share one CIK; keep one ticker each.

    Preference: the ticker we already had in universe.csv, else the "(Class A)" row, else the first.
    Returns (kept rows, list of dropped tickers).
    """
    by_cik = {}
    for row in rows:
        key = row["cik"] if row["cik"] is not None else row["ticker"]  # no CIK: can't group
        by_cik.setdefault(key, []).append(row)

    kept, dropped = [], []
    for group in by_cik.values():
        def preference(row):
            if row["ticker"] in previous_tickers:
                return 0
            if "(Class A)" in row["name"]:
                return 1
            return 2

        best = min(group, key=preference)  # min keeps the first row when preferences are equal
        kept.append(dict(best, name=best["name"].replace(" (Class A)", "").replace(" (Class C)", "")))
        dropped += [row["ticker"] for row in group if row is not best]
    return kept, dropped


def check_against_sec(rows, sec_ticker_to_cik, previous_overrides):
    """Decide the cik override column for every row and collect problems for the report.

    The override stays empty when the SEC ticker list already gives the right CIK.
      - manual override in the old universe.csv -> kept as it is
      - ticker missing from the SEC list -> Wikipedia's CIK becomes the override
      - SEC list and Wikipedia disagree -> Wikipedia's CIK becomes the override (check it by hand!)
    """
    problems = []
    for row in rows:
        ticker = row["ticker"]
        sec_cik = sec_ticker_to_cik.get(sec_ticker(ticker))
        wiki_cik = row["cik"]
        if ticker in previous_overrides:
            row["cik_override"] = previous_overrides[ticker]
        elif sec_cik is None:
            row["cik_override"] = wiki_cik
            problems.append(f"{ticker}: not in the SEC ticker list, using Wikipedia's CIK {wiki_cik}")
        elif wiki_cik is not None and wiki_cik != sec_cik:
            row["cik_override"] = wiki_cik
            problems.append(f"{ticker}: SEC list says CIK {sec_cik}, Wikipedia says {wiki_cik} (using Wikipedia's)")
        else:
            row["cik_override"] = None
    return problems


def write_universe(rows, path, read_on):
    rows = sorted(rows, key=lambda r: r["ticker"])
    with open(path, "w", newline="", encoding="utf-8") as f:
        f.write(f"# S&P 500 from Wikipedia ({WIKIPEDIA_URL}), read {read_on}. "
                f"Regenerate with: python -m pipeline.update_universe\n")
        writer = csv.writer(f)
        writer.writerow(["ticker", "name", "sector", "cik"])
        for row in rows:
            writer.writerow([row["ticker"], row["name"], row["sector"], row["cik_override"] or ""])


def main():
    previous = load_universe()
    previous_tickers = {row["ticker"] for row in previous}
    previous_overrides = {row["ticker"]: int(row["cik"]) for row in previous if row.get("cik")}

    # Always check against today's SEC ticker list, not an old saved copy.
    (RAW_DIR / "company_tickers.json").unlink(missing_ok=True)

    rows = parse_constituents(download_wikipedia_page())
    rows, dropped = one_row_per_company(rows, previous_tickers)
    problems = check_against_sec(rows, load_ticker_to_cik(), previous_overrides)
    write_universe(rows, UNIVERSE_CSV, date.today().isoformat())

    tickers = {row["ticker"] for row in rows}
    print(f"Wrote {len(rows)} companies to {UNIVERSE_CSV}")
    print(f"Second share classes left out: {', '.join(sorted(dropped)) or 'none'}")
    print(f"New since the old list: {len(tickers - previous_tickers)}")
    print(f"No longer in the list: {', '.join(sorted(previous_tickers - tickers)) or 'none'}")
    print()
    print("Companies per sector:")
    sectors = pd.Series([row["sector"] for row in rows]).value_counts()
    for sector, count in sectors.items():
        print(f"  {sector:<28}{count:>4}")
    print()
    print(f"CIK checks against the SEC ticker list: {len(problems)} to look at")
    for problem in problems:
        print(f"  {problem}")


if __name__ == "__main__":
    main()
