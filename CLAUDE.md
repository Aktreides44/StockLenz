# StockLens — project brief for Claude Code

## What this is
StockLens is a university project (Medical Informatics, software engineering course): a
fundamental stock screener inspired by Screener.in, for long-term investors. Not a trading app,
and it shows facts and simple rules — never investment advice.

**v1.0 is done and tagged** (`git checkout v1.0`): the Windows app demoed on 28 Oct 2026 — 40
companies, SEC 10-K data, yfinance prices, offline snapshot fallback.

**Now building v2.** The scope, decisions and order of work are in [`docs/V2_PLAN.md`](docs/V2_PLAN.md).
Work through its phases in order, in small steps. That plan replaces the old v1 "out of scope" list:
build what the current phase says, and nothing from a later phase unless asked.

## v2 target (see the plan for why)
- **Hosted API:** the FastAPI backend runs online on **Render** (free tier first); the app talks to it,
  not to `127.0.0.1`. Settings (e.g. `SEC_USER_AGENT`) come from environment variables / Render secrets.
- **No offline mode:** no `snapshot.json` in the app. If the API can't be reached, show
  "Can't connect — Retry" (and "Waking up the server…" while Render's free tier starts).
- **Platforms:** one Flutter codebase for **web, Android and Windows**; **iOS** later (built on a Mac).
  Keep code platform-neutral (no `dart:io`-only features in shared code).
- **Companies:** the **S&P 500** (~500), from a published constituents list.
- **Prices:** **Polygon.io** (one daily request for all US closing prices), yfinance only as backup.
  **Shares outstanding:** from the SEC (10-K/10-Q cover page), not Yahoo.
- **Data refresh:** the pipeline runs once a day (GitHub Actions), not on the user's PC.

Until a phase changes it, the code still works the v1 way (yfinance, 40 companies).
Done so far: hosted API (phase 1); API address in `config.dart`, offline snapshot removed and links
opened with `url_launcher` (phase 2 steps 1–3). When a phase replaces something, update this file and the README.

## Stack
- `backend/` — Python 3.11+, FastAPI, SQLite (stdlib `sqlite3`), pytest. Hosted on Render (v2).
- `app/` — Flutter (web, Android, Windows; iOS later), `http` package, `fl_chart` for charts.
- Data: SEC EDGAR XBRL "companyfacts" API for fundamentals (+ 10-Q for TTM in phase 4);
  Polygon.io for prices (v2), `yfinance` as backup.

## Architecture
1. `backend/pipeline/` — a script (`python -m pipeline.refresh`) that:
   - loads tickers from `backend/data/universe.csv` (ticker, name, sector, optional cik override)
   - maps ticker → CIK using https://www.sec.gov/files/company_tickers.json
   - downloads `https://data.sec.gov/api/xbrl/companyfacts/CIK##########.json`
   - extracts ANNUAL (form 10-K, fp=FY) values for the fields below, deduplicated by fiscal year
   - fetches the latest price (v1: yfinance; v2: Polygon)
   - computes indicators and writes everything to `backend/data/stocklens.db`
   - in v2 it runs in GitHub Actions (`.github/workflows/refresh-data.yml`, weekdays), is checked by
     `python -m pipeline.check_database`, and the DB is uploaded to the GitHub release `data-latest`
2. `backend/api/` — FastAPI app reading only from SQLite (never calls SEC at request time).
   On Render it downloads the DB from `STOCKLENS_DB_URL` at startup and when its copy is > 6 h old
   (`api/database_file.py`); locally that setting is empty and the pipeline's file is used.
   - `GET /companies` → list with all screener metrics
   - `GET /companies/{ticker}` → detail incl. yearly history
   - `GET /metrics` → metric definitions (key, label, formula, unit, higher_is_better)
3. `app/` — Flutter reads the API address from `app/lib/config.dart`: the Render URL by default,
   `--dart-define=API_URL=http://127.0.0.1:8000` for a local API. No offline data: while loading
   it shows "Waking up the server…" after 5 s, on failure "Can't connect" + Retry (`widgets.dart`).

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
- Work in small steps. Before each step explain what you build and why (in plain words — I'm new to
  coding tools and to the stock market); after each step tell me exactly what command to run to see it working.
- Commit to git after each working step with a clear message.
- Git/GitHub: the repo is https://github.com/Aktreides44/StockLenz (remote `origin`, branch `main`).
  Commits use my GitHub noreply email (set as this repo's `user.email`) — never my personal email.
  No "Co-Authored-By: Claude" (or any Claude attribution) line in commit messages — I'm the only author.
  Ask me before every push. Never commit `backend/.env`, `backend/data/raw/` or `*.db`.
  Never rewrite history that has already been pushed.
- Prefer simple, readable code over clever abstractions — this will be graded and explained by a student.
- Write a `README.md` with: setup, how to run pipeline/API/app, data sources and their limitations,
  metric definitions.
- UI: clean, dark-mode-friendly Material 3, dense data table (like Screener.in), right-aligned numbers,
  percentages to 1 decimal place, large numbers as $1.2B / $340M.
