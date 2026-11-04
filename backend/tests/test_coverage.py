"""Tests for the coverage report (pipeline/coverage.py)."""
from pipeline.coverage import build_report, general_reason

METRICS = [{"key": "pe", "label": "P/E (FY)"}, {"key": "current_ratio", "label": "Current ratio"}]


def company(ticker, pe, reason=None, financial=False, price_source="Polygon close", day="2026-11-03"):
    return {
        "ticker": ticker, "pe": pe, "current_ratio": None if financial else 1.5,
        "not_applicable": ["current_ratio"] if financial else [],
        "missing_reasons": {"pe": reason} if reason else {},
        "price_source": price_source, "price_fetched_at": day, "shares_source": "SEC cover page (10-Q)",
    }


def test_general_reason_drops_the_year():
    assert general_reason("Diluted EPS not reported in the FY2025 10-K") == "Diluted EPS not reported in the latest 10-K"
    assert general_reason("No 10-K data for FY2022") == "No 10-K data for an earlier year"


def test_report_counts_and_groups_reasons():
    companies = [
        company("AAA", 20.0),
        company("BBB", None, "Diluted EPS is zero or negative (a loss year)"),
        company("CCC", None, "Diluted EPS is zero or negative (a loss year)"),
        company("BNK", 12.0, financial=True),
        company("NEW", 30.0, price_source="Yahoo Finance (backup)", day="2026-11-04T09:00:00"),
    ]
    report = build_report(companies, METRICS, ["AAA", "BBB", "CCC", "BNK", "NEW", "GONE"])
    assert "5 companies in the database · prices as of 2026-11-03." in report  # the day most prices are from
    assert "| P/E (FY) | 3 (60%) | 0 | 2 |" in report
    assert "| Current ratio | 4 (80%) | 1 | 0 |" in report  # the bank is "not applicable", not "missing"
    assert "- 2 × Diluted EPS is zero or negative (a loss year): BBB, CCC" in report
    assert "- Price (no Polygon close): NEW" in report
    assert "GONE" in report.split("## In universe.csv but not in the database")[1]
