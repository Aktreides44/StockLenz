"""v3 scores (pipeline/scores.py): Piotroski F-Score and sector value ranking, with hand-computed numbers."""
import copy
import json
from pathlib import Path

import pytest

from pipeline.extract import extract_company
from pipeline.scores import (
    add_scores,
    combined_reading,
    gross_profit,
    percentile,
    piotroski_score,
    plain_years,
    value_scores,
)

# A made-up company that improves on every check from 2024 to 2025.
#   1 ROA 2025 = 88 / 1100 (assets end 2024)          = 0.080 > 0                  ✓
#   2 cash from operations 120 > 0                                                  ✓
#   3 ROA 2024 = 50 / 1000 = 0.050 → 0.080 is higher                                ✓
#   4 cash from operations 120 > net income 88                                      ✓
#   5 debt / avg assets: 2025 280 / 1150 = 0.243 < 2024 300 / 1050 = 0.286          ✓
#   6 current ratio: 500 / 200 = 2.5 > 400 / 200 = 2.0                              ✓
#   7 diluted shares 98 ≤ 100                                                       ✓
#   8 gross margin: 550 / 1320 = 0.417 > 400 / 1000 = 0.400                         ✓
#   9 asset turnover: 1320 / 1100 = 1.2 > 1000 / 1000 = 1.0                         ✓
GOOD = {
    2023: {"total_assets": 1000},
    2024: {"net_income": 50, "total_assets": 1100, "operating_cash_flow": 60, "long_term_debt": 300,
           "current_assets": 400, "current_liabilities": 200, "revenue": 1000, "gross_profit": 400,
           "diluted_shares": 100},
    2025: {"net_income": 88, "total_assets": 1200, "operating_cash_flow": 120, "long_term_debt": 280,
           "current_assets": 500, "current_liabilities": 200, "revenue": 1320, "gross_profit": 550,
           "diluted_shares": 98},
}


def with_changes(changes):
    """A copy of GOOD with some 2025 numbers changed (None = not reported)."""
    years = copy.deepcopy(GOOD)
    years[2025].update(changes)
    return years


def results(score):
    return {check["key"]: check["passed"] for check in score["checks"]}


def test_all_nine_checks_pass():
    score = piotroski_score(GOOD, is_financial=False)
    assert all(results(score).values())
    assert (score["points"], score["checkable"], score["score"], score["label"]) == (9, 9, 9.0, "Strong")
    roa_up = next(c for c in score["checks"] if c["key"] == "roa_up")
    assert roa_up["values"]["now"] == pytest.approx(0.08)
    assert roa_up["values"]["before"] == pytest.approx(0.05)


def test_all_nine_checks_fail():
    years = with_changes({"net_income": -10, "operating_cash_flow": -20, "long_term_debt": 400,
                          "current_assets": 300, "gross_profit": 300, "diluted_shares": 110, "revenue": 900})
    score = piotroski_score(years, is_financial=False)
    assert not any(results(score).values())
    # 4: cash from operations −20 is not more than net income −10
    assert (score["points"], score["score"], score["label"]) == (0, 0.0, "Weak")


def test_missing_numbers_skip_a_check_and_the_score_is_rescaled():
    # No diluted shares (check 7 skipped) and a lower ROA (check 3 fails): 7 of 8 → 7 / 8 × 9 = 7.875 → 7.9
    years = with_changes({"diluted_shares": None, "net_income": 50})
    # net income 50: ROA 50 / 1100 = 0.045 < 0.050; still 120 > 50 for check 4
    score = piotroski_score(years, is_financial=False)
    assert results(score)["no_new_shares"] is None
    assert results(score)["roa_up"] is False
    assert (score["points"], score["checkable"], score["score"], score["label"]) == (7, 8, 7.9, "Mixed")
    skipped = next(c for c in score["checks"] if c["key"] == "no_new_shares")
    assert skipped["skip_reason"] == "Numbers missing"


def test_same_number_of_shares_passes_check_7():
    score = piotroski_score(with_changes({"diluted_shares": 100}), is_financial=False)
    assert results(score)["no_new_shares"] is True


def test_financials_skip_current_ratio_and_gross_margin():
    score = piotroski_score(GOOD, is_financial=True)
    assert results(score)["current_ratio_up"] is None
    assert results(score)["gross_margin_up"] is None
    assert (score["points"], score["checkable"], score["score"]) == (7, 7, 9.0)


def test_fewer_than_seven_checkable_checks_gives_no_score():
    # Financials (2 skipped) without long-term debt (1 more skipped): 6 checkable
    score = piotroski_score(with_changes({"long_term_debt": None}), is_financial=True)
    assert score["checkable"] == 6
    assert score["score"] is None and score["label"] is None


def test_only_one_year_gives_no_score():
    score = piotroski_score({2025: GOOD[2025]}, is_financial=False)
    # Every check except 2 (cash from operations) and 4 (cash vs net income) needs the year before.
    assert score["checkable"] == 2
    assert score["score"] is None


def test_no_years_at_all():
    score = piotroski_score({}, is_financial=False)
    assert (score["score"], score["checkable"]) == (None, 0)


def test_gross_profit_from_cost_of_revenue():
    assert gross_profit({"gross_profit": 40, "revenue": 100, "cost_of_revenue": 70}) == 40  # reported wins
    assert gross_profit({"gross_profit": None, "revenue": 100, "cost_of_revenue": 70}) == 30
    assert gross_profit({"gross_profit": None, "revenue": 100, "cost_of_revenue": None}) is None


def test_plain_years_turns_extractor_cells_into_numbers():
    extracted = {2025: {"end_date": "2025-12-31",
                        "fields": {"revenue": {"value": 10, "tag": "Revenues"}, "gross_profit": None}}}
    assert plain_years(extracted) == {2025: {"revenue": 10, "gross_profit": None}}


def test_extractor_reads_the_new_fields_for_apple():
    fixture = Path(__file__).parent / "fixtures" / "aapl_companyfacts.json"
    years = extract_company(json.loads(fixture.read_text(encoding="utf-8")))
    fy2024 = years[2024]["fields"]
    # Apple 10-K FY2024: gross margin $180,683M, diluted weighted-average shares 15,408,095 thousand
    assert fy2024["gross_profit"]["value"] == 180_683_000_000
    assert fy2024["diluted_shares"]["value"] == 15_408_095_000


# ---------------------------------------------------------------------------------------------------------------
# Value
# ---------------------------------------------------------------------------------------------------------------

def company(ticker, sector="Tech", pe_ttm=None, pe=None, pb=None, ps_ttm=None):
    return {"ticker": ticker, "sector": sector, "pe_ttm": pe_ttm, "pe": pe, "pb": pb, "ps_ttm": ps_ttm}


def five_companies(sector="Tech"):
    """P/E 10–50, P/B 1–5, P/S 1–5: A is the cheapest on every ratio, E the most expensive."""
    return [company(t, sector, pe_ttm=10 * (i + 1), pb=i + 1, ps_ttm=i + 1) for i, t in enumerate("ABCDE")]


def test_percentile_ranks_from_cheapest_to_most_expensive():
    values = [10, 20, 30, 40, 50]
    assert [percentile(v, values) for v in values] == [0, 0.25, 0.5, 0.75, 1]
    # Ties share the average position: 10, 20, 20, 40 → the two 20s are positions 1 and 2 → 1.5 / 3 = 0.5
    assert percentile(20, [10, 20, 20, 40]) == 0.5


def test_value_scores_in_a_sector_of_five():
    scores, medians = value_scores(five_companies())
    assert (scores["A"]["score"], scores["A"]["label"]) == (10.0, "Cheap")
    assert (scores["C"]["score"], scores["C"]["label"]) == (5.0, "Fair")
    assert (scores["E"]["score"], scores["E"]["label"]) == (0.0, "Expensive")
    # B: percentile 0.25 on all three → (1 − 0.25) × 10 = 7.5
    assert (scores["B"]["score"], scores["B"]["label"]) == (7.5, "Cheap")
    assert medians["Tech"] == {"pe": 30, "pb": 3, "ps": 3}
    assert scores["A"]["ratios"]["pe"]["sector_median"] == 30


def test_negative_pe_is_skipped_not_cheap():
    companies = five_companies() + [company("LOSS", pe_ttm=-5, pb=1, ps_ttm=1)]
    scores, _ = value_scores(companies)
    loss = scores["LOSS"]["ratios"]["pe"]
    assert loss["value"] is None and loss["percentile"] is None
    assert loss["skip_reason"].startswith("No positive value")
    assert scores["LOSS"]["score"] is not None  # still ranked on P/B and P/S


def test_pe_falls_back_to_the_fiscal_year_value():
    companies = five_companies()
    companies[0] = company("A", pe=5, pb=1, ps_ttm=1)  # no TTM P/E, FY P/E 5
    scores, _ = value_scores(companies)
    assert scores["A"]["ratios"]["pe"]["value"] == 5


def test_sector_with_fewer_than_five_companies_is_not_ranked():
    scores, medians = value_scores(five_companies()[:4])
    assert scores["A"]["score"] is None
    assert scores["A"]["ratios"]["pb"]["skip_reason"] == "Fewer than 5 companies in the sector have it"
    assert medians["Tech"]["pb"] is None


def test_financials_are_ranked_without_price_to_sales():
    scores, _ = value_scores(five_companies("Financials"))
    assert scores["A"]["ratios"]["ps"]["skip_reason"] == "Not meaningful for banks and insurers"
    assert (scores["A"]["score"], scores["A"]["label"]) == (10.0, "Cheap")  # from P/E and P/B


def test_one_ratio_is_not_enough_for_a_value_score():
    companies = [company(t, pe_ttm=10 * (i + 1)) for i, t in enumerate("ABCDE")]  # P/E only
    scores, _ = value_scores(companies)
    assert scores["A"]["score"] is None


def test_companies_are_compared_only_within_their_own_sector():
    expensive_tech = [company(t, "Tech", pe_ttm=100 * (i + 1), pb=10 + i, ps_ttm=10 + i) for i, t in enumerate("ABCDE")]
    cheap_energy = [company(t, "Energy", pe_ttm=i + 1, pb=0.1 * (i + 1), ps_ttm=0.1 * (i + 1)) for i, t in enumerate("VWXYZ")]
    scores, _ = value_scores(expensive_tech + cheap_energy)
    assert scores["A"]["score"] == 10.0  # cheapest in Tech, although far more expensive than all of Energy
    assert scores["Z"]["score"] == 0.0


def test_combined_reading():
    assert combined_reading("Strong", "Cheap").startswith("Strong finances and cheaper")
    assert combined_reading("Weak", "Cheap") == "Cheap, but weak finances — cheap for a reason?"
    assert combined_reading("Mixed", "Cheap") is None
    assert combined_reading(None, None) is None


def test_add_scores_fills_every_company():
    """The pipeline step: five companies in one sector, all with the GOOD history (9 of 9) and different prices."""
    from tests.test_calculations import make_years

    companies = []
    for i, ticker in enumerate("ABCDE"):
        companies.append({
            "ticker": ticker, "sector": "Tech", "years": make_years(copy.deepcopy(GOOD)), "missing_reasons": {},
            "pe_ttm": 10 * (i + 1), "pe": None, "pb": i + 1, "ps_ttm": i + 1,
        })
    companies.append({"ticker": "NEW", "sector": "Tech", "years": make_years({2025: GOOD[2025]}),
                      "missing_reasons": {}, "pe_ttm": None, "pe": None, "pb": None, "ps_ttm": None})
    add_scores(companies)

    a = companies[0]
    assert (a["quality_score"], a["quality_label"], a["value_score"], a["value_label"]) == (9.0, "Strong", 10.0, "Cheap")
    assert a["scores"]["combined"] == "Strong finances and cheaper than its sector — worth a closer look"
    e = companies[4]
    assert e["scores"]["combined"] == "Strong finances, but the market already prices that in"

    new = companies[5]
    assert new["quality_score"] is None and new["value_score"] is None
    assert new["missing_reasons"]["quality_score"] == "Not enough data: 2 of 9 checks can be calculated (needs 7)"
    assert new["missing_reasons"]["value_score"].startswith("Not enough data")
