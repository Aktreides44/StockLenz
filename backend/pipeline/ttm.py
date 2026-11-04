"""TTM ("trailing twelve months"): revenue, net income and diluted EPS of the last four quarters.

Companies do not report a fourth quarter on its own. Their 10-Q reports instead contain "year to date"
values (the first 3, 6 or 9 months of the fiscal year) next to the same months of the year before. So:

    TTM = last full fiscal year (10-K) + this year's months so far − the same months a year earlier

Example, Apple: FY2025 revenue $416.16B + 9 months to 27 Jun 2026 $364.36B − 9 months to 28 Jun 2025
$313.70B = $466.82B for the 12 months to 27 Jun 2026.

If there is no 10-Q after the latest 10-K, TTM is simply the fiscal year. All three numbers come from
one XBRL tag: the tag of the fiscal-year value, or another tag from the FIELDS list that reports exactly
the same fiscal-year value (JPMorgan: "Revenues" in the 10-K, "RevenuesNetOfInterestExpense" in the
10-Qs, both $182.45B). So different definitions are never mixed.
"""
from datetime import date, timedelta

from pipeline.extract import FIELDS, annual_values

TTM_FIELDS = ["revenue", "net_income", "eps_diluted"]
QUARTERLY_FORMS = {"10-Q", "10-Q/A"}
DAYS_TOLERANCE = 7  # 52/53-week years: period dates move by a few days from year to year


def _days(entry):
    return (date.fromisoformat(entry["end"]) - date.fromisoformat(entry["start"])).days


def _close(day_a, day_b):
    return abs((date.fromisoformat(day_a) - date.fromisoformat(day_b)).days) <= DAYS_TOLERANCE


def _quarters_since(entries, fy_end, fy_value):
    """Try one tag. Returns ("no quarter", None, None), ("no comparison", None, None) or ("ok", value, end)."""
    periods = [e for e in entries if e.get("form") in QUARTERLY_FORMS and "start" in e]

    # 1. This year so far: starts the day after the fiscal year end, ends later, 3 to 9 months long.
    next_start = (date.fromisoformat(fy_end) + timedelta(days=1)).isoformat()
    this_year = [e for e in periods if _close(e["start"], next_start) and e["end"] > fy_end and 80 <= _days(e) <= 300]
    if not this_year:
        return "no quarter", None, None
    current = max(this_year, key=lambda e: (e["end"], e["filed"]))

    # 2. The same months one year earlier (the comparison column of the same 10-Q).
    year_before = (date.fromisoformat(current["end"]) - timedelta(days=365)).isoformat()
    earlier = [e for e in periods if _close(e["end"], year_before) and abs(_days(e) - _days(current)) <= DAYS_TOLERANCE
               and e["start"] <= fy_end]
    if not earlier:
        return "no comparison", None, None  # we won't guess the comparison period
    previous = max(earlier, key=lambda e: e["filed"])  # the newest filing includes corrections
    return "ok", fy_value + current["val"] - previous["val"], current["end"]


def ttm_value(companyfacts, field, fiscal_year):
    """TTM for one field: {"value", "end", "tag"}, or None if it cannot be calculated.

    fiscal_year: the latest year from extract_company(), {"end_date": ..., "fields": {...}}.
    """
    cell = fiscal_year["fields"][field]
    if cell is None:
        return None
    fy_end = fiscal_year["end_date"]
    tags, unit = FIELDS[field]
    facts = companyfacts.get("facts", {})
    us_gaap = facts.get("us-gaap", {})

    statuses = []
    for tag in [cell["tag"]] + [t for t in tags if t != cell["tag"]]:
        if tag != cell["tag"] and annual_values(facts, tag, unit).get(fy_end) != cell["value"]:
            continue  # another tag may only be used if it reports the same fiscal-year value
        entries = us_gaap.get(tag, {}).get("units", {}).get(unit, [])
        status, value, end = _quarters_since(entries, fy_end, cell["value"])
        if status == "ok":
            return {"value": value, "end": end, "tag": tag}
        statuses.append(status)

    if all(status == "no quarter" for status in statuses):
        return {"value": cell["value"], "end": fy_end, "tag": cell["tag"]}  # the 10-K is the latest report
    return None


def extract_ttm(companyfacts, years):
    """TTM values for the latest fiscal year in `years` (from extract_company).

    Returns {"end": "YYYY-MM-DD" or None, "revenue": value or None, "net_income": ..., "eps_diluted": ...}.
    "end" is where the 12 months end (the latest 10-Q, or the fiscal year end). A field whose latest
    quarter differs from the others (rare) is left empty, so every TTM value covers the same months.
    """
    latest = years[max(years)]
    results = {field: ttm_value(companyfacts, field, latest) for field in TTM_FIELDS}
    ends = [r["end"] for r in results.values() if r is not None]
    end = max(ends) if ends else None
    ttm = {"end": end}
    for field, result in results.items():
        ttm[field] = result["value"] if result is not None and result["end"] == end else None
    return ttm
