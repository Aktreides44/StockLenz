# StockLens v3 — plan (draft)

Status: **idea agreed 4 Nov 2026, not started.** v3 starts only after v2 is finished (phases 3, 4 and 6).
v3 is the third and final version.

## Goal
Make the "good vs bad" comparison explicit and explainable — **without predicting prices.**

> StockLens doesn't predict prices. It turns official SEC data into transparent rules that separate
> financially healthy companies from weak ones, and it shows its reasons.

Every result shows *why* (which rules passed or failed). Still **not investment advice**.

## New tabs in the app
The app gets a tab bar (bottom bar on phones, top tabs on wide screens):

| Tab | What it shows |
|---|---|
| **Screener** | The existing table / cards (unchanged). |
| **Strong vs Weak** | Two lists side by side (stacked on phones): financially strong companies and weak ones, each with the rules it passed or failed. |
| **Cheap vs Expensive** | Companies ranked by valuation (P/E, P/B, P/S), ideally compared within their own sector. |
| **Scores** | Every company with a **Quality** score and a **Value** score (0–10 each), sortable, with a breakdown of the points. |

## Rules (first draft — to be discussed and tested)
**Quality (strong vs weak)** — one point per rule, scaled to 0–10:
- revenue is growing (revenue_growth > 0, revenue_cagr_3y > 0)
- profitable (net_margin > 0) and margins are decent (operating_margin above a threshold)
- high ROE (> 15 %) and ROA (> 5 %)
- low debt (debt_to_equity < 0.5; not used for Financials)
- positive free cash flow (fcf > 0)
- can pay short-term bills (current_ratio > 1; not used for Financials)

**Value (cheap vs expensive)**:
- P/E, P/B, P/S compared with the **median of the same sector** (a bank and a software company
  are not comparable), so "cheap" means "cheaper than its peers".

Missing data is never counted as a pass or a fail: the rule is skipped and shown as "—", and the score
says how many rules it was based on.

## Honesty / limitations (for the report)
- A good *company* is not automatically a good *stock*: a high Quality score with a low Value score
  means "great company, but the market already charges for it".
- Thresholds (15 % ROE, 0.5 D/E, …) are common rules of thumb, not laws — the app shows them openly.
- Optional, discussion only: testing the rules on past data has pitfalls (survivorship bias: today's
  S&P 500 list only contains companies that survived; look-ahead bias). Don't promise "it beats the market".

## Builds on
- `backend/pipeline/analysis.py` (pros/cons rules already exist) → becomes the scoring module, with tests.
- v2 phase 4 data (S&P 500, TTM) makes the scores more meaningful.
