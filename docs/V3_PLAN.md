# StockLens v3 — plan

Status: **rules fixed 11 Nov 2026; build on 12 Nov 2026 (one day).** v2 is finished and tagged `v2.0` first.
v3 is the third and final version.

## Goal
Make the "good vs bad" comparison explicit and explainable — **without predicting prices.**

> StockLens doesn't predict prices. It turns official SEC data into transparent rules that separate
> financially healthy companies from weak ones, and it shows its reasons.

Every result shows *why* (which rules passed or failed). Still **not investment advice**.

## New tabs in the app
The app gets a tab bar (bottom navigation bar on phones, tabs/navigation rail on wide screens):

| Tab | What it shows |
|---|---|
| **Screener** | The existing table / cards (unchanged). |
| **Strong vs Weak** | Companies with Quality ≥ 7 ("Strong") and ≤ 3 ("Weak"), side by side on wide screens, switchable on phones. Each row: score and the passed ✓ / failed ✗ rules. |
| **Cheap vs Expensive** | Companies with Value ≥ 7 ("Cheaper than sector peers") and ≤ 3 ("More expensive than peers"), with P/E, P/B, P/S next to the sector median. |
| **Scores** | Every company with Quality and Value (0–10), sortable, sector filter, tap → company page. |

The company page gets a **"Scores" section**: both scores with the full list of rules (✓ / ✗ / — and the actual value).

## Rules (fixed for v3)

### Quality score — "is this a financially healthy company?"
One point per rule that passes. **Score = points ÷ rules that could be checked × 10**, rounded to one decimal.
A rule whose number is missing or "not applicable" is **skipped** (shown as "—"), never counted as pass or fail.
Fewer than **6** checkable rules → no score ("not enough data").

| # | Rule | Metric | Pass if |
|---|---|---|---|
| 1 | Sales grew last year | revenue_growth | > 0 % |
| 2 | Sales grow steadily | revenue_cagr_3y | > 5 % per year |
| 3 | Makes a profit | net_margin | > 0 % |
| 4 | Healthy operating margin | operating_margin | > 15 % |
| 5 | Uses owners' money well | roe | > 15 % |
| 6 | Uses its assets well | roa | > 5 % |
| 7 | Generates cash | fcf | > 0 |
| 8 | Turns sales into cash | fcf_margin | > 10 % |
| 9 | Earnings per share growing | eps_growth | > 0 % |
| 10 | Low debt | debt_to_equity | < 1.0 (not for Financials) |
| 11 | Can pay short-term bills | current_ratio | > 1.0 (not for Financials) |

**Strong:** score ≥ 7. **Weak:** score ≤ 3. In between: "Mixed".

### Value score — "is it cheap or expensive compared with similar companies?"
Compared **within the same sector only** (a bank and a software company have very different normal P/Es).

For each of **P/E (TTM)** (fallback P/E FY), **P/B** and **P/S (TTM)**:
- only positive values count (a negative P/E means a loss — not "cheap");
- the company's **percentile rank** in its sector: 0 = cheapest, 1 = most expensive.

**Value score = (1 − average percentile of the available ratios) × 10.**
Needs at least 2 of the 3 ratios, and at least 5 companies with that ratio in the sector; otherwise no score.
For Financials, P/S is skipped (bank "revenue" is not comparable).

**Cheap:** score ≥ 7. **Expensive:** score ≤ 3. The app always shows the sector median next to the value.

### Combined reading (shown as text, never as "buy"/"sell")
| Quality | Value | Text in the app |
|---|---|---|
| Strong | Cheap | "Strong finances and cheaper than its sector — worth a closer look" |
| Strong | Expensive | "Strong finances, but the market already prices that in" |
| Weak | Cheap | "Cheap, but weak finances — cheap for a reason?" |
| Weak | Expensive | "Weak finances and expensive" |

## Build order for 12 Nov (small steps, tests after each)
1. **Backend `pipeline/scores.py`**: `quality_score()` and `value_scores()` as pure functions returning the score
   and the list of rule results (rule, value, threshold, passed/failed/skipped). Unit tests with hand-computed
   examples, incl. missing data, Financials, too few rules, tiny sectors, negative P/E.
2. **Pipeline + DB + API**: compute after all companies are built (value needs the whole sector); store
   `quality_score`, `value_score` and the rule results (JSON) in `companies`; sector medians; add them to
   `/companies` and `/companies/{ticker}`; `/metrics` gets the two score definitions.
3. **App: tab bar** with the four tabs (bottom bar on phones), reusing cards/table widgets.
4. **App: Strong vs Weak, Cheap vs Expensive, Scores tabs** + "Scores" section on the company page.
5. **Docs**: README section "How the scores work" (rules table, limitations), CLAUDE.md, this plan. Tag `v3.0`,
   new APK, push (ask first).

If time runs short: drop the Cheap vs Expensive tab first (the Scores tab still shows Value), never the tests.

## Honesty / limitations (for the report)
- A good *company* is not automatically a good *stock*: Strong + Expensive means "great company, but the
  market already charges for it".
- Thresholds (15 % ROE, 1.0 D/E, …) are common rules of thumb, not laws — the app shows them openly.
- Value is relative to the sector: a whole sector can be expensive.
- Scores use the latest fiscal year (and TTM for valuation); one bad year can move them a lot.
- Testing the rules on past data has pitfalls (survivorship bias: today's S&P 500 list only contains
  companies that survived; look-ahead bias). StockLens does not claim it beats the market.

## Builds on
- `backend/pipeline/analysis.py` (pros/cons rules) and `metrics.py`; v2 data (S&P 500, TTM, Polygon prices).
