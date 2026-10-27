"""SQLite storage: the pipeline writes here, the API (and the snapshot export) read from here.

Tables:
- companies: one row per company, with price info and every screener metric as a column
- financials: the raw SEC values, one row per (company, fiscal year, field), incl. the XBRL tag used
- metric_definitions: label, formula and unit for each metric, shown in the app
"""
import json
import sqlite3

from pipeline.extract import FIELDS
from pipeline.analysis import pros_and_cons
from pipeline.metrics import METRIC_DEFINITIONS, METRIC_KEYS, fcf, yearly_ratios
from pipeline.sec_client import BACKEND_DIR

DB_PATH = BACKEND_DIR / "data" / "stocklens.db"

COMPANY_COLUMNS = [
    "ticker", "name", "sector", "cik", "price", "shares_outstanding", "price_fetched_at",
    "latest_fiscal_year", "latest_fiscal_year_end",
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

CREATE TABLE companies (
    ticker TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    sector TEXT NOT NULL,
    cik INTEGER NOT NULL,
    price REAL,
    shares_outstanding REAL,
    price_fetched_at TEXT,
    latest_fiscal_year INTEGER,
    latest_fiscal_year_end TEXT,
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


def write_database(companies, path=DB_PATH):
    """Replace the whole database with the given companies.

    Each company is a dict with the COMPANY_COLUMNS keys, plus "not_applicable" (list),
    "missing_reasons" (dict) and "years" (the output of extract_company).
    """
    conn = connect(path)
    with conn:
        create_tables(conn)

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


# --- Reading (used by the API and the snapshot export) ---

def company_row_to_dict(row):
    company = {column: row[column] for column in COMPANY_COLUMNS}
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
    return company


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
