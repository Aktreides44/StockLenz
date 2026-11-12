"""Extract annual (10-K) values from an SEC companyfacts JSON.

How the SEC data looks: facts["us-gaap"][tag]["units"]["USD"] is a list of entries like
    {"start": "2023-10-01", "end": "2024-09-28", "val": 391035000000,
     "form": "10-K", "fp": "FY", "filed": "2024-11-01", ...}
A single 10-K also repeats the previous years as comparison columns, so the same period
appears in several filings. We keep one value per period end date.
"""
from datetime import date

# For each raw field: the us-gaap tags to try (in order, first one found wins) and the unit.
# Tags after the ones listed in CLAUDE.md were added because real companies use them (example in the comment).
FIELDS = {
    # RevenuesNetOfInterestExpense: banks' "total net revenue" (WFC, GS); RegulatedAndUnregulated...: utilities (NEE);
    # ...IncludingAssessedTax (revenue incl. taxes passed on to customers): CRWD, CPRT, AKAM, BALL, CBOE, ARE
    "revenue": (["Revenues", "RevenueFromContractWithCustomerExcludingAssessedTax", "SalesRevenueNet",
                 "RevenuesNetOfInterestExpense", "RegulatedAndUnregulatedOperatingRevenue",
                 "RevenueFromContractWithCustomerIncludingAssessedTax"], "USD"),
    # NetIncomeLossAvailableToCommonStockholdersBasic: CAT from 2025;
    # ProfitLoss (incl. the small share of minority owners): AVGO, MA, ITW, LYB, VRSN, VTRS, BE
    "net_income": (["NetIncomeLoss", "NetIncomeLossAvailableToCommonStockholdersBasic", "ProfitLoss"], "USD"),
    "operating_income": (["OperatingIncomeLoss"], "USD"),
    "eps_diluted": (["EarningsPerShareDiluted"], "USD/shares"),
    "total_assets": (["Assets"], "USD"),
    "current_assets": (["AssetsCurrent"], "USD"),
    "current_liabilities": (["LiabilitiesCurrent"], "USD"),
    "equity": (["StockholdersEquity", "StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest"], "USD"),
    # LongTermDebtAndCapitalLeaseObligations: KO from 2024 (non-current debt incl. finance leases);
    # LongTermNotesPayable: ORCL
    "long_term_debt": (["LongTermDebtNoncurrent", "LongTermDebt", "LongTermDebtAndCapitalLeaseObligations",
                        "LongTermNotesPayable"], "USD"),
    # ...ContinuingOperations (without sold or discontinued businesses): APD, BDX, DD, DLTR, DOV, DRI, GEHC, JCI
    "operating_cash_flow": (["NetCashProvidedByUsedInOperatingActivities",
                             "NetCashProvidedByUsedInOperatingActivitiesContinuingOperations"], "USD"),
    # PaymentsToAcquireProductiveAssets (PP&E incl. software): NVDA, AMZN, HD, PEP, V, LMT, CVX;
    # PaymentsToAcquireOtherPropertyPlantAndEquipment: LLY; PaymentsToAcquireOtherProductiveAssets: VZ
    "capex": (["PaymentsToAcquirePropertyPlantAndEquipment", "PaymentsToAcquireProductiveAssets",
               "PaymentsToAcquireOtherPropertyPlantAndEquipment", "PaymentsToAcquireOtherProductiveAssets"], "USD"),
    # PaymentsOfOrdinaryDividends: used by e.g. JNJ
    "dividends_paid": (["PaymentsOfDividends", "PaymentsOfDividendsCommonStock", "PaymentsOfOrdinaryDividends"], "USD"),
    # v3 (Piotroski F-Score, pipeline/scores.py). Gross profit = revenue − cost of revenue; when a company
    # doesn't report GrossProfit, scores.py calculates it from the cost of revenue.
    "gross_profit": (["GrossProfit"], "USD"),
    "cost_of_revenue": (["CostOfRevenue", "CostOfGoodsAndServicesSold"], "USD"),
    # Average number of shares in the year, including options etc. that could become shares ("diluted").
    "diluted_shares": (["WeightedAverageNumberOfDilutedSharesOutstanding"], "shares"),
}

ANNUAL_FORMS = {"10-K", "10-K/A"}

# A fiscal year is 52 or 53 weeks (364 or 371 days); anything far from that is a quarter etc.
MIN_YEAR_DAYS = 350
MAX_YEAR_DAYS = 380


def annual_values(facts, tag, unit):
    """Return {end_date: value} for one tag, using only full-year values from 10-K filings.

    Balance sheet items (assets, equity, ...) have only an "end" date. Income and cash flow
    items also have a "start" date, and we require that period to be about one year long.
    When several filings report the same period, the most recently filed one wins,
    because it includes any later corrections (restatements).
    """
    entries = facts.get("us-gaap", {}).get(tag, {}).get("units", {}).get(unit, [])
    best = {}  # end_date -> entry
    for entry in entries:
        if entry.get("form") not in ANNUAL_FORMS or entry.get("fp") != "FY":
            continue
        if "start" in entry:
            days = (date.fromisoformat(entry["end"]) - date.fromisoformat(entry["start"])).days
            if not MIN_YEAR_DAYS <= days <= MAX_YEAR_DAYS:
                continue
        end = entry["end"]
        if end not in best or entry["filed"] > best[end]["filed"]:
            best[end] = entry
    return {end: entry["val"] for end, entry in best.items()}


def fiscal_year_label(end_date):
    """Return the fiscal year a period end date belongs to.

    Normally this is the calendar year it ends in (Apple's year ending 2024-09-28 is 2024).
    But companies with 52/53-week years sometimes end a year in the first days of January:
    JNJ's year ending 2023-01-01 is really fiscal 2022.
    """
    end = date.fromisoformat(end_date)
    if end.month == 1 and end.day <= 7:
        return end.year - 1
    return end.year


def find_fiscal_year_ends(values_by_tag):
    """Return {fiscal_year: end_date}, based on the end dates of full-year income/cash flow values.

    Balance sheet dates are not used here, because a 10-K can contain balance sheet
    values for dates that are not a fiscal year end.
    """
    end_dates = set()
    for (field, tag), values in values_by_tag.items():
        if field in ("revenue", "net_income", "operating_cash_flow"):
            end_dates.update(values.keys())

    ends_by_year = {}
    for end in end_dates:
        year = fiscal_year_label(end)
        if year not in ends_by_year or end > ends_by_year[year]:
            ends_by_year[year] = end
    return ends_by_year


def extract_company(companyfacts, num_years=5):
    """Return the raw fields for the last num_years fiscal years.

    Result looks like:
    {2024: {"end_date": "2024-09-28",
            "fields": {"revenue": {"value": 391035000000, "tag": "RevenueFromContract..."},
                       "dividends_paid": None,   # None means: not reported
                       ...}},
     ...}
    """
    facts = companyfacts.get("facts", {})

    values_by_tag = {}
    for field, (tags, unit) in FIELDS.items():
        for tag in tags:
            values_by_tag[(field, tag)] = annual_values(facts, tag, unit)

    ends_by_year = find_fiscal_year_ends(values_by_tag)
    last_years = sorted(ends_by_year)[-num_years:]

    result = {}
    for year in last_years:
        end = ends_by_year[year]
        fields = {}
        for field, (tags, unit) in FIELDS.items():
            fields[field] = None
            for tag in tags:
                value = values_by_tag[(field, tag)].get(end)
                if value is not None:
                    fields[field] = {"value": value, "tag": tag}
                    break
        result[year] = {"end_date": end, "fields": fields}
    return result
