"""Unit tests for every indicator, with hand-computed expected values.

Each formula is tested with normal, zero, negative and missing (None) inputs.
"""
from pytest import approx

from pipeline import metrics


# --- revenue_growth: (Rev_t − Rev_t-1) / Rev_t-1 × 100 ---

def test_revenue_growth_normal():
    assert metrics.revenue_growth(110, 100) == approx(10.0)


def test_revenue_growth_decline():
    assert metrics.revenue_growth(80, 100) == approx(-20.0)


def test_revenue_growth_zero_prior_is_none():
    assert metrics.revenue_growth(100, 0) is None


def test_revenue_growth_missing():
    assert metrics.revenue_growth(None, 100) is None
    assert metrics.revenue_growth(100, None) is None


# --- revenue_cagr_3y: (Rev_t / Rev_t-3)^(1/3) − 1, × 100 ---

def test_revenue_cagr_normal():
    # 100 -> 133.1 in 3 years is exactly 10 % per year (1.1^3 = 1.331)
    assert metrics.revenue_cagr_3y(133.1, 100) == approx(10.0)


def test_revenue_cagr_shrinking():
    # 1000 -> 729 is −10 % per year (0.9^3 = 0.729)
    assert metrics.revenue_cagr_3y(729, 1000) == approx(-10.0)


def test_revenue_cagr_zero_or_negative_is_none():
    assert metrics.revenue_cagr_3y(100, 0) is None
    assert metrics.revenue_cagr_3y(100, -50) is None
    assert metrics.revenue_cagr_3y(-100, 50) is None


def test_revenue_cagr_missing():
    assert metrics.revenue_cagr_3y(None, 100) is None
    assert metrics.revenue_cagr_3y(100, None) is None


# --- net_income_growth: (NI_t − NI_t-1) / abs(NI_t-1) × 100 ---

def test_net_income_growth_normal():
    assert metrics.net_income_growth(150, 100) == approx(50.0)


def test_net_income_growth_from_loss_to_smaller_loss_is_positive():
    # −100 -> −50: (−50 − −100) / 100 × 100 = +50
    assert metrics.net_income_growth(-50, -100) == approx(50.0)


def test_net_income_growth_from_profit_to_loss():
    # 100 -> −20: (−20 − 100) / 100 × 100 = −120
    assert metrics.net_income_growth(-20, 100) == approx(-120.0)


def test_net_income_growth_zero_prior_is_none():
    assert metrics.net_income_growth(100, 0) is None


def test_net_income_growth_missing():
    assert metrics.net_income_growth(None, 100) is None
    assert metrics.net_income_growth(100, None) is None


# --- eps_growth: null if prior EPS ≤ 0 ---

def test_eps_growth_normal():
    assert metrics.eps_growth(2.50, 2.00) == approx(25.0)


def test_eps_growth_current_negative_is_allowed():
    # 2.00 -> −1.00: (−1 − 2) / 2 × 100 = −150
    assert metrics.eps_growth(-1.00, 2.00) == approx(-150.0)


def test_eps_growth_prior_zero_or_negative_is_none():
    assert metrics.eps_growth(1.00, 0) is None
    assert metrics.eps_growth(1.00, -0.50) is None


def test_eps_growth_missing():
    assert metrics.eps_growth(None, 2.00) is None
    assert metrics.eps_growth(2.00, None) is None


# --- net_margin and operating_margin: X / Rev × 100 ---

def test_net_margin_normal():
    assert metrics.net_margin(25, 200) == approx(12.5)


def test_net_margin_loss():
    assert metrics.net_margin(-30, 200) == approx(-15.0)


def test_net_margin_zero_revenue_is_none():
    assert metrics.net_margin(25, 0) is None


def test_net_margin_zero_income_is_zero_not_none():
    # A real zero is a real value; only a missing input gives None.
    assert metrics.net_margin(0, 200) == 0


def test_net_margin_missing():
    assert metrics.net_margin(None, 200) is None
    assert metrics.net_margin(25, None) is None


def test_operating_margin_normal():
    assert metrics.operating_margin(30, 120) == approx(25.0)


def test_operating_margin_negative():
    assert metrics.operating_margin(-12, 120) == approx(-10.0)


def test_operating_margin_zero_revenue_and_missing():
    assert metrics.operating_margin(30, 0) is None
    assert metrics.operating_margin(None, 120) is None


# --- roe: NI / average(Equity_t, Equity_t-1) × 100; null if avg equity ≤ 0 ---

def test_roe_normal():
    # average equity = (90 + 110) / 2 = 100 -> 20 / 100 = 20 %
    assert metrics.roe(20, 110, 90) == approx(20.0)


def test_roe_net_loss():
    assert metrics.roe(-10, 110, 90) == approx(-10.0)


def test_roe_zero_or_negative_average_equity_is_none():
    assert metrics.roe(20, 50, -50) is None   # average 0
    assert metrics.roe(20, -100, -50) is None  # average negative


def test_roe_missing():
    assert metrics.roe(None, 110, 90) is None
    assert metrics.roe(20, 110, None) is None


# --- roa: NI / average(Assets_t, Assets_t-1) × 100 ---

def test_roa_normal():
    # average assets = (450 + 550) / 2 = 500 -> 25 / 500 = 5 %
    assert metrics.roa(25, 550, 450) == approx(5.0)


def test_roa_negative_income():
    assert metrics.roa(-25, 550, 450) == approx(-5.0)


def test_roa_zero_assets_is_none():
    assert metrics.roa(25, 0, 0) is None


def test_roa_missing():
    assert metrics.roa(25, 550, None) is None
    assert metrics.roa(None, 550, 450) is None


# --- debt_to_equity: LTD / Equity; null if equity ≤ 0 or Financials ---

def test_debt_to_equity_normal():
    assert metrics.debt_to_equity(150, 100) == approx(1.5)


def test_debt_to_equity_zero_debt_is_zero():
    assert metrics.debt_to_equity(0, 100) == 0


def test_debt_to_equity_zero_or_negative_equity_is_none():
    assert metrics.debt_to_equity(150, 0) is None
    assert metrics.debt_to_equity(150, -20) is None


def test_debt_to_equity_missing():
    assert metrics.debt_to_equity(None, 100) is None
    assert metrics.debt_to_equity(150, None) is None


def test_debt_to_equity_financials_is_none():
    assert metrics.debt_to_equity(150, 100, is_financial=True) is None


# --- current_ratio: CA / CL; null for Financials ---

def test_current_ratio_normal():
    assert metrics.current_ratio(300, 200) == approx(1.5)


def test_current_ratio_zero_liabilities_is_none():
    assert metrics.current_ratio(300, 0) is None


def test_current_ratio_missing():
    assert metrics.current_ratio(None, 200) is None
    assert metrics.current_ratio(300, None) is None


def test_current_ratio_financials_is_none():
    assert metrics.current_ratio(300, 200, is_financial=True) is None


# --- fcf and fcf_margin ---

def test_fcf_normal():
    assert metrics.fcf(120, 20) == 100


def test_fcf_can_be_negative():
    assert metrics.fcf(10, 40) == -30


def test_fcf_zero_capex():
    assert metrics.fcf(120, 0) == 120


def test_fcf_missing():
    assert metrics.fcf(None, 20) is None
    assert metrics.fcf(120, None) is None


def test_fcf_margin_normal():
    assert metrics.fcf_margin(30, 200) == approx(15.0)


def test_fcf_margin_negative():
    assert metrics.fcf_margin(-30, 200) == approx(-15.0)


def test_fcf_margin_zero_revenue_and_missing():
    assert metrics.fcf_margin(30, 0) is None
    assert metrics.fcf_margin(None, 200) is None


# --- market_cap: Price × shares ---

def test_market_cap_normal():
    assert metrics.market_cap(50.0, 1_000_000) == approx(50_000_000)


def test_market_cap_missing():
    assert metrics.market_cap(None, 1_000_000) is None
    assert metrics.market_cap(50.0, None) is None


# --- pe: Price / EPS; null if EPS ≤ 0 ---

def test_pe_normal():
    assert metrics.pe(100.0, 4.0) == approx(25.0)


def test_pe_zero_or_negative_eps_is_none():
    assert metrics.pe(100.0, 0) is None
    assert metrics.pe(100.0, -2.0) is None


def test_pe_missing():
    assert metrics.pe(None, 4.0) is None
    assert metrics.pe(100.0, None) is None


# --- pb: MarketCap / Equity; null if equity ≤ 0 ---

def test_pb_normal():
    assert metrics.pb(1000, 250) == approx(4.0)


def test_pb_zero_or_negative_equity_is_none():
    assert metrics.pb(1000, 0) is None
    assert metrics.pb(1000, -100) is None


def test_pb_missing():
    assert metrics.pb(None, 250) is None
    assert metrics.pb(1000, None) is None


# --- ps: MarketCap / Rev ---

def test_ps_normal():
    assert metrics.ps(1000, 400) == approx(2.5)


def test_ps_zero_revenue_is_none():
    assert metrics.ps(1000, 0) is None


def test_ps_missing():
    assert metrics.ps(None, 400) is None
    assert metrics.ps(1000, None) is None


# --- compute_all: picks the right years and passes the Financials flag ---

def make_years(data):
    """Build the extract_company() shape from {year: {field: value}}."""
    from pipeline.extract import FIELDS
    years = {}
    for year, values in data.items():
        fields = {f: None for f in FIELDS}
        for f, v in values.items():
            fields[f] = {"value": v, "tag": "TestTag"}
        years[year] = {"end_date": f"{year}-12-31", "fields": fields}
    return years


def test_compute_all_uses_latest_and_prior_years():
    years = make_years({
        2021: {"revenue": 100},
        2023: {"revenue": 100, "equity": 90, "total_assets": 450},
        2024: {"revenue": 133.1, "net_income": 20, "equity": 110, "total_assets": 550,
               "eps_diluted": 4.0, "operating_cash_flow": 30, "capex": 10,
               "current_assets": 300, "current_liabilities": 200, "long_term_debt": 55},
    })
    result = metrics.compute_all(years, price=100.0, shares_outstanding=2, is_financial=False)
    assert result["revenue_growth"] == approx(33.1)
    assert result["revenue_cagr_3y"] == approx(10.0)
    assert result["roe"] == approx(20.0)
    assert result["roa"] == approx(20 / 500 * 100)
    assert result["fcf"] == 20
    assert result["market_cap"] == approx(200.0)
    assert result["pe"] == approx(25.0)
    assert result["current_ratio"] == approx(1.5)
    assert result["debt_to_equity"] == approx(0.5)
    assert result["operating_margin"] is None   # operating income not reported
    assert result["net_income_growth"] is None  # no prior net income


def test_compute_all_financials_flag():
    years = make_years({2024: {"current_assets": 300, "current_liabilities": 200,
                               "long_term_debt": 50, "equity": 100}})
    result = metrics.compute_all(years, price=None, shares_outstanding=None, is_financial=True)
    assert result["current_ratio"] is None
    assert result["debt_to_equity"] is None
    assert result["market_cap"] is None
    assert result["pe"] is None
