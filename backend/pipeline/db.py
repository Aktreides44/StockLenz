"""SQLite storage: the pipeline writes here, the API reads from here.

Tables:
- companies: one row per company, with price info and every screener metric as a column
- financials: the raw SEC values, one row per (company, fiscal year, field), incl. the XBRL tag used
- metric_definitions: label, formula and unit for each metric, shown in the app
- prices: daily closing prices of the last year, for the price chart (pipeline/price_history.py)
- price_days: the days the price history has already asked Polygon for (incl. holidays)
"""
import json
import sqlite3

from pipeline.extract import FIELDS
from pipeline.analysis import pros_and_cons
from pipeline.metrics import METRIC_DEFINITIONS, METRIC_KEYS, fcf, yearly_ratios
from config import DB_PATH

COMPANY_COLUMNS = [
    "ticker", "name", "sector", "cik", "price", "price_source", "price_fetched_at",
    "shares_outstanding", "shares_source", "shares_as_of",
    "latest_fiscal_year", "latest_fiscal_year_end",
    "ttm_end", "revenue_ttm", "net_income_ttm", "eps_ttm",
] + METRIC_KEYS


def connect(path=DB_PATH):
    # check_same_thread=False: FastAPI may open the connection and use it on different worker threads
    conn = sqlite3.connect(path, check_same_thread=False)
    conn.row_factory = sqlite3.Row  # lets us read rows like dicts: row["ticker"]
    return conn


def create_tables(conn):
    metric_columns = ",\n".join(f"    {key} REAL" for key in METRIC_KEYS)
    conn.executescript(f"""
DROP TABLE IF EXISTS companies;
DROP TABLE IF EXISTS financials;
DROP TABLE IF EXISTS metric_definitions;
DROP TABLE IF EXISTS prices;
DROP TABLE IF EXISTS price_days;

CREATE TABLE companies (
    ticker TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    sector TEXT NOT NULL,
    cik INTEGER NOT NULL,
    price REAL,
    price_source TEXT,    -- "Polygon close" or "Yahoo Finance (backup)"
    shares_outstanding REAL,
    shares_source TEXT,   -- where the share count comes from, e.g. "SEC cover page (10-Q)"
    shares_as_of TEXT,    -- the date the share count refers to (None for Yahoo)
    price_fetched_at TEXT, -- Polygon: the trading day of the close; Yahoo: when it was downloaded
    latest_fiscal_year INTEGER,
    latest_fiscal_year_end TEXT,
    ttm_end TEXT,          -- where the trailing 12 months end (latest 10-Q, or the fiscal year end)
    revenue_ttm REAL,      -- trailing-twelve-month values (pipeline/ttm.py); NULL if not calculable
    net_income_ttm REAL,
    eps_ttm REAL,
    not_applicable TEXT,  -- comma-separated metric keys, e.g. "current_ratio,debt_to_equity"
    missing_reasons TEXT, -- JSON object mapping metric key to why it has no value
{metric_columns}
);

CREATE TABLE financials (
    ticker TEXT NOT NULL,
    fiscal_year INTEGER NOT NULL,
    end_date TEXT NOT NULL,
    field TEXT NOT NULL,
    value REAL,  -- NULL when the company did not report it
    tag TEXT,    -- the us-gaap XBRL tag the value came from
    PRIMARY KEY (ticker, fiscal_year, field)
);

CREATE TABLE prices (
    ticker TEXT NOT NULL,
    day TEXT NOT NULL,     -- trading day, "YYYY-MM-DD"
    close REAL NOT NULL,   -- closing price that day (split-adjusted)
    PRIMARY KEY (ticker, day)
) WITHOUT ROWID;

CREATE TABLE price_days (
    day TEXT PRIMARY KEY
);

CREATE TABLE metric_definitions (
    key TEXT PRIMARY KEY,
    label TEXT NOT NULL,
    group_name TEXT NOT NULL,
    formula TEXT NOT NULL,
    unit TEXT NOT NULL,
    higher_is_better INTEGER NOT NULL,
    sort_order INTEGER NOT NULL
);
""")


def write_database(companies, path=DB_PATH, price_history=None, price_days=None):
    """Replace the whole database with the given companies.

    Each company is a dict with the COMPANY_COLUMNS keys, plus "not_applicable" (list),
    "missing_reasons" (dict) and "years" (the output of extract_company).
    price_history: {ticker: {day: close}} and price_days: set of days (from price_history.py), optional.
    """
    conn = connect(path)
    with conn:
        create_tables(conn)

        for ticker, closes in (price_history or {}).items():
            conn.executemany("INSERT INTO prices VALUES (?, ?, ?)",
                             [(ticker, day, close) for day, close in closes.items()])
        conn.executemany("INSERT INTO price_days VALUES (?)", [(day,) for day in sorted(price_days or [])])

        for order, (key, label, group, formula, unit, higher_is_better) in enumerate(METRIC_DEFINITIONS):
            conn.execute(
                "INSERT INTO metric_definitions VALUES (?, ?, ?, ?, ?, ?, ?)",
                (key, label, group, formula, unit, int(higher_is_better), order),
            )

        placeholders = ", ".join("?" for _ in COMPANY_COLUMNS)
        for company in companies:
            conn.execute(
                f"INSERT INTO companies ({', '.join(COMPANY_COLUMNS)}, not_applicable, missing_reasons) "
                f"VALUES ({placeholders}, ?, ?)",
                [company[column] for column in COMPANY_COLUMNS]
                + [",".join(company["not_applicable"]), json.dumps(company["missing_reasons"])],
            )
            for year, data in company["years"].items():
                for field in FIELDS:
                    cell = data["fields"][field]
                    conn.execute(
                        "INSERT INTO financials VALUES (?, ?, ?, ?, ?, ?)",
                        (company["ticker"], year, data["end_date"], field,
                         None if cell is None else cell["value"],
                         None if cell is None else cell["tag"]),
                    )
    conn.close()


# --- Reading (used by the API) ---

def company_row_to_dict(row):
    # A column the database does not have yet counts as empty. This keeps the API working right after
    # a code update, while the server still has yesterday's database (it is replaced within hours).
    present = set(row.keys())
    company = {column: row[column] if column in present else None for column in COMPANY_COLUMNS}
    company["not_applicable"] = row["not_applicable"].split(",") if row["not_applicable"] else []
    company["missing_reasons"] = json.loads(row["missing_reasons"]) if row["missing_reasons"] else {}
    return company


def load_companies(conn):
    rows = conn.execute("SELECT * FROM companies ORDER BY ticker").fetchall()
    return [company_row_to_dict(row) for row in rows]


def load_company_detail(conn, ticker):
    """Return one company with its yearly history and analysis, or None if the ticker is unknown.

    history is a list (oldest year first) of
    {"fiscal_year", "end_date", <each raw field>, "fcf", "tags": {field: tag},
     "ratios": {key: value}, "ratio_missing_reasons": {key: reason}}.
    analysis is {"pros": [{"id", "text"}], "cons": [...]}.
    """
    row = conn.execute("SELECT * FROM companies WHERE ticker = ?", (ticker.upper(),)).fetchone()
    if row is None:
        return None
    company = company_row_to_dict(row)

    # Rebuild the extract_company() shape, so the same metric functions can be reused per year.
    years = {}
    for f in conn.execute("SELECT * FROM financials WHERE ticker = ?", (company["ticker"],)):
        year = years.setdefault(f["fiscal_year"], {"end_date": f["end_date"], "fields": {}})
        year["fields"][f["field"]] = None if f["value"] is None else {"value": f["value"], "tag": f["tag"]}

    is_financial = company["sector"] == "Financials"
    ratios_by_year = yearly_ratios(years, is_financial)

    history = []
    for fiscal_year in sorted(years):
        cells = years[fiscal_year]["fields"]
        item = {"fiscal_year": fiscal_year, "end_date": years[fiscal_year]["end_date"]}
        for field in FIELDS:
            item[field] = None if cells.get(field) is None else cells[field]["value"]
        item["fcf"] = fcf(item["operating_cash_flow"], item["capex"])
        item["tags"] = {field: None if cells.get(field) is None else cells[field]["tag"] for field in FIELDS}
        item["ratios"] = ratios_by_year[fiscal_year]["ratios"]
        item["ratio_missing_reasons"] = ratios_by_year[fiscal_year]["missing_reasons"]
        history.append(item)
    company["history"] = history

    latest_equity = history[-1]["equity"] if history else None
    company["analysis"] = pros_and_cons(company, company["not_applicable"], latest_equity)
    company["price_history"] = load_price_history(conn, company["ticker"])
    return company


def load_price_history(conn, ticker):
    """[{"day": "2025-11-10", "close": 269.43}, ...], oldest first; [] if the database has none."""
    tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if "prices" not in tables:  # a database built before the price chart existed
        return []
    rows = conn.execute("SELECT day, close FROM prices WHERE ticker = ? ORDER BY day", (ticker,))
    return [{"day": day, "close": close} for day, close in rows]


def load_metric_definitions(conn):
    rows = conn.execute("SELECT * FROM metric_definitions ORDER BY sort_order").fetchall()
    return [
        {
            "key": row["key"],
            "label": row["label"],
            "group": row["group_name"],
            "formula": row["formula"],
            "unit": row["unit"],
            "higher_is_better": bool(row["higher_is_better"]),
        }
        for row in rows
    ]
