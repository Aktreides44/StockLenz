"""v3 scores: Quality (Piotroski F-Score) and Value (valuation ratios ranked within the sector).

Both are pure functions: numbers in, score + reasons out. The pipeline stores the results and the app shows them
(see docs/V3_PLAN.md for the rules and the sources).

Quality — Piotroski, J. D. (2000), "Value Investing: The Use of Historical Financial Statement Information to
Separate Winners from Losers", Journal of Accounting Research 38: nine yes/no checks, one point each.
Value — compare valuation ratios only with companies of the same sector (Damodaran, Investment Valuation,
relative valuation) and rank them (Fama & French 1992 rank stocks by such ratios).

Neither score predicts prices, and neither is investment advice.
"""
from statistics import median

FINANCIALS = "Financials"

# ---------------------------------------------------------------------------------------------------------------
# Quality: Piotroski F-Score
# ---------------------------------------------------------------------------------------------------------------

MIN_CHECKABLE = 7  # fewer checkable checks than this → "not enough data"
STRONG_AT_LEAST = 8.0  # Piotroski's high group: 8–9 points
WEAK_AT_MOST = 1.0  # Piotroski's low group: 0–1 points


def _ratio(numerator, denominator):
    """numerator / denominator, or None if a number is missing or the denominator is zero."""
    if numerator is None or denominator is None or denominator == 0:
        return None
    return numerator / denominator


def _average(a, b):
    return None if a is None or b is None else (a + b) / 2


def _check(key, label, passed, values, skip_reason=None):
    """One check result. passed: True / False, or None when the check was skipped."""
    return {"key": key, "label": label, "passed": passed, "values": values, "skip_reason": skip_reason}


def _compare(key, label, now, before, better="higher", values=None, missing_reason="Numbers missing"):
    """A check of the form "now is better than before". Skipped when one of the two is missing.

    better: "higher" (now > before), "lower" (now < before) or "not_higher" (now ≤ before).
    """
    values = values if values is not None else {"now": now, "before": before}
    if now is None or before is None:
        return _check(key, label, None, values, missing_reason)
    if better == "higher":
        passed = now > before
    elif better == "lower":
        passed = now < before
    else:
        passed = now <= before
    return _check(key, label, passed, values)


def gross_profit(fields):
    """Gross profit of one year: GrossProfit if reported, else revenue − cost of revenue."""
    if fields.get("gross_profit") is not None:
        return fields["gross_profit"]
    if fields.get("revenue") is not None and fields.get("cost_of_revenue") is not None:
        return fields["revenue"] - fields["cost_of_revenue"]
    return None


def piotroski_score(years, is_financial):
    """The F-Score for the latest fiscal year in `years`.

    years: {fiscal_year: {field: value or None}} — plain numbers, e.g. from plain_years().
    Returns {"score": 0–9 with one decimal or None, "label": "Strong" / "Mixed" / "Weak" or None,
             "points": int, "checkable": int, "checks": [nine check results]}.
    A check whose numbers are missing (or that doesn't apply to Financials) is skipped, never passed or failed.
    The score is rescaled to the checkable checks: points ÷ checkable × 9.
    """
    t = max(years) if years else None

    def v(year, field):
        if year is None or year not in years:
            return None
        return years[year].get(field)

    def roa(year):  # net income ÷ total assets at the start of the year (= end of the year before)
        return _ratio(v(year, "net_income"), v(year - 1, "total_assets"))

    def leverage(year):  # long-term debt ÷ average total assets
        return _ratio(v(year, "long_term_debt"), _average(v(year, "total_assets"), v(year - 1, "total_assets")))

    def current_ratio(year):
        return _ratio(v(year, "current_assets"), v(year, "current_liabilities"))

    def gross_margin(year):
        fields = years.get(year, {}) if year is not None else {}
        return _ratio(gross_profit(fields), v(year, "revenue"))

    def asset_turnover(year):  # revenue ÷ total assets at the start of the year
        return _ratio(v(year, "revenue"), v(year - 1, "total_assets"))

    prev = None if t is None else t - 1
    roa_now = None if t is None else roa(t)
    ocf_now = v(t, "operating_cash_flow")
    ni_now = v(t, "net_income")
    not_for_financials = "Not meaningful for banks and insurers"

    checks = [
        _check("roa_positive", "Profitable (ROA > 0)", None if roa_now is None else roa_now > 0, {"now": roa_now},
               None if roa_now is not None else "Numbers missing"),
        _check("ocf_positive", "Cash from operations > 0", None if ocf_now is None else ocf_now > 0, {"now": ocf_now},
               None if ocf_now is not None else "Numbers missing"),
        _compare("roa_up", "ROA higher than last year", roa_now, None if t is None else roa(prev)),
        _compare("accruals", "Cash from operations > net income", ocf_now, ni_now,
                 values={"cash_from_operations": ocf_now, "net_income": ni_now}),
        _compare("leverage_down", "Less long-term debt (vs assets)", None if t is None else leverage(t),
                 None if t is None else leverage(prev), better="lower"),
        _check("current_ratio_up", "Current ratio higher", None, {}, not_for_financials) if is_financial else
        _compare("current_ratio_up", "Current ratio higher", None if t is None else current_ratio(t),
                 None if t is None else current_ratio(prev)),
        _compare("no_new_shares", "No new shares (diluted shares not up)", v(t, "diluted_shares"),
                 v(prev, "diluted_shares"), better="not_higher"),
        _check("gross_margin_up", "Gross margin higher", None, {}, not_for_financials) if is_financial else
        _compare("gross_margin_up", "Gross margin higher", None if t is None else gross_margin(t),
                 None if t is None else gross_margin(prev)),
        _compare("asset_turnover_up", "Asset turnover higher", None if t is None else asset_turnover(t),
                 None if t is None else asset_turnover(prev)),
    ]

    checkable = sum(1 for c in checks if c["passed"] is not None)
    points = sum(1 for c in checks if c["passed"] is True)
    if checkable < MIN_CHECKABLE:
        return {"score": None, "label": None, "points": points, "checkable": checkable, "checks": checks}
    score = round(points / checkable * 9, 1)
    if score >= STRONG_AT_LEAST:
        label = "Strong"
    elif score <= WEAK_AT_MOST:
        label = "Weak"
    else:
        label = "Mixed"
    return {"score": score, "label": label, "points": points, "checkable": checkable, "checks": checks}


def plain_years(extracted):
    """Turn extract_company() output ({year: {"end_date", "fields": {field: {"value", "tag"} or None}}})
    into plain numbers: {year: {field: value or None}}."""
    return {
        year: {field: None if cell is None else cell["value"] for field, cell in data["fields"].items()}
        for year, data in extracted.items()
    }


# ---------------------------------------------------------------------------------------------------------------
# Value: valuation ratios ranked within the sector
# ---------------------------------------------------------------------------------------------------------------

MIN_SECTOR_COMPANIES = 5  # fewer companies with a ratio in the sector → that ratio isn't ranked
MIN_RATIOS = 2  # a value score needs at least this many ranked ratios
CHEAP_AT_LEAST = 7.0  # roughly the cheapest 30 % of the sector
EXPENSIVE_AT_MOST = 3.0

VALUE_RATIOS = [
    ("pe", "P/E"),  # P/E (TTM), or P/E (FY) when there is no TTM value
    ("pb", "P/B"),
    ("ps", "P/S (TTM)"),
]


def value_ratio(company, key):
    """The ratio used for ranking, or None. Only positive values count: a negative P/E means a loss, not "cheap"."""
    if key == "pe":
        value = company.get("pe_ttm") if company.get("pe_ttm") is not None else company.get("pe")
    elif key == "pb":
        value = company.get("pb")
    else:
        if company.get("sector") == FINANCIALS:
            return None  # revenue means something different for banks and insurers
        value = company.get("ps_ttm")
    return value if value is not None and value > 0 else None


def percentile(value, values):
    """Position of value among values, from 0 (lowest = cheapest) to 1 (highest = most expensive).

    position ÷ (count − 1). Equal values share the average of their positions, so ties are treated fairly.
    """
    lower = sum(1 for other in values if other < value)
    equal = sum(1 for other in values if other == value)
    position = lower + (equal - 1) / 2
    return position / (len(values) - 1)


def value_scores(companies):
    """Rank every company's P/E, P/B and P/S against its own sector.

    companies: list of {"ticker", "sector", "pe_ttm", "pe", "pb", "ps_ttm"}.
    Returns ({ticker: {"score": 0–10 or None, "label": "Cheap" / "Fair" / "Expensive" or None,
                       "ratios": {key: {"label", "value", "percentile", "sector_median", "sector_count",
                                        "skip_reason"}}}},
             {sector: {key: median or None}}).
    """
    by_sector = {}
    for company in companies:
        by_sector.setdefault(company["sector"], []).append(company)

    # The positive values of each ratio in each sector.
    sector_values = {
        sector: {key: [v for v in (value_ratio(c, key) for c in members) if v is not None] for key, _ in VALUE_RATIOS}
        for sector, members in by_sector.items()
    }
    medians = {
        sector: {key: median(values) if len(values) >= MIN_SECTOR_COMPANIES else None
                 for key, values in ratios.items()}
        for sector, ratios in sector_values.items()
    }

    results = {}
    for company in companies:
        ratios = {}
        for key, label in VALUE_RATIOS:
            value = value_ratio(company, key)
            values = sector_values[company["sector"]][key]
            entry = {"label": label, "value": value, "percentile": None,
                     "sector_median": medians[company["sector"]][key], "sector_count": len(values),
                     "skip_reason": None}
            if key == "ps" and company["sector"] == FINANCIALS:
                entry["skip_reason"] = "Not meaningful for banks and insurers"
            elif value is None:
                entry["skip_reason"] = "No positive value (e.g. a loss)"
            elif len(values) < MIN_SECTOR_COMPANIES:
                entry["skip_reason"] = f"Fewer than {MIN_SECTOR_COMPANIES} companies in the sector have it"
            else:
                entry["percentile"] = round(percentile(value, values), 3)
            ratios[key] = entry

        ranked = [r["percentile"] for r in ratios.values() if r["percentile"] is not None]
        if len(ranked) < MIN_RATIOS:
            score, label = None, None
        else:
            score = round((1 - sum(ranked) / len(ranked)) * 10, 1)
            if score >= CHEAP_AT_LEAST:
                label = "Cheap"
            elif score <= EXPENSIVE_AT_MOST:
                label = "Expensive"
            else:
                label = "Fair"
        results[company["ticker"]] = {"score": score, "label": label, "ratios": ratios}
    return results, medians


# ---------------------------------------------------------------------------------------------------------------
# Combined reading (text only — never "buy" or "sell")
# ---------------------------------------------------------------------------------------------------------------

COMBINED_TEXT = {
    ("Strong", "Cheap"): "Strong finances and cheaper than its sector — worth a closer look",
    ("Strong", "Expensive"): "Strong finances, but the market already prices that in",
    ("Weak", "Cheap"): "Cheap, but weak finances — cheap for a reason?",
    ("Weak", "Expensive"): "Weak finances and expensive",
}


def combined_reading(quality_label, value_label):
    """One sentence for the four clear cases, otherwise None."""
    return COMBINED_TEXT.get((quality_label, value_label))


# ---------------------------------------------------------------------------------------------------------------
# Used by the pipeline (pipeline/refresh.py)
# ---------------------------------------------------------------------------------------------------------------

def add_scores(companies):
    """Add both scores to every company built by refresh.build_company (changes the dicts in place).

    Sets quality_score, quality_label, value_score, value_label, "scores" (all details, stored as JSON)
    and a missing reason when a score can't be calculated.
    """
    ratio_keys = ("ticker", "sector", "pe_ttm", "pe", "pb", "ps_ttm")
    values, _ = value_scores([{key: company.get(key) for key in ratio_keys} for company in companies])

    for company in companies:
        quality = piotroski_score(plain_years(company["years"]), company["sector"] == FINANCIALS)
        value = values[company["ticker"]]
        company["quality_score"] = quality["score"]
        company["quality_label"] = quality["label"]
        company["value_score"] = value["score"]
        company["value_label"] = value["label"]
        company["scores"] = {
            "quality": quality,
            "value": value,
            "combined": combined_reading(quality["label"], value["label"]),
        }
        if quality["score"] is None:
            company["missing_reasons"]["quality_score"] = (
                f"Not enough data: {quality['checkable']} of 9 checks can be calculated (needs {MIN_CHECKABLE})")
        if value["score"] is None:
            company["missing_reasons"]["value_score"] = (
                f"Not enough data: fewer than {MIN_RATIOS} valuation ratios can be compared with the sector")
