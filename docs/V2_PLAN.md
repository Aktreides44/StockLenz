# StockLens v2 — plan

Status: **agreed 2 Nov 2026**. Phases 0–4 done (9 Nov 2026); phase 5 (nice-to-haves) / phase 6 (logo) next. We work through the phases in order, in small steps.
Before each step Claude explains what it builds and why; after each step you get the files to look at
in VS Code and a command to try it yourself.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Where the app gets data | **Our FastAPI server, hosted online** (Render free tier first) | Phones and the web can't reach `127.0.0.1` (your PC). A hosted API works everywhere. |
| Offline mode | **Dropped** — no `snapshot.json` inside the app | Keeps the app light; it fetches only what it shows. |
| Platforms | **Web, Android, Windows**; iOS tested on a friend's Mac | Flutter builds all of them from the same code. iOS can only be built on macOS. |
| Financial statements | **SEC EDGAR** (unchanged) + quarterly reports | Official, free, and the original source behind every finance website. |
| Shares outstanding | **SEC** (cover page of each 10-K / 10-Q) instead of Yahoo | Official number, reported by the company itself. |
| Share prices | **Polygon.io** free key (you sign up), yfinance as backup | Official API; one request per day returns closing prices for all US stocks. |
| Companies | **S&P 500** (~500) | The 500 large US companies everyone tracks; easy to explain. |
| Logo | Last phase | Design is easier once the app looks final. |

How the pieces fit together:

```
SEC (10-K/10-Q) ─┐
                 ├─ once a day ─► pipeline ─► SQLite database ─► FastAPI on Render ◄── app (web / Android / iOS / Windows)
Polygon (prices) ┘
```

The heavy part (downloading ~2 GB of SEC files and calculating) happens **only on the server side**.
The app downloads finished numbers: about 1 MB for the whole screener, ~15 KB per company page.

---

## Phase 0 — Lock v1 and put it on GitHub
1. Write `README.md` (setup, how to run, data sources, metric definitions).
2. Tag the current code as `v1.0`, so we can always go back to the version you demoed.
3. You create an empty repository `stocklens` on https://github.com/Aktreides44; we push the code there.
4. Update `CLAUDE.md` with the v2 scope.

**You learn:** what git tags, remotes and pushing are; why secrets (`backend/.env`) must never go to GitHub.
**Done when:** the code is visible on GitHub and `.env` is not.

## Phase 1 — Host the API online
1. Make the backend ready for a server: settings from environment variables, a `/health` endpoint.
2. Deploy to **Render** directly from GitHub (free tier). Store `SEC_USER_AGENT` as a Render secret.
3. Decide how the database gets onto the server: the pipeline builds `stocklens.db` once a day
   (GitHub Actions) and the server loads the newest one.
4. Note: the free tier "sleeps" when nobody uses it — the first request can take 30–60 s. The app will show
   "Waking up the server…" instead of looking broken.

**You learn:** what hosting/deploying means, environment variables, scheduled jobs (cron).
**Done when:** `https://<your-app>.onrender.com/companies` works in any browser, also on your phone.

## Phase 2 — App on web, Android and Windows (iOS later)
1. App reads the API address from one config setting (local for development, Render for real use).
2. Remove offline mode (snapshot + banner); show "Can't connect — Retry" instead.
3. Replace the Windows-only link opener with the `url_launcher` package
   (needs Windows **Developer Mode** turned on — one switch in Windows settings, you do it).
4. **Web:** `flutter build web`, published on GitHub Pages → a link anyone can open.
5. **Android:** run on the emulator (Android Studio) or your own phone via USB; build an `.apk`.
6. **iOS (later, on your friend's Mac):** install Xcode + Flutter, clone from GitHub, run in the iPhone Simulator.
   *Status 3 Nov 2026:* no Mac or iPhone available → iOS stays "code ready, build later";
   iPhone users use the web version.

**You learn:** how one Flutter codebase becomes several apps; what an APK is; why iOS needs a Mac.
**Done when:** the same app runs in a browser, on an Android phone and on Windows, all reading the hosted API.

## Phase 3 — Cleaner UI that works on every screen size
1. One theme file with all colours, spacing and fonts (one font only, to stay light).
2. **Phones:** screener becomes a list of cards with 3 key numbers; filters open as a bottom sheet.
   **Wide screens:** keep the dense table.
   *Feedback from testing on a Samsung S24 (3 Nov 2026):*
   - The frozen Ticker + Name columns (276 px) fill ~70% of a phone screen, so only one metric fits per
     swipe. On phones: cards, or freeze only the ticker.
   - After choosing a sector there was no obvious way back: the dropdown opens scrolled to the chosen
     sector, so "All sectors" is off-screen at the top. Add a visible clear (×) button for the sector,
     and make sure "All sectors" works on the phone. (The toolbar also overflows by ~53 px at phone width.)
3. Search box in the top bar that jumps straight to a company.
4. Company page tidied up for small screens.

**You learn:** responsive layout (one design that adapts), design tokens, basic UX choices.
**Done when:** the app looks good at phone, tablet and desktop width.

## Phase 4 — More companies and better data
1. Universe = **S&P 500** with sectors, from a published constituents list.
2. Shares outstanding from the SEC; prices from **Polygon** (one request per day for all stocks).
3. Coverage report: which companies miss which numbers → add XBRL tag fallbacks where needed.
4. **Quarterly reports (10-Q)** → **TTM** numbers (last 4 quarters), so P/E can be shown both "FY" and "TTM".
5. Price history chart on the company page.
6. Daily automatic refresh with GitHub Actions; raw SEC files are deleted after extraction.

**You learn:** what the S&P 500 is, annual vs quarterly reports, TTM, why data has gaps.
**Done when:** ~500 companies load, with a coverage report showing what is missing and why.

## Phase 5 — Nice-to-haves (only if time allows)
- Choose which columns to show in the screener.
- Saved filter presets, e.g. "Profitable & low debt".
- Watchlist saved on the device.

## Phase 6 — Logo and branding
- Logo concept (e.g. a lens + bar chart), app icons for every platform, splash screen, web favicon.

---

## Beginner's glossary (the terms StockLens uses)

| Term | Plain meaning | Example from our data |
|---|---|---|
| **Stock / share** | A tiny piece of ownership in a company. | One Apple share ≈ $344. |
| **Ticker** | The short code a stock trades under. | AAPL = Apple, KO = Coca-Cola. |
| **S&P 500** | A list of ~500 of the largest US companies, used as "the US market". | Apple, Microsoft, JPMorgan are all in it. |
| **10-K / 10-Q** | The yearly (10-K) and quarterly (10-Q) reports US companies must file with the SEC. | Our numbers come from these. |
| **SEC / EDGAR** | The US market regulator / its public database of filings. | Where the pipeline downloads data. |
| **Fiscal year (FY)** | A company's own 12-month accounting year; it doesn't have to match the calendar. | Apple's FY2025 ended 27 Sep 2025. |
| **TTM** | "Trailing twelve months": the last 4 quarters added up — more up-to-date than the last FY. | Coming in phase 4. |
| **Revenue** | All money from selling products/services, before costs. | Apple FY2025: $416B. |
| **Net income (profit)** | What is left after all costs and taxes. | Apple FY2025: $112B. |
| **Market cap** | Price × number of shares = what the market says the whole company is worth. | Apple ≈ $5T. |
| **EPS** | Earnings per share = net income ÷ number of shares. | Apple: $7.46. |
| **P/E** | Price ÷ EPS: how many years of current profit you pay for. High = expensive or high growth expected. | Apple 46. |
| **Equity** | What the company owns minus what it owes (assets − liabilities). | Can be negative (McDonald's). |
| **ROE** | Profit ÷ equity: how well a company uses the owners' money. | >15% is usually seen as strong. |
| **Debt / Equity** | How much long-term debt per $1 of equity. | Below 0.5 = low debt. |
| **Free cash flow (FCF)** | Cash from operations minus spending on buildings/equipment = cash the company can actually use. | Apple FY2025: $98.8B. |
| **Screener** | A tool to filter many companies by numbers, e.g. "ROE > 15% and P/E < 20". | That's StockLens. |

StockLens shows facts and simple rules — **it is not investment advice.**
