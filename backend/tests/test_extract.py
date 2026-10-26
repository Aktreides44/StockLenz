"""Integration test: run the extractor on a saved copy of Apple's SEC companyfacts JSON.

Expected values are taken from Apple's 10-K for fiscal 2024 (year ended 28 Sep 2024):
net sales $391,035 million, net income $93,736 million, diluted EPS $6.08.
"""
import json
from pathlib import Path

from pipeline.extract import extract_company, fiscal_year_label

FIXTURE = Path(__file__).parent / "fixtures" / "aapl_companyfacts.json"


def load_apple():
    return extract_company(json.loads(FIXTURE.read_text(encoding="utf-8")))


def test_apple_fy2024_matches_10k():
    fy2024 = load_apple()[2024]
    assert fy2024["end_date"] == "2024-09-28"
    assert fy2024["fields"]["revenue"]["value"] == 391_035_000_000
    assert fy2024["fields"]["revenue"]["tag"] == "RevenueFromContractWithCustomerExcludingAssessedTax"
    assert fy2024["fields"]["net_income"]["value"] == 93_736_000_000
    assert fy2024["fields"]["eps_diluted"]["value"] == 6.08


def test_apple_has_five_consecutive_years():
    years = sorted(load_apple())
    assert len(years) == 5
    assert years == list(range(years[0], years[0] + 5))


def test_fiscal_year_label_early_january_belongs_to_previous_year():
    assert fiscal_year_label("2024-09-28") == 2024
    assert fiscal_year_label("2023-01-01") == 2022  # JNJ's 52/53-week year
    assert fiscal_year_label("2026-01-31") == 2026  # Walmart-style January year end
