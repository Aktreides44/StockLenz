"""Tests for building universe.csv from the Wikipedia S&P 500 table (on a saved sample, no internet)."""
from pathlib import Path

from pipeline import refresh
from pipeline.sec_client import sec_ticker
from pipeline.update_universe import (
    check_against_sec, one_row_per_company, parse_constituents, readable_name, write_universe,
)

SAMPLE = Path(__file__).parent / "fixtures" / "sp500_sample.html"

# What the SEC ticker list says (it writes BRK-B with a dash; it does not know NEWCO).
SEC_TICKERS = {"AAPL": 320193, "BRK-B": 1067983, "GOOGL": 1652044, "GOOG": 1652044,
               "XOM": 2075101, "ODD": 222}


def sample_rows():
    return parse_constituents(SAMPLE.read_text(encoding="utf-8"))


def test_parse_reads_ticker_name_sector_and_cik():
    rows = sample_rows()
    assert len(rows) == 7
    assert rows[0] == {"ticker": "AAPL", "name": "Apple Inc.", "sector": "Information Technology", "cik": 320193}
    assert rows[1]["ticker"] == "BRK.B"  # Wikipedia's spelling is kept in universe.csv


def test_readable_names():
    assert readable_name("Coca-Cola Company (The)") == "The Coca-Cola Company"
    assert readable_name("Lilly (Eli)") == "Eli Lilly"
    assert readable_name("Alphabet Inc. (Class A)") == "Alphabet Inc. (Class A)"  # handled by one_row_per_company
    assert readable_name("Apple Inc.") == "Apple Inc."


def test_sec_ticker_uses_a_dash():
    assert sec_ticker("BRK.B") == "BRK-B"
    assert sec_ticker("AAPL") == "AAPL"


def test_one_row_per_company_prefers_the_old_ticker_then_class_a():
    kept, dropped = one_row_per_company(sample_rows(), previous_tickers=set())
    alphabet = [row for row in kept if row["cik"] == 1652044]
    assert [row["ticker"] for row in alphabet] == ["GOOGL"]  # the "(Class A)" row
    assert alphabet[0]["name"] == "Alphabet Inc."  # the class is removed from the name
    assert dropped == ["GOOG"]

    # A ticker we already had wins, so the list does not jump between share classes.
    kept, dropped = one_row_per_company(sample_rows(), previous_tickers={"GOOG"})
    assert "GOOG" in [row["ticker"] for row in kept]
    assert dropped == ["GOOGL"]


def test_check_against_sec_sets_overrides_and_reports_problems():
    rows, _ = one_row_per_company(sample_rows(), previous_tickers=set())
    problems = check_against_sec(rows, SEC_TICKERS, previous_overrides={"XOM": 34088})
    override = {row["ticker"]: row["cik_override"] for row in rows}

    assert override["AAPL"] is None  # SEC list and Wikipedia agree: no override needed
    assert override["BRK.B"] is None  # found in the SEC list as BRK-B
    assert override["XOM"] == 34088  # the manual override from the old universe.csv is kept
    assert override["NEWCO"] == 9999999  # not in the SEC list: Wikipedia's CIK
    assert override["ODD"] == 111  # disagreement: Wikipedia's CIK, and it is reported
    assert problems == [
        "NEWCO: not in the SEC ticker list, using Wikipedia's CIK 9999999",
        "ODD: SEC list says CIK 222, Wikipedia says 111 (using Wikipedia's)",
    ]


def test_written_file_has_the_date_and_the_pipeline_can_read_it(tmp_path, monkeypatch):
    rows, _ = one_row_per_company(sample_rows(), previous_tickers=set())
    check_against_sec(rows, SEC_TICKERS, previous_overrides={"XOM": 34088})
    path = tmp_path / "universe.csv"
    write_universe(rows, path, "2026-11-04")

    first_line = path.read_text(encoding="utf-8").splitlines()[0]
    assert first_line.startswith("# S&P 500 from Wikipedia") and "read 2026-11-04" in first_line

    monkeypatch.setattr(refresh, "UNIVERSE_CSV", path)
    universe = refresh.load_universe()  # skips the "#" line
    assert [row["ticker"] for row in universe] == ["AAPL", "BRK.B", "GOOGL", "NEWCO", "ODD", "XOM"]
    assert next(row for row in universe if row["ticker"] == "XOM")["cik"] == "34088"
    assert next(row for row in universe if row["ticker"] == "AAPL")["cik"] == ""
