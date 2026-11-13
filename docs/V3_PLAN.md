# StockLens v3 — plan

Status: **v3 finished (13 Nov 2026), tagged `v3.0`** — all five build steps done. Rules fixed 12 Nov 2026 (based on
published methods). v3 is the third and final version. Done beyond the lean plan: Quality and Value are also screener
columns (Columns picker, filters, presets). Not done (extra): Strong and Weak side by side on wide screens.

## Goal
Make the "good vs bad" comparison explicit and explainable — **without predicting prices**, and with rules
that come from published sources, not from our own opinion.

> StockLens doesn't predict prices. It applies a published financial-health score (Piotroski F-Score) and a
> standard sector comparison of valuation ratios to official SEC data, and it shows its reasons.

Every result shows *why* (which checks passed or failed). Still **not investment advice**.

## Sources (cite these in the report)
- **Quality:** Piotroski, J. D. (2000). *Value Investing: The Use of Historical Financial Statement Information
  to Separate Winners from Losers.* Journal of Accounting Research, 38 (Supplement), 1–41.
- **Value (compare with comparable firms):** Damodaran, A. (2012). *Investment Valuation* (3rd ed.). Wiley —
  chapters on relative valuation (multiples compared within comparable firms / the same sector).
- **Value (ranking by valuation ratios):** Fama, E. F., & French, K. R. (1992). *The Cross-Section of Expected
  Stock Returns.* Journal of Finance, 47(2), 427–465.
- Background only: Graham, B. *The Intelligent Investor* (rev. ed. 1973), ch. 14 (classic P/E and P/B limits).

Check page numbers in the library / Google Scholar before submitting.

## Quality — Piotroski F-Score ("is this company financially healthy and improving?")
Nine yes/no checks, one point each. Year t = latest fiscal year, t-1 = the year before.
"Beginning assets" = total assets at the end of the previous year (as in the paper).

| # | Check (1 point if true) | Calculation from our data |
|---|---|---|
| 1 | Profitable | ROA = NI_t / Assets_t-1 > 0 |
| 2 | Cash from operations | OCF_t > 0 |
| 3 | More profitable than last year | ROA_t > ROA_t-1 (ROA_t-1 = NI_t-1 / Assets_t-2) |
| 4 | Profit backed by cash (accruals) | OCF_t > NI_t |
| 5 | Less long-term debt | LTD_t / avg(Assets_t, Assets_t-1) < LTD_t-1 / avg(Assets_t-1, Assets_t-2) |
| 6 | Better liquidity | current ratio_t > current ratio_t-1 (not for Financials) |
| 7 | No new shares issued | diluted weighted-average shares_t ≤ shares_t-1 (proxy, see limitations) |
| 8 | Better gross margin | gross margin_t > gross margin_t-1 (not for Financials) |
| 9 | Better asset turnover | Rev_t / Assets_t-1 > Rev_t-1 / Assets_t-2 |

- A check whose numbers are missing (or not applicable) is **skipped** ("—"), never pass or fail.
- **Score = points ÷ checkable checks × 9**, one decimal (so it stays on Piotroski's 0–9 scale).
  Needs at least **7** checkable checks; otherwise "not enough data".
- **Strong: score ≥ 8. Weak: score ≤ 1.** (Piotroski's own high / low groups: 8–9 and 0–1.) Otherwise "Mixed".
- New SEC data needed (same companyfacts files, no extra downloads):
  - Gross profit: `GrossProfit`; else Revenue − `CostOfRevenue` / `CostOfGoodsAndServicesSold` (that difference
    *is* gross profit; record which was used).
  - Diluted weighted-average shares per fiscal year: `WeightedAverageNumberOfDilutedSharesOutstanding`.

## Value — sector ranking ("is it cheap or expensive compared with similar companies?")
Compared **within the same sector only** (Damodaran: compare multiples with comparable firms).

For each of **P/E (TTM)** (fallback P/E FY), **P/B** and **P/S (TTM)**:
- only positive values count (a negative P/E means a loss, not "cheap");
- percentile rank in the sector = position ÷ (count − 1): 0 = cheapest, 1 = most expensive;
- needs at least **5** companies with that ratio in the sector. Financials: P/S skipped.

**Value score = (1 − average percentile of the available ratios) × 10**, one decimal; needs at least 2 ratios.
**Cheap: ≥ 7** (roughly the cheapest 30 % of its sector). **Expensive: ≤ 3.** The app shows the sector median
next to each ratio.

## Combined reading (text only, never "buy"/"sell")
| Quality | Value | Text |
|---|---|---|
| Strong | Cheap | "Strong finances and cheaper than its sector — worth a closer look" |
| Strong | Expensive | "Strong finances, but the market already prices that in" |
| Weak | Cheap | "Cheap, but weak finances — cheap for a reason?" |
| Weak | Expensive | "Weak finances and expensive" |

## The app (lean version — fits in short sessions)
- Bottom bar (phones) / navigation rail (wide screens) with **two tabs: Screener | Scores.**
- **Scores tab:** one list with buttons at the top: **All · Strong · Weak · Cheap · Expensive**; each row shows
  Quality (0–9) and Value (0–10) as coloured chips; sortable; sector filter; tap → company page.
- **Company page:** new "Scores" section — both scores, every check with ✓ / ✗ / — and its numbers, the sector
  medians, and the combined text.
- Extra if time allows: Quality and Value as normal Screener columns (Columns picker, filters, presets);
  Strong and Weak side by side on wide screens.

## Build order (each step ends with tests, a commit and a short explanation)
1. **`pipeline/scores.py`**: `piotroski_score()` and `value_scores()` as pure functions returning the score and
   the check results (check, numbers, passed/failed/skipped). Hand-computed tests incl. missing data,
   Financials, too few checks, tiny sectors, negative P/E. Extractor: gross profit + diluted shares.
2. **Pipeline + DB + API**: compute after all companies are built; store scores + check results (JSON) and
   sector medians; add to `/companies`, `/companies/{ticker}`, `/metrics`. → **push (ask first)**
3. **App: tab bar + Scores tab.**
4. **App: company-page Scores section.** → **push (ask first)**
5. **Docs**: README "How the scores work" (checks, sources, limitations), CLAUDE.md, this plan.
   Tag `v3.0`, new APK, push (ask first).

If time runs short: drop the extras first, then the sector filter on the Scores tab — never the tests,
the company-page section or the sources.

## Honesty / limitations (for the report)
- Piotroski tested the F-Score on high book-to-market ("value") US stocks, 1976–1996. Applying it to the whole
  S&P 500 today is common practice, but not what the paper proved.
- Check 7 uses the change in diluted weighted-average shares as a proxy for "issued new shares"
  (the paper uses equity issuance); share-based pay can move it a little.
- Skipped checks are rescaled to 0–9 — our adaptation, not in the paper.
- A good *company* is not automatically a good *stock* (Strong + Expensive).
- Value is relative to the sector: a whole sector can be expensive.
- One unusual year can move the scores a lot; scores use the latest fiscal year (TTM for valuation).
- No back-test: today's S&P 500 list contains only survivors (survivorship bias). StockLens does not claim
  to beat the market.

## Builds on
- `backend/pipeline/metrics.py`, `extract.py`, `analysis.py`; v2 data (S&P 500, TTM, Polygon prices).
