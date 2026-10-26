# StockLens — project brief for Claude Code

## What this is
StockLens is a university prototype (Medical Informatics, software engineering course): a
fundamental stock screener inspired by Screener.in, for long-term investors. Not a trading app.

**Hard deadline: Wednesday 28 Oct 2026.** Must deliver a working Windows desktop UI with real
screener functionality. iOS is a later goal — keep code platform-neutral, but do not spend time on
iOS builds now.

## Scope for the Wednesday demo (MVP)
In scope:
- 30–50 large US companies (S&P 500 names across several sectors).
- Screener table: search by ticker/name, sort by any column, simple filters (min/max per metric, sector).
- Company detail page: key metrics as cards + 4–5 years of annual revenue / net income / FCF (simple bar or line chart).
- ~12–15 core indicators (list below), each with a visible formula/definition.
- "Missing data" shown as "—" with a tooltip, never as 0 and never invented.

Out of scope until after Wednesday (do NOT build unless asked):
- Scoring engine, five-company evaluation snapshots, comparison page, iOS build,
  user accounts, real-time prices, PEG/ROCE/EV-EBITDA.

## Stack
- `backend/` — Python 3.11+, FastAPI, SQLite (via stdlib `sqlite3` or SQLModel), pytest.
- `app/` — Flutter (Windows desktop target), `http` package, `fl_chart` for charts.
- Data: SEC EDGAR XBRL "companyfacts" API for fundamentals; `yfinance` for latest price and
  shares outstanding (unofficial source — acceptable for prototype, document it in README).

## Architecture
1. `backend/pipeline/` — a script (`python -m pipeline.refresh`) that:
   - loads tickers from `backend/data/universe.csv` (ticker, name, sector)
   - maps ticker → CIK using https://www.sec.gov/files/company_tickers.json
   - downloads `https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json`
   - extracts ANNUAL (form 10-K, fp=FY) values for the fields below, deduplicated by fiscal year
   - fetches latest price via yfinance
   - computes indicators and writes everything to `backend/data/stocklens.db`
   - also exports `app/assets/snapshot.json` so the Flutter app can run offline if the API is down
2. `backend/api/` — FastAPI app reading only from SQLite (never calls SEC at request time):
   - `GET /companies` → list with all screener metrics
   - `GET /companies/{ticker}` → detail incl. yearly history
   - `GET /metrics` → metric definitions (key, label, formula, unit, higher_is_better)
3. `app/` — Flutter calls `http://127.0.0.1:8000`; on failure falls back to `assets/snapshot.json`
   and shows a small "offline snapshot" banner.

## SEC rules (important)
- Every request MUST send a `User-Agent` header like `StockLens student project <EMAIL_FROM_.env>`.
  Read the email from `backend/.env` (`SEC_USER_AGENT=...`). Never hardcode it.
- Max 10 requests/second; add a small sleep. Cache raw JSON in `backend/data/raw/` so reruns don't refetch.

## XBRL field mapping (us-gaap tags; try in order, first one found wins)
- Revenue: `Revenues`, `RevenueFromContractWithCustomerExcludingAssessedTax`, `SalesRevenueNet`,
  `RevenuesNetOfInterestExpense` (banks), `RegulatedAndUnregulatedOperatingRevenue` (utilities)
- Net income: `NetIncomeLoss`, `NetIncomeLossAvailableToCommonStockholdersBasic`
- Operating income: `OperatingIncomeLoss`
- Diluted EPS: `EarningsPerShareDiluted` (unit USD/shares)
- Total assets: `Assets`
- Current assets / liabilities: `AssetsCurrent`, `LiabilitiesCurrent`
- Equity: `StockholdersEquity`, `StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest`
- Long-term debt: `LongTermDebtNoncurrent`, `LongTermDebt`, `LongTermDebtAndCapitalLeaseObligations`,
  `LongTermNotesPayable`
- Operating cash flow: `NetCashProvidedByUsedInOperatingActivities`
- Capex: `PaymentsToAcquirePropertyPlantAndEquipment`, `PaymentsToAcquireProductiveAssets`,
  `PaymentsToAcquireOtherPropertyPlantAndEquipment`, `PaymentsToAcquireOtherProductiveAssets`
- Dividends paid: `PaymentsOfDividends`, `PaymentsOfDividendsCommonStock`, `PaymentsOfOrdinaryDividends`
Record which tag was used per field and fiscal year end date; store it in the DB.

## Indicators for MVP (latest fiscal year unless noted)
| key | formula |
|---|---|
| revenue_growth | (Rev_t − Rev_t-1) / Rev_t-1 × 100 |
| revenue_cagr_3y | (Rev_t / Rev_t-3)^(1/3) − 1, ×100 |
| net_income_growth | (NI_t − NI_t-1) / abs(NI_t-1) × 100; null if NI_t-1 == 0 |
| eps_growth | as above using diluted EPS; null if prior EPS ≤ 0 |
| net_margin | NI / Rev × 100 |
| operating_margin | OpInc / Rev × 100 |
| roe | NI / average(Equity_t, Equity_t-1) × 100; null if avg equity ≤ 0 |
| roa | NI / average(Assets_t, Assets_t-1) × 100 |
| debt_to_equity | LongTermDebt / Equity; null if equity ≤ 0 |
| current_ratio | CurrentAssets / CurrentLiabilities |
| fcf | OCF − Capex |
| fcf_margin | FCF / Rev × 100 |
| pe | Price / diluted EPS; null if EPS ≤ 0 |
| pb | MarketCap / Equity; null if equity ≤ 0 |
| ps | MarketCap / Rev |
| market_cap | Price × shares outstanding |

Any division with a missing or zero denominator → null. Never substitute 0.
Banks/insurers: current_ratio and debt_to_equity are not meaningful — return null and set a
`not_applicable` flag for sector "Financials".

## Testing rules
- `backend/tests/test_calculations.py`: unit tests for every formula with hand-computed values,
  including zero, negative and missing inputs.
- One integration test that runs the extractor on a cached companyfacts JSON for AAPL and checks
  revenue for one known fiscal year against the 10-K.
- Run `pytest` after every change to calculations. Do not mark a task done with failing tests.

## Working conventions
- Work in small steps; after each step tell me exactly what command to run to see it working.
- Commit to git after each working step with a clear message.
- Prefer simple, readable code over clever abstractions — this will be graded and explained by a student.
- Write a `README.md` with: setup, how to run pipeline/API/app, data sources and their limitations,
  metric definitions.
- UI: clean, dark-mode-friendly Material 3, dense data table (like Screener.in), right-aligned numbers,
  percentages to 1 decimal place, large numbers as $1.2B / $340M.
