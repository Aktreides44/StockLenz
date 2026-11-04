"""Tests for shares outstanding from the SEC (pipeline/shares.py), on small hand-made companyfacts."""
from pipeline.shares import extract_shares


def fact(end, val, form="10-Q", filed=None):
    return {"end": end, "val": val, "form": form, "filed": filed or end}


def companyfacts(cover=(), balance=(), average=()):
    facts = {"dei": {}, "us-gaap": {}}
    if cover:
        facts["dei"]["EntityCommonStockSharesOutstanding"] = {"units": {"shares": list(cover)}}
    if balance:
        facts["us-gaap"]["CommonStockSharesOutstanding"] = {"units": {"shares": list(balance)}}
    if average:
        facts["us-gaap"]["WeightedAverageNumberOfSharesOutstandingBasic"] = {"units": {"shares": list(average)}}
    return {"facts": facts}


def test_cover_page_wins_and_the_newest_filing_is_used():
    # Apple-like: several cover-page values, the 10-Q of July 2026 is the newest.
    data = companyfacts(
        cover=[fact("2025-10-17", 14_776_353_000, "10-K"), fact("2026-07-17", 14_594_180_000)],
        balance=[fact("2026-06-27", 14_600_000_000)],
    )
    assert extract_shares(data, "2025-09-27") == {
        "value": 14_594_180_000, "as_of": "2026-07-17", "source": "SEC cover page (10-Q)",
    }


def test_balance_sheet_when_there_is_no_cover_page_number():
    # Alphabet-like: the cover page is split by share class, so companyfacts has no cover number.
    data = companyfacts(balance=[fact("2026-06-30", 12_230_000_000)], average=[fact("2026-06-30", 12_125_000_000)])
    result = extract_shares(data, "2025-12-31")
    assert result["value"] == 12_230_000_000
    assert result["source"] == "SEC balance sheet (10-Q)"


def test_old_numbers_are_skipped():
    # Nike-like: the last cover-page number is from 2015, far too old for FY2026 figures.
    data = companyfacts(cover=[fact("2015-07-17", 855_351_589, "10-K")], average=[fact("2026-08-31", 1_483_600_000)])
    result = extract_shares(data, "2026-05-31")
    assert result == {"value": 1_483_600_000, "as_of": "2026-08-31", "source": "SEC average shares in the period (10-Q)"}


def test_nothing_usable_gives_none():
    # Visa-like: only a cover-page number from 2010.
    assert extract_shares(companyfacts(cover=[fact("2010-01-27", 469_280_842)]), "2025-09-30") is None
    assert extract_shares({"facts": {}}, "2025-09-30") is None


def test_other_forms_and_zero_values_are_ignored():
    data = companyfacts(cover=[fact("2026-03-01", 0), fact("2026-02-01", 5_000, "8-K"), fact("2026-01-15", 1_000)])
    assert extract_shares(data, "2025-12-31")["value"] == 1_000
