# StockLens — prompts to paste into Claude Code, in order

Paste ONE prompt, let it finish, check the result yourself, then move to the next.
If something breaks, paste the error and say "fix this". Type `/clear` between big steps
to keep its context fresh (CLAUDE.md is re-read automatically).

---

## Prompt 1 — Set up the project (≈20 min)
```
Read CLAUDE.md. Set up the repo: git init, create backend/ (Python venv, requirements.txt with
fastapi, uvicorn, requests, yfinance, python-dotenv, pytest), backend/.env.example with
SEC_USER_AGENT, a .gitignore, and backend/data/universe.csv with 40 large US companies across
at least 6 sectors (ticker,name,sector). Then check that python, flutter and git are installed
and tell me anything missing. Don't build features yet.
```
→ Then: copy `.env.example` to `.env` and put your real email in it.

## Prompt 2 — Prove the data works (≈1 h) — MOST IMPORTANT STEP
```
Build the SEC extraction part of the pipeline for just AAPL, MSFT, JNJ, KO and JPM. Print a
table per company with each raw field from CLAUDE.md for the last 5 fiscal years, the XBRL tag
used, and the fiscal year end date. Show me which fields are missing for which company.
```
→ Check: open Apple's 10-K revenue figure on Google and compare with what it printed.

## Prompt 3 — Calculations + tests (≈1 h)
```
Implement all MVP indicators from CLAUDE.md in backend/pipeline/metrics.py as pure functions,
with pytest tests for normal, zero, negative and missing inputs. Run the tests until they pass.
Then finish the pipeline: all companies in universe.csv, latest price via yfinance, write to
SQLite and export app/assets/snapshot.json. Run it and show me a summary of coverage per metric.
```

## Prompt 4 — API (≈30 min)
```
Build the FastAPI app from CLAUDE.md (/companies, /companies/{ticker}, /metrics) with CORS
enabled. Add a test using TestClient. Tell me the command to start it and a URL to check in
my browser.
```

## Prompt 5 — Flutter screener (≈2–3 h)
```
Create the Flutter app in app/ targeting Windows. Screen 1: screener table with all companies
and metrics, search box (ticker/name), click-to-sort column headers, sector dropdown filter,
and a "Filters" panel with min/max for any metric. Load from the API; fall back to
assets/snapshot.json with an "offline snapshot" banner. Missing values show "—" with a tooltip.
Follow the UI conventions in CLAUDE.md. Run it with `flutter run -d windows` and fix errors.
```

## Prompt 6 — Company page (≈1–2 h)
```
Add the company detail page: header (name, ticker, sector, price, market cap), metric cards
grouped Growth / Profitability / Financial health / Valuation / Cash flow, each with an info
icon showing the formula from /metrics, and fl_chart bar charts of revenue, net income and FCF
for the last 5 years. Clicking a row in the screener opens it.
```

## Prompt 7 — Polish + deliver (Wednesday morning)
```
Review the whole project for bugs and rough edges. Write README.md as described in CLAUDE.md.
Build a Windows release (`flutter build windows`) and tell me where the .exe is and what other
files must ship with it. Write a 5-step demo script I can follow in front of my professor.
```

---

## Only if time remains
- Save "evaluation snapshots" for the five professor-selected companies (frozen inputs, date, price).
- Comparison page (2–3 companies side by side).
- Transparent scoring (Fundamental Strength Score).
