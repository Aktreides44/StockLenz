"""Tests for TTM (trailing twelve months) from 10-K + 10-Q values (pipeline/ttm.py).

The numbers are Apple's: FY2025 (ended 27 Sep 2025) revenue $416.161B; 9 months to 27 Jun 2026
$364.357B; 9 months to 28 Jun 2025 $313.695B -> TTM $466.823B. EPS: 7.46 + 6.88 − 5.62 = 8.72.
"""
import pytest

from pipeline.ttm import extract_ttm, ttm_value

FY_END = "2025-09-27"


def period(start, end, val, form="10-Q", filed="2026-07-31"):
    return {"start": start, "end": end, "val": val, "form": form, "fp": "Q3" if form == "10-Q" else "FY",
            "filed": filed}


def facts(tag_entries, unit="USD"):
    return {"facts": {"us-gaap": {tag: {"units": {unit: entries}} for tag, entries in tag_entries.items()}}}


def latest_year(field, value, tag):
    return {"end_date": FY_END, "fields": {field: {"value": value, "tag": tag}}}


REVENUE_TAG = "RevenueFromContractWithCustomerExcludingAssessedTax"
APPLE_REVENUE = [
    period("2024-09-29", FY_END, 416_161e6, form="10-K", filed="2025-10-31"),
    period("2024-09-29", "2025-06-28", 313_695e6),  # same 9 months, one year earlier
    period("2025-09-28", "2026-06-27", 364_357e6),  # this year so far (9 months)
    period("2026-03-29", "2026-06-27", 109_417e6),  # the 3-month quarter alone: not used
    period("2025-09-28", "2026-03-28", 254_940e6, filed="2026-05-01"),  # an older 6-month value: not used
]


def test_ttm_is_the_year_plus_this_year_minus_the_same_months_last_year():
    result = ttm_value(facts({REVENUE_TAG: APPLE_REVENUE}), "revenue", latest_year("revenue", 416_161e6, REVENUE_TAG))
    assert result == {"value": pytest.approx(466_823e6), "end": "2026-06-27", "tag": REVENUE_TAG}


def test_when_the_10k_is_the_latest_report_ttm_is_the_fiscal_year():
    only_10k = facts({REVENUE_TAG: APPLE_REVENUE[:1]})
    assert ttm_value(only_10k, "revenue", latest_year("revenue", 416_161e6, REVENUE_TAG)) == {
        "value": 416_161e6, "end": FY_END, "tag": REVENUE_TAG,
    }


def test_without_the_comparison_period_there_is_no_ttm():
    no_comparison = facts({REVENUE_TAG: [APPLE_REVENUE[0], APPLE_REVENUE[2]]})
    assert ttm_value(no_comparison, "revenue", latest_year("revenue", 416_161e6, REVENUE_TAG)) is None


def test_another_tag_with_the_same_fiscal_year_value_can_supply_the_quarters():
    # JPMorgan-like: the 10-K uses "Revenues", the 10-Qs "RevenuesNetOfInterestExpense" (same FY value).
    data = facts({"Revenues": APPLE_REVENUE[:1], "RevenuesNetOfInterestExpense": APPLE_REVENUE})
    result = ttm_value(data, "revenue", latest_year("revenue", 416_161e6, "Revenues"))
    assert result["value"] == pytest.approx(466_823e6)
    assert result["tag"] == "RevenuesNetOfInterestExpense"


def test_another_tag_with_a_different_fiscal_year_value_is_not_used():
    different = [dict(entry, val=entry["val"] * 0.9) for entry in APPLE_REVENUE]  # a different definition
    data = facts({"Revenues": APPLE_REVENUE[:1], "RevenuesNetOfInterestExpense": different})
    assert ttm_value(data, "revenue", latest_year("revenue", 416_161e6, "Revenues"))["end"] == FY_END  # FY only


def test_extract_ttm_for_revenue_net_income_and_eps():
    eps = [period("2024-09-29", FY_END, 7.46, form="10-K"), period("2024-09-29", "2025-06-28", 5.62),
           period("2025-09-28", "2026-06-27", 6.88)]
    data = facts({REVENUE_TAG: APPLE_REVENUE})
    data["facts"]["us-gaap"]["EarningsPerShareDiluted"] = {"units": {"USD/shares": eps}}
    years = {2025: {"end_date": FY_END, "fields": {
        "revenue": {"value": 416_161e6, "tag": REVENUE_TAG},
        "net_income": None,  # not reported: no TTM either
        "eps_diluted": {"value": 7.46, "tag": "EarningsPerShareDiluted"},
    }}}
    ttm = extract_ttm(data, years)
    assert ttm["end"] == "2026-06-27"
    assert ttm["revenue"] == pytest.approx(466_823e6)
    assert ttm["eps_diluted"] == pytest.approx(8.72)
    assert ttm["net_income"] is None
