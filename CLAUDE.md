# StockLens — project brief for Claude Code

## What this is
StockLens is a university project (Medical Informatics, software engineering course): a
fundamental stock screener inspired by Screener.in, for long-term investors. Not a trading app,
and it shows facts and simple rules — never investment advice.

**v1.0 is done and tagged** (`git checkout v1.0`): the Windows app demoed on 28 Oct 2026 — 40
companies, SEC 10-K data, yfinance prices, offline snapshot fallback.

**v2.0 is done** (tag `v2.0`, 11 Nov 2026): every phase of [`docs/V2_PLAN.md`](docs/V2_PLAN.md) is built — what v2
contains is listed below. **v3 is planned** in [`docs/V3_PLAN.md`](docs/V3_PLAN.md); don't start it unless asked.
Work in small steps; build nothing from a later plan unless asked.

## What v2 contains (see the plan for why)
- **Hosted API:** the FastAPI backend runs online on **Render** (free tier first); the app talks to it,
  not to `127.0.0.1`. Settings (e.g. `SEC_USER_AGENT`) come from environment variables / Render secrets.
- **No offline mode:** no `snapshot.json` in the app. If the API can't be reached, show
  "Can't connect — Retry" (and "Waking up the server…" while Render's free tier starts).
- **Platforms:** one Flutter codebase for **web, Android and Windows** (all working). **iOS**: code ready,
  build later — no Mac available; iPhone users use the web version.
  Keep code platform-neutral (no `dart:io`-only features in shared code).
- **Companies:** the **S&P 500** (~500), from a published constituents list.
- **Prices:** **Polygon.io** (one daily request for all US closing prices), yfinance only as backup.
  **Shares outstanding:** from the SEC (10-K/10-Q cover page), not Yahoo.
- **Data refresh:** the pipeline runs once a day (GitHub Actions), not on the user's PC.

Phase 4 step 2 done: shares outstanding from the SEC (`pipeline/shares.py`; source stored as `shares_source`), Yahoo as backup.
Phase 4 step 3 done: closing prices from Polygon grouped daily (`pipeline/prices.py`, `POLYGON_API_KEY`; `price_source`),
Yahoo only for gaps.
Phase 4 step 4 done: only changed SEC files are downloaded again (`pipeline/sec_updates.py`: daily filing index +
`raw/downloaded.json`, 30-day safety net); `raw/` kept between Actions runs with `actions/cache`.
Phase 4 step 7 done: price chart — daily closes kept in the `prices` table (`pipeline/price_history.py`: carried over from
yesterday's published DB, backfill `PRICE_BACKFILL_DAYS`, re-adjust after splits), `price_history` in the detail API, `price_chart.dart`.
Phase 4 done.
Phase 6 done (logo): icons + splash from `docs/logo_icon.png` / `docs/logo_foreground.png` (`flutter_launcher_icons`,
`flutter_native_splash`, settings in `app/pubspec.yaml`), logo in the top bar (`app/assets/logo.png`), accent = logo green
(`logoGreen`/`logoNavy` in `theme.dart`).
Phase 5 done: filter presets (`presets.dart`: 4 examples + your own, saved as JSON) and a watchlist (`watchlist.dart`:
one shared `ChangeNotifier`, ☆ in table/cards/company page, "Watchlist" filter), both saved via `device_settings.dart`.
Phase 5 step 1 done: "Columns" picker (wide screens), hidden columns saved on the device (`device_settings.dart`,
`shared_preferences`; also the place for presets and the watchlist).
Phase 4 step 6 done: TTM revenue/net income/EPS (`pipeline/ttm.py`), metrics P/E (TTM) and P/S (TTM), `ttm_end` shown in the app.
Phase 4 step 5 done: coverage report `python -m pipeline.coverage` (published daily next to the DB); 3 fallback tags.
Phase 4 step 1 done: S&P 500 in `universe.csv` from `python -m pipeline.update_universe` (Wikipedia, read once).
Done so far: hosted API (phase 1); API address in `config.dart`, offline snapshot removed and links
opened with `url_launcher`, web app on GitHub Pages via `.github/workflows/deploy-web.yml`, Android app (phase 2 done); theme file and phone layout with cards, sort menu,
filter bottom sheet and a sector ✕ button, 🔍 company search in the top bar (`company_search.dart`), company page for phones
(fixed row labels in year tables, 3 peer columns) (phase 3 done). When a phase replaces something, update this file and the README.

## Stack
- `backend/` — Python 3.11+, FastAPI, SQLite (stdlib `sqlite3`), pytest. Hosted on Render (v2).
- `app/` — Flutter (web, Android, Windows; iOS later), `http` package, `fl_chart` for charts.
- Data: SEC EDGAR XBRL "companyfacts" API for fundamentals (+ 10-Q for TTM in phase 4);
  Polygon.io for prices (v2), `yfinance` as backup.

## Architecture
1. `backend/pipeline/` — a script (`python -m pipeline.refresh`) that:
   - loads tickers from `backend/data/universe.csv` (ticker, name, sector, optional cik override; `#` lines are
     comments). Tickers use dots (`BRK.B`); `sec_ticker()` converts to `BRK-B` for the SEC and Yahoo.
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
  `RevenuesNetOfInterestExpense` (banks), `RegulatedAndUnregulatedOperatingRevenue` (utilities),
  `RevenueFromContractWithCustomerIncludingAssessedTax`
- Net income: `NetIncomeLoss`, `NetIncomeLossAvailableToCommonStockholdersBasic`, `ProfitLoss`
- Operating income: `OperatingIncomeLoss`
- Diluted EPS: `EarningsPerShareDiluted` (unit USD/shares)
- Total assets: `Assets`
- Current assets / liabilities: `AssetsCurrent`, `LiabilitiesCurrent`
- Equity: `StockholdersEquity`, `StockholdersEquityIncludingPortionAttributableToNoncontrollingInterest`
- Long-term debt: `LongTermDebtNoncurrent`, `LongTermDebt`, `LongTermDebtAndCapitalLeaseObligations`,
  `LongTermNotesPayable`
- Operating cash flow: `NetCashProvidedByUsedInOperatingActivities`, `NetCashProvidedByUsedInOperatingActivitiesContinuingOperations`
- Never fill a field with a different number (e.g. pre-tax income for operating income): leave it null.
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
| pe_ttm | Price / TTM diluted EPS; null if TTM EPS ≤ 0 |
| ps_ttm | MarketCap / TTM revenue |

TTM = latest 10-K value + latest 10-Q year-to-date − the same period a year earlier (`pipeline/ttm.py`);
= the FY value when the 10-K is the latest report; null when the comparison period is missing.

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
- UI: colours, spacing (`Space.*`), text sizes (`FontSizes.*`), radii and the phone breakpoint (`isPhone`,
  < 600 px) live in `app/lib/theme.dart` — use those, not loose numbers. Clean, dark-mode-friendly Material 3, dense data table (like Screener.in), right-aligned numbers,
  percentages to 1 decimal place, large numbers as $1.2B / $340M.
