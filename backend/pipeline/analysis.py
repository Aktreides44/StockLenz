"""Rule-based pros and cons for the company page.

These are simple, transparent threshold rules on the metrics, not investment advice.
A rule is skipped when its metric is missing (None) or not applicable for the company.
"""

# Thresholds, in the metric's own unit (percent or ratio)
HIGH_ROE = 15.0
HIGH_REVENUE_CAGR = 10.0
LOW_DEBT_TO_EQUITY = 0.5
HIGH_NET_MARGIN = 15.0
HIGH_DEBT_TO_EQUITY = 2.0
HIGH_PE = 40.0


def format_money(value):
    """$1.2B style, like the app."""
    sign = "-" if value < 0 else ""
    amount = abs(value)
    if amount >= 1e12:
        return f"{sign}${amount / 1e12:.2f}T"
    if amount >= 1e9:
        return f"{sign}${amount / 1e9:.1f}B"
    return f"{sign}${amount / 1e6:,.0f}M"


def pros_and_cons(metrics, not_applicable, latest_equity):
    """Return {"pros": [...], "cons": [...]}, each item {"id": rule id, "text": explanation}.

    metrics: {metric_key: value or None} for the latest fiscal year
    not_applicable: metric keys that make no sense for this company (e.g. D/E for banks)
    latest_equity: shareholders' equity at the latest fiscal year end, or None
    """

    def get(key):
        if key in not_applicable:
            return None
        return metrics.get(key)

    pros = []
    cons = []

    roe = get("roe")
    if roe is not None and roe > HIGH_ROE:
        pros.append({"id": "high_roe", "text": f"Strong return on equity: ROE of {roe:.1f}% (above {HIGH_ROE:.0f}%)"})

    cagr = get("revenue_cagr_3y")
    if cagr is not None and cagr > HIGH_REVENUE_CAGR:
        pros.append({"id": "revenue_cagr_high",
                     "text": f"Revenue grew {cagr:.1f}% per year over the last 3 years (above {HIGH_REVENUE_CAGR:.0f}%)"})

    debt_to_equity = get("debt_to_equity")
    if debt_to_equity is not None and debt_to_equity < LOW_DEBT_TO_EQUITY:
        pros.append({"id": "low_debt",
                     "text": f"Low long-term debt: debt/equity of {debt_to_equity:.2f} (below {LOW_DEBT_TO_EQUITY})"})

    free_cash_flow = get("fcf")
    if free_cash_flow is not None and free_cash_flow > 0:
        pros.append({"id": "positive_fcf", "text": f"Positive free cash flow of {format_money(free_cash_flow)}"})

    net_margin = get("net_margin")
    if net_margin is not None and net_margin > HIGH_NET_MARGIN:
        pros.append({"id": "high_net_margin",
                     "text": f"High net margin of {net_margin:.1f}% (above {HIGH_NET_MARGIN:.0f}%)"})

    revenue_growth = get("revenue_growth")
    if revenue_growth is not None and revenue_growth < 0:
        cons.append({"id": "revenue_decline",
                     "text": f"Revenue fell {abs(revenue_growth):.1f}% in the latest fiscal year"})

    if debt_to_equity is not None and debt_to_equity > HIGH_DEBT_TO_EQUITY:
        cons.append({"id": "high_debt",
                     "text": f"High long-term debt: debt/equity of {debt_to_equity:.2f} (above {HIGH_DEBT_TO_EQUITY:.0f})"})

    if latest_equity is not None and latest_equity < 0:
        cons.append({"id": "negative_equity",
                     "text": f"Negative shareholders' equity of {format_money(latest_equity)} (liabilities exceed assets)"})

    pe = get("pe")
    if pe is not None and pe > HIGH_PE:
        cons.append({"id": "high_pe", "text": f"Expensive on earnings: P/E (FY) of {pe:.1f} (above {HIGH_PE:.0f})"})

    if free_cash_flow is not None and free_cash_flow < 0:
        cons.append({"id": "negative_fcf", "text": f"Negative free cash flow of {format_money(free_cash_flow)}"})

    return {"pros": pros, "cons": cons}
