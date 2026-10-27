"""The MVP indicators, as small pure functions.

Rules (from CLAUDE.md):
- Any missing input, or a division by a missing or zero denominator, gives None.
- We never substitute 0 for a missing value.
- Percentages are returned as percent numbers (12.5 means 12.5 %).
"""


def safe_divide(numerator, denominator):
    """numerator / denominator, or None if either is missing or the denominator is zero."""
    if numerator is None or denominator is None or denominator == 0:
        return None
    return numerator / denominator


def as_percent(ratio):
    return None if ratio is None else ratio * 100


def average(a, b):
    if a is None or b is None:
        return None
    return (a + b) / 2


# --- Growth ---

def revenue_growth(revenue, revenue_prev):
    """(Rev_t − Rev_t-1) / Rev_t-1 × 100"""
    if revenue is None or revenue_prev is None:
        return None
    return as_percent(safe_divide(revenue - revenue_prev, revenue_prev))


def revenue_cagr_3y(revenue, revenue_3y_ago):
    """(Rev_t / Rev_t-3)^(1/3) − 1, × 100. None unless both revenues are positive."""
    if revenue is None or revenue_3y_ago is None or revenue <= 0 or revenue_3y_ago <= 0:
        return None
    return ((revenue / revenue_3y_ago) ** (1 / 3) - 1) * 100


def net_income_growth(net_income, net_income_prev):
    """(NI_t − NI_t-1) / abs(NI_t-1) × 100; None if NI_t-1 is 0 or missing.

    abs() keeps the sign meaningful when the previous year was a loss:
    going from −100 to −50 is an improvement, so growth is +50 %.
    """
    if net_income is None or net_income_prev is None:
        return None
    return as_percent(safe_divide(net_income - net_income_prev, abs(net_income_prev)))


def eps_growth(eps, eps_prev):
    """(EPS_t − EPS_t-1) / EPS_t-1 × 100; None if prior EPS ≤ 0 or missing."""
    if eps is None or eps_prev is None or eps_prev <= 0:
        return None
    return as_percent(safe_divide(eps - eps_prev, eps_prev))


# --- Profitability ---

def net_margin(net_income, revenue):
    """NI / Rev × 100"""
    return as_percent(safe_divide(net_income, revenue))


def operating_margin(operating_income, revenue):
    """OpInc / Rev × 100"""
    return as_percent(safe_divide(operating_income, revenue))


def roe(net_income, equity, equity_prev):
    """NI / average(Equity_t, Equity_t-1) × 100; None if average equity ≤ 0."""
    avg_equity = average(equity, equity_prev)
    if avg_equity is None or avg_equity <= 0:
        return None
    return as_percent(safe_divide(net_income, avg_equity))


def roa(net_income, assets, assets_prev):
    """NI / average(Assets_t, Assets_t-1) × 100"""
    return as_percent(safe_divide(net_income, average(assets, assets_prev)))


# --- Financial health (not meaningful for banks/insurers) ---

def debt_to_equity(long_term_debt, equity, is_financial=False):
    """LongTermDebt / Equity; None if equity ≤ 0, or for Financials."""
    if is_financial or equity is None or equity <= 0:
        return None
    return safe_divide(long_term_debt, equity)


def current_ratio(current_assets, current_liabilities, is_financial=False):
    """CurrentAssets / CurrentLiabilities; None for Financials."""
    if is_financial:
        return None
    return safe_divide(current_assets, current_liabilities)


# --- Cash flow ---

def fcf(operating_cash_flow, capex):
    """OCF − Capex (capex is reported as a positive payment)."""
    if operating_cash_flow is None or capex is None:
        return None
    return operating_cash_flow - capex


def fcf_margin(free_cash_flow, revenue):
    """FCF / Rev × 100"""
    return as_percent(safe_divide(free_cash_flow, revenue))


# --- Valuation ---

def market_cap(price, shares_outstanding):
    """Price × shares outstanding"""
    if price is None or shares_outstanding is None:
        return None
    return price * shares_outstanding


def pe(price, eps):
    """Price / diluted EPS; None if EPS ≤ 0."""
    if eps is None or eps <= 0:
        return None
    return safe_divide(price, eps)


def pb(market_capitalization, equity):
    """MarketCap / Equity; None if equity ≤ 0."""
    if equity is None or equity <= 0:
        return None
    return safe_divide(market_capitalization, equity)


def ps(market_capitalization, revenue):
    """MarketCap / Rev"""
    return safe_divide(market_capitalization, revenue)


# Metrics that are not meaningful for banks and insurers.
NOT_APPLICABLE_FOR_FINANCIALS = ["current_ratio", "debt_to_equity"]

# Definitions shown in the app. unit is one of: "%", "x" (a ratio), "USD".
METRIC_DEFINITIONS = [
    # key, label, group, formula, unit, higher_is_better
    ("revenue_growth", "Revenue growth", "Growth", "(Rev_t − Rev_t-1) / Rev_t-1 × 100", "%", True),
    ("revenue_cagr_3y", "Revenue CAGR 3y", "Growth", "((Rev_t / Rev_t-3)^(1/3) − 1) × 100", "%", True),
    ("net_income_growth", "Net income growth", "Growth", "(NI_t − NI_t-1) / |NI_t-1| × 100", "%", True),
    ("eps_growth", "EPS growth", "Growth", "(EPS_t − EPS_t-1) / EPS_t-1 × 100, diluted EPS; empty if prior EPS ≤ 0", "%", True),
    ("net_margin", "Net margin", "Profitability", "Net income / Revenue × 100", "%", True),
    ("operating_margin", "Operating margin", "Profitability", "Operating income / Revenue × 100", "%", True),
    ("roe", "ROE", "Profitability", "Net income / average(Equity_t, Equity_t-1) × 100", "%", True),
    ("roa", "ROA", "Profitability", "Net income / average(Assets_t, Assets_t-1) × 100", "%", True),
    ("debt_to_equity", "Debt / Equity", "Financial health", "Long-term debt / Shareholders' equity (not shown for Financials)", "x", False),
    ("current_ratio", "Current ratio", "Financial health", "Current assets / Current liabilities (not shown for Financials)", "x", True),
    ("fcf", "Free cash flow", "Cash flow", "Operating cash flow − Capital expenditure", "USD", True),
    ("fcf_margin", "FCF margin", "Cash flow", "Free cash flow / Revenue × 100", "%", True),
    ("market_cap", "Market cap", "Valuation", "Price × Shares outstanding", "USD", True),
    ("pe", "P/E (FY)", "Valuation",
     "Current price / Diluted EPS of the latest fiscal year (not trailing 12 months); empty if EPS ≤ 0", "x", False),
    ("pb", "P/B (FY)", "Valuation",
     "Current market cap / Shareholders' equity at the latest fiscal year end; empty if equity ≤ 0", "x", False),
    ("ps", "P/S (FY)", "Valuation",
     "Current market cap / Revenue of the latest fiscal year (not trailing 12 months)", "x", False),
]

METRIC_KEYS = [definition[0] for definition in METRIC_DEFINITIONS]

FIELD_LABELS = {
    "revenue": "Revenue",
    "net_income": "Net income",
    "operating_income": "Operating income",
    "eps_diluted": "Diluted EPS",
    "total_assets": "Total assets",
    "current_assets": "Current assets",
    "current_liabilities": "Current liabilities",
    "equity": "Shareholders' equity",
    "long_term_debt": "Long-term debt",
    "operating_cash_flow": "Operating cash flow",
    "capex": "Capital expenditure",
    "dividends_paid": "Dividends paid",
}

# The inputs each metric needs: (raw field, how many years before the latest year).
# "price" and "shares" come from Yahoo Finance instead of the 10-K.
METRIC_INPUTS = {
    "revenue_growth": [("revenue", 0), ("revenue", 1)],
    "revenue_cagr_3y": [("revenue", 0), ("revenue", 3)],
    "net_income_growth": [("net_income", 0), ("net_income", 1)],
    "eps_growth": [("eps_diluted", 0), ("eps_diluted", 1)],
    "net_margin": [("net_income", 0), ("revenue", 0)],
    "operating_margin": [("operating_income", 0), ("revenue", 0)],
    "roe": [("net_income", 0), ("equity", 0), ("equity", 1)],
    "roa": [("net_income", 0), ("total_assets", 0), ("total_assets", 1)],
    "debt_to_equity": [("long_term_debt", 0), ("equity", 0)],
    "current_ratio": [("current_assets", 0), ("current_liabilities", 0)],
    "fcf": [("operating_cash_flow", 0), ("capex", 0)],
    "fcf_margin": [("operating_cash_flow", 0), ("capex", 0), ("revenue", 0)],
    "market_cap": [("price", 0), ("shares", 0)],
    "pe": [("price", 0), ("eps_diluted", 0)],
    "pb": [("price", 0), ("shares", 0), ("equity", 0)],
    "ps": [("price", 0), ("shares", 0), ("revenue", 0)],
}


def missing_reason(key, years, price, shares_outstanding, is_financial):
    """Explain in plain words why metric `key` has no value. Shown as the tooltip on "—"."""
    if is_financial and key in NOT_APPLICABLE_FOR_FINANCIALS:
        return "Not meaningful for banks and insurers (Financials sector)"

    latest = max(years)
    for field, years_back in METRIC_INPUTS[key]:
        if field == "price":
            if price is None:
                return "No current share price available"
            continue
        if field == "shares":
            if shares_outstanding is None:
                return "Shares outstanding not available"
            continue
        year = latest - years_back
        if year not in years:
            return f"No 10-K data for FY{year}"
        if years[year]["fields"][field] is None:
            return f"{FIELD_LABELS[field]} not reported in the FY{year} 10-K"

    # All inputs exist, so one of the sign rules (or a zero denominator) left it empty.
    if key == "roe":
        return "Average shareholders' equity is zero or negative"
    if key in ("debt_to_equity", "pb"):
        return "Shareholders' equity is zero or negative"
    if key == "pe":
        return "Diluted EPS is zero or negative (a loss year)"
    if key == "eps_growth":
        return "Prior-year EPS is zero or negative, so growth is not meaningful"
    if key == "revenue_cagr_3y":
        return "Revenue is zero or negative"
    return "Cannot be calculated: the denominator is zero"


def explain_missing(values, years, price, shares_outstanding, is_financial):
    """Return {metric_key: reason} for every metric in `values` that is None."""
    return {
        key: missing_reason(key, years, price, shares_outstanding, is_financial)
        for key, value in values.items()
        if value is None
    }


def compute_all(years, price, shares_outstanding, is_financial):
    """Compute every metric for the latest fiscal year in `years` (the output of extract_company).

    Returns {metric_key: value or None}.
    """
    latest = max(years)

    def value(year, field):
        if year not in years:
            return None
        cell = years[year]["fields"][field]
        return None if cell is None else cell["value"]

    def now(field):
        return value(latest, field)

    def prev(field):
        return value(latest - 1, field)

    company_fcf = fcf(now("operating_cash_flow"), now("capex"))
    company_market_cap = market_cap(price, shares_outstanding)

    return {
        "revenue_growth": revenue_growth(now("revenue"), prev("revenue")),
        "revenue_cagr_3y": revenue_cagr_3y(now("revenue"), value(latest - 3, "revenue")),
        "net_income_growth": net_income_growth(now("net_income"), prev("net_income")),
        "eps_growth": eps_growth(now("eps_diluted"), prev("eps_diluted")),
        "net_margin": net_margin(now("net_income"), now("revenue")),
        "operating_margin": operating_margin(now("operating_income"), now("revenue")),
        "roe": roe(now("net_income"), now("equity"), prev("equity")),
        "roa": roa(now("net_income"), now("total_assets"), prev("total_assets")),
        "debt_to_equity": debt_to_equity(now("long_term_debt"), now("equity"), is_financial),
        "current_ratio": current_ratio(now("current_assets"), now("current_liabilities"), is_financial),
        "fcf": company_fcf,
        "fcf_margin": fcf_margin(company_fcf, now("revenue")),
        "market_cap": company_market_cap,
        "pe": pe(price, now("eps_diluted")),
        "pb": pb(company_market_cap, now("equity")),
        "ps": ps(company_market_cap, now("revenue")),
    }
