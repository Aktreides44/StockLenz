"""Tests for the rule-based pros and cons."""
from pipeline.analysis import format_money, pros_and_cons


def ids(items):
    return [item["id"] for item in items]


def test_all_pros_triggered():
    metrics = {"roe": 25.0, "revenue_cagr_3y": 12.0, "debt_to_equity": 0.3, "fcf": 5e9, "net_margin": 20.0}
    result = pros_and_cons(metrics, [], latest_equity=100e9)
    assert ids(result["pros"]) == ["high_roe", "revenue_cagr_high", "low_debt", "positive_fcf", "high_net_margin"]
    assert result["cons"] == []
    assert result["pros"][0]["text"] == "Strong return on equity: ROE of 25.0% (above 15%)"
    assert result["pros"][3]["text"] == "Positive free cash flow of $5.0B"


def test_all_cons_triggered():
    metrics = {"revenue_growth": -4.2, "debt_to_equity": 2.5, "pe": 55.0, "fcf": -300e6}
    result = pros_and_cons(metrics, [], latest_equity=-2e9)
    assert ids(result["cons"]) == ["revenue_decline", "high_debt", "negative_equity", "high_pe", "negative_fcf"]
    assert result["cons"][0]["text"] == "Revenue fell 4.2% in the latest fiscal year"
    assert result["cons"][4]["text"] == "Negative free cash flow of -$300M"


def test_thresholds_are_strict():
    # Exactly on the threshold triggers nothing
    metrics = {"roe": 15.0, "revenue_cagr_3y": 10.0, "debt_to_equity": 0.5, "fcf": 0, "net_margin": 15.0,
               "revenue_growth": 0.0, "pe": 40.0}
    result = pros_and_cons(metrics, [], latest_equity=0)
    assert result == {"pros": [], "cons": []}


def test_missing_metrics_skip_their_rules():
    metrics = {"roe": None, "revenue_cagr_3y": None, "debt_to_equity": None, "fcf": None, "net_margin": None,
               "revenue_growth": None, "pe": None}
    assert pros_and_cons(metrics, [], latest_equity=None) == {"pros": [], "cons": []}


def test_not_applicable_metrics_skip_their_rules():
    # A bank: D/E is not meaningful, so neither "low debt" nor "high debt" may appear
    metrics = {"debt_to_equity": 0.1, "roe": 16.0}
    result = pros_and_cons(metrics, ["debt_to_equity", "current_ratio"], latest_equity=300e9)
    assert ids(result["pros"]) == ["high_roe"]
    metrics = {"debt_to_equity": 9.0}
    assert pros_and_cons(metrics, ["debt_to_equity"], latest_equity=300e9)["cons"] == []


def test_format_money():
    assert format_money(5.02e12) == "$5.02T"
    assert format_money(1.25e9) == "$1.2B"
    assert format_money(-340e6) == "-$340M"
