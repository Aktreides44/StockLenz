# How data travels in StockLens — from the SEC and Polygon to the screen

This guide follows the data through every script, in the order it happens.
Written 4 Nov 2026, updated 7 Nov 2026, for StockLens v2 (phase 4: S&P 500, Polygon prices,
SEC share counts, TTM, coverage report).

---

## The big picture

```
 ① LIST OF COMPANIES        backend/data/universe.csv  (S&P 500, read once from Wikipedia)
          │
 ② EVERY WEEKDAY 22:30 UTC  GitHub Actions starts  .github/workflows/refresh-data.yml
          │
          ├── ③ SEC  ──────────  company reports (revenue, profit, debt, shares…)   1 request per company
          │                       sec_updates.py → sec_client.py → extract.py + shares.py
          │
          ├── ④ POLYGON  ─────  yesterday's closing price of every US stock         1 request in total
          │                       prices.py
          ▼
 ⑤ COMBINE + CALCULATE      refresh.py → metrics.py (16 ratios) → analysis.py (pros/cons)
          ▼
 ⑥ DATABASE                 db.py → stocklens.db → check_database.py → GitHub release "data-latest"
          ▼
 ⑦ SERVER (Render)          api/database_file.py downloads it, api/main.py answers /companies …
          ▼
 ⑧ APP (web/Android/Win)    config.dart → data_service.dart → models.dart → screens
```

The **heavy, slow work (③–⑥) happens once a day on GitHub**, never while someone uses the app.
The app only ever talks to the server (⑦), and the server only reads a finished file.

---

## ① The list of companies — `universe.csv`

| | |
|---|---|
| File | `backend/data/universe.csv` |
| Made by | `python -m pipeline.update_universe` (`backend/pipeline/update_universe.py`) |
| Source | Wikipedia's "List of S&P 500 companies" table, read **once**, saved with the date in a `#` comment line |
| Contents | `ticker, name, sector, cik` (cik only filled in as an override, e.g. Exxon) |

The script checks every ticker against the SEC's official ticker list, so a typo or outdated row on
Wikipedia is caught before it is used. The list only decides **which** companies are shown — all
numbers come from the SEC and Polygon.

Tickers are written with a dot (`BRK.B`). The SEC and Yahoo write `BRK-B`, so `sec_ticker()` in
`sec_client.py` converts them.

---

## ② The daily job starts — `refresh-data.yml`

A "workflow" is a list of instructions for a computer that GitHub lends us for free.

| Step in the workflow | What it does |
|---|---|
| Schedule | `cron: "30 22 * * 1-5"` → 22:30 UTC, Monday–Friday (after the US market closes). GitHub often starts scheduled jobs late when it is busy: so far they started around 02:15–02:45 UTC. Can also be started by hand with **Run workflow**. |
| Get the code, install Python + packages | A fresh, empty computer every time. |
| **Restore the saved SEC files** | `actions/cache` brings back `backend/data/raw/` from the last run, so we don't download 500 files again. |
| Run tests | `pytest`. If a test fails, the job stops and **yesterday's data stays online**. |
| Build the database | `python -m pipeline.refresh` — stages ③ to ⑥ below. Secrets `SEC_USER_AGENT` and `POLYGON_API_KEY` are passed in. |
| Check the database | `python -m pipeline.check_database` |
| Write the coverage report | `python -m pipeline.coverage` → `coverage.md` |
| Publish | Uploads `stocklens.db` and `coverage.md` to the GitHub release `data-latest`, replacing yesterday's files. |

The secrets are stored encrypted on GitHub (Settings → Secrets) and never appear in the code or logs.

---

## ③ The SEC route — company reports

The SEC (US market regulator) stores every company's reports. Its free API gives one file per
company with every number the company ever reported.

### ③a Which saved files are out of date? — `sec_updates.py`
- The SEC publishes a **daily index**: a list of every filing made that day.
  ```
  CIK|Company Name|Form Type|Date Filed|Filename
  320193|Apple Inc.|10-K|20261031|edgar/data/320193/...
  ```
- `remove_outdated_files()` reads the lists since each file was downloaded (dates kept in
  `raw/downloaded.json`) and **deletes the saved file of every company that filed a new 10-K or 10-Q**.
- Safety net: any file older than 30 days is refreshed anyway.
- Result: on a normal day only a handful of companies are downloaded again, not 500.

### ③b Ticker → CIK — `sec_client.py → load_ticker_to_cik()`
- Downloads `https://www.sec.gov/files/company_tickers.json` (the SEC's "phone book").
- `AAPL → 320193`. The SEC identifies companies by this number (CIK), not by ticker.
- If `universe.csv` has a `cik` value, that one wins (needed for Exxon, see v1).

### ③c Download each company's file — `sec_client.py → load_companyfacts()`
```
https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json
```
- Every request sends the **User-Agent** (`StockLens student project <email>`) from `SEC_USER_AGENT` —
  the SEC requires it.
- Waits **0.2 s** after each request (max 5 per second; the SEC allows 10).
- Saves the file in `backend/data/raw/` (`get_cached_json`) and notes the date in `downloaded.json`.
  If the file is already there, it is read from disk — no request.

### ③d Pick out the numbers we need — `extract.py → extract_company()`
A companyfacts file has thousands of values (every quarter, every year, many labels). We keep:
- only values from **10-K** filings that cover a **full year** (350–380 days) — `annual_values()`;
- for each field, the **first label found** in our fallback list (`FIELDS`), e.g. revenue tries
  `Revenues`, then `RevenueFromContractWithCustomerExcludingAssessedTax`, then …;
- if a number was restated, the **latest filing wins**;
- years are named by `fiscal_year_label()` (a year ending on or before 7 Jan counts as the year before);
- the **last 5 fiscal years**.

Result per company:
```
{2026: {"end_date": "2026-09-26",
        "fields": {"revenue":    {"value": 478834000000, "tag": "RevenueFromContractWith…"},
                   "net_income": {"value": 132175000000, "tag": "NetIncomeLoss"},
                   "dividends_paid": None,        # None = not reported → shown as "—"
                   …}},
 2025: {…}, …}
```

### ③e Shares outstanding — `shares.py → extract_shares()`
Needed for market cap (price × shares). From the same SEC file, first fresh source wins:
1. **SEC cover page** — `dei:EntityCommonStockSharesOutstanding` (the number on the first page of each 10-K/10-Q)
2. **SEC balance sheet** — `us-gaap:CommonStockSharesOutstanding`
3. **SEC average in the period** — `us-gaap:WeightedAverageNumberOfSharesOutstandingBasic`

"Fresh" = at most 365 days older than the latest fiscal year end. If none qualifies → Yahoo (backup).

### ③f The last 12 months (TTM) — `ttm.py → extract_ttm()`
The yearly numbers can be up to a year old. TTM ("trailing twelve months") uses the quarterly
reports (10-Q) to get the most recent 12 months. Companies don't report a 4th quarter on its own,
but each 10-Q has "year to date" values next to the same months of the year before, so:

```
TTM = last full fiscal year (10-K) + this year's months so far − the same months a year earlier
```
Apple: FY2025 revenue $416.16B + 9 months to 27 Jun 2026 $364.36B − 9 months to 28 Jun 2025 $313.70B
= **$466.82B** for the 12 months to 27 Jun 2026.

- Done for revenue, net income and diluted EPS; used for **P/E (TTM)** and **P/S (TTM)**.
- If the 10-K is the newest report, TTM = that fiscal year. If the comparison period is missing → `None`.
- All three parts come from the same XBRL tag, so different definitions are never mixed.

---

## ④ The Polygon route — prices — `prices.py → latest_closes()`

Polygon (now also called Massive) sells market data; its free plan includes end-of-day prices.

```
https://api.polygon.io/v2/aggs/grouped/locale/us/market/stocks/2026-11-03?adjusted=true&apiKey=…
```
- **One request returns the closing price of every US stock** for that day (~12,600 tickers).
- `parse_grouped_daily()` turns the answer into `{"AAPL": 331.90, "MSFT": 520.99, …}`.
- The free plan has no prices for *today*, so it asks for **yesterday**. On a weekend or holiday
  there is no data, so it steps back one more day (up to 5), waiting 12 s between tries
  (free plan: 5 requests per minute).
- The key comes from `POLYGON_API_KEY` and is **never printed** — error messages show only the date
  and the status code.
- **Backup:** if a ticker has no Polygon price, `yahoo_price_and_shares()` asks Yahoo Finance for
  that one company.

---

## ⑤ Combine and calculate — `refresh.py`

`main()` loops over every company in `universe.csv`. For each one, `build_company()`:

1. reads its SEC file (③c) and extracts the years (③d) — if no annual 10-K data: skipped, with a warning;
2. gets the SEC share count (③e);
3. `choose_price_and_shares()` — Polygon price, SEC shares; Yahoo only for what is missing.
   It records **where each number came from** (`price_source`, `shares_source`) so the app can show it;
4. `ttm.py → extract_ttm()` gets the last-12-months revenue, net income and EPS (③f);
   `metrics.py → compute_all()` calculates the ratios (16 yearly + P/E TTM and P/S TTM) (formulas in the README / CLAUDE.md).
   Each formula is a small function with unit tests. Missing or zero denominator → `None`, never 0;
5. `explain_missing()` writes a plain-English reason for every `None` (shown as a tooltip on "—");
6. Financials: current ratio and debt/equity are marked **not applicable**.

At the end it prints a **coverage table**: for each metric, how many companies have a value and which miss it.

---

## ⑥ The database — `db.py`, `check_database.py`

`write_database()` replaces `backend/data/stocklens.db` (SQLite: one file, no server) with 3 tables:

| Table | One row per | Holds |
|---|---|---|
| `companies` | company | ticker, name, sector, price + source + date, shares + source, the 16 metrics, missing reasons |
| `financials` | company × fiscal year | the raw yearly values and which XBRL tag each came from |
| `metric_definitions` | metric | label, formula, unit, "higher is better" |

`check_database.py` refuses to publish if fewer than **90 %** of the companies made it, or fewer than
90 % have a price (e.g. a price source was blocked). Then the workflow stops and the old database
stays online.

The finished file is small (a few MB for ~500 companies) because it only holds the results, not the
raw SEC files.

**Coverage report** (`python -m pipeline.coverage`): reads the finished database and writes
`coverage.md` — for each metric, which companies miss it and why (the same reasons as the "—"
tooltips). The workflow publishes it next to `stocklens.db` in the `data-latest` release every day.

---

## ⑦ The server — Render — `api/database_file.py`, `api/main.py`

Render runs our FastAPI app 24/7 at `https://stocklens-api-43hi.onrender.com` (free plan: it sleeps
after ~15 min without visitors; the first request then takes 30–60 s).

**Getting the database** (`database_file.py → refresh_if_needed()`):
- Setting `STOCKLENS_DB_URL` = `https://github.com/Aktreides44/StockLenz/releases/download/data-latest/stocklens.db`
- Downloads it **when the server starts**, and again when its copy is **older than 6 hours**.
- Downloads to a temporary file first, then swaps it in, so a half-finished download is never used.
- If GitHub can't be reached, it keeps serving its current copy.

**Answering the app** (`main.py`) — read-only, never calls the SEC or Polygon:

| Address | Answer |
|---|---|
| `/companies` | all companies with every screener metric (`db.load_companies`) |
| `/companies/AAPL` | one company + yearly history + yearly ratios + pros/cons (`db.load_company_detail`, `analysis.py`) |
| `/metrics` | the metric definitions (labels, formulas) |
| `/health` | is the server up, how many companies, prices as of when |

Answers are **JSON** (structured text). CORS allows any website to read them (needed for the web app).

---

## ⑧ The app — Flutter (`app/lib/`)

| Step | File | What happens |
|---|---|---|
| Which server? | `config.dart` | `API_URL` = the Render address (or `http://127.0.0.1:8000` for local testing via `--dart-define`) |
| Ask the server | `data_service.dart` | `loadScreenerData()` → `GET /metrics` and `GET /companies`; `loadCompanyDetail()` → `GET /companies/AAPL`. No answer → "Can't connect — Retry"; slow → "Waking up the server…" |
| JSON → objects | `models.dart` | `Company.fromJson`, `MetricDefinition`, `CompanyDetail` turn text into Dart objects |
| Screener screen | `screener_page.dart` | search, sector, min/max filters, sorting; then `isPhone()` (`theme.dart`, < 600 px) picks the layout |
| … wide screens | `screener_table.dart` | dense table, frozen ticker + name |
| … phones | `screener_cards.dart` | one card per company: market cap, P/E, ROE |
| Formatting | `format.dart` | `$4.82T`, `27.6%`, missing → "—" with the reason as tooltip (`widgets.dart`) |
| Company page | `company_page.dart`, `company_sections.dart`, `company_chart.dart` | key ratios, revenue/profit chart (`fl_chart`), pros/cons, peers, yearly tables |

The same code is built for the web (GitHub Pages), Android (APK) and Windows.

---

## Worked example: Apple, one number at a time (live data, 4 Nov 2026)

| Stage | What we got |
|---|---|
| ① | `AAPL, Apple Inc., Information Technology` in `universe.csv` |
| ③b | AAPL → CIK **320193** |
| ③d | FY2026 (ended 26 Sep 2026): revenue **$478,834M** (tag `RevenueFromContractWithCustomerExcludingAssessedTax`), net income **$132,175M**, diluted EPS **$8.98** |
| ③e | shares **14,532,182,000** — source "SEC cover page (10-K)", as of 23 Oct 2026 |
| ④ | close **$331.90** on 3 Nov 2026 — source "Polygon close" |
| ⑤ | market cap = 331.90 × 14,532,182,000 = **$4.82T** · P/E = 331.90 ÷ 8.98 = **37.0** · net margin = 132,175 ÷ 478,834 = **27.6 %** |
| ⑥ | one row in `companies`, five rows in `financials` |
| ⑦ | `GET /companies/AAPL` returns these numbers as JSON |
| ⑧ | Apple's card: **Mkt cap $4.82T · P/E (FY) 36.96 · ROE 142.3%** (`format.dart`: trillions with 2 decimals, ratios with 2, percentages with 1) |

---

## When something goes wrong

| Problem | What happens |
|---|---|
| A company has no annual 10-K data | skipped, listed in the log |
| A number isn't reported | stored as `None`, shown as "—" with a reason; never 0 |
| Polygon has no price for a ticker | Yahoo Finance for that ticker; `price_source` says so |
| No fresh SEC share count | Yahoo Finance; `shares_source` says so |
| A test fails, or the database looks broken | the workflow stops; **yesterday's data stays online** |
| GitHub unreachable from Render | the server keeps its current copy |
| Render asleep | app shows "Waking up the server…" |
| Server unreachable | app shows "Can't connect — Retry" |

## How fresh is each number?

| Data | Changes | Reaches the app |
|---|---|---|
| Prices | every trading day | next day (previous close), after the 22:30 UTC job + up to 6 h on Render |
| Financial statements | when a company files (≈ 4×/year) | the next job after the filing |
| Company list | when we re-run `update_universe` | manually, then committed to git |
