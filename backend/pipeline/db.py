"""SQLite storage: the pipeline writes here, the API (and the snapshot export) read from here.

Tables:
- companies: one row per company, with price info and every screener metric as a column
- financials: the raw SEC values, one row per (company, fiscal year, field), incl. the XBRL tag used
- metric_definitions: label, formula and unit for each metric, shown in the app
"""
import json
import sqlite3

from pipeline.extract import FIELDS
from pipeline.metrics import METRIC_DEFINITIONS, METRIC_KEYS, fcf
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
    """Return one company with its yearly history, or None if the ticker is unknown.

    history is a list (oldest year first) of
    {"fiscal_year", "end_date", <each raw field>, "fcf", "tags": {field: tag}}.
    """
    row = conn.execute("SELECT * FROM companies WHERE ticker = ?", (ticker.upper(),)).fetchone()
    if row is None:
        return None
    company = company_row_to_dict(row)

    history_by_year = {}
    for f in conn.execute(
        "SELECT * FROM financials WHERE ticker = ? ORDER BY fiscal_year", (company["ticker"],)
    ):
        year = history_by_year.setdefault(
            f["fiscal_year"], {"fiscal_year": f["fiscal_year"], "end_date": f["end_date"], "tags": {}}
        )
        year[f["field"]] = f["value"]
        year["tags"][f["field"]] = f["tag"]

    history = list(history_by_year.values())
    for year in history:
        year["fcf"] = fcf(year.get("operating_cash_flow"), year.get("capex"))
    company["history"] = history
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
