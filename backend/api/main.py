"""StockLens API: read-only access to the SQLite database built by `python -m pipeline.refresh`.

It never calls the SEC or Yahoo at request time; it only reads the database. On the server the
database file is downloaded from GitHub (see api/database_file.py).

Start it from the backend folder:
    python -m uvicorn api.main:app --reload
Then open http://127.0.0.1:8000/docs
"""
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from api.database_file import refresh_if_needed
from pipeline import db


@asynccontextmanager
async def lifespan(app):
    # Runs once when the server starts: on Render, fetch the newest database before the first request.
    refresh_if_needed()
    yield


app = FastAPI(
    title="StockLens API",
    description="Fundamental stock screener data (SEC 10-K + latest price)",
    lifespan=lifespan,
)

# Allow the app (or a browser page) on any origin to read the data. The API is read-only.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


def get_db():
    """Open a database connection for one request and close it afterwards.

    Tests replace this function (app.dependency_overrides) to use a small test database.
    """
    refresh_if_needed()  # does nothing locally, or when the server's copy is still fresh
    if not db.DB_PATH.exists():
        raise HTTPException(
            status_code=503,
            detail="Database not found. Locally: run `python -m pipeline.refresh`. "
            "On the server: the daily data workflow has not published a database yet.",
        )
    conn = db.connect(db.DB_PATH)
    try:
        yield conn
    finally:
        conn.close()


@app.get("/")
def index():
    return {
        "name": "StockLens API",
        "endpoints": ["/companies", "/companies/{ticker}", "/metrics", "/health", "/docs"],
    }


@app.get("/health")
def health():
    """Is the server up, and does it have data? The hosting service calls this to check on us.

    It always answers (status "ok"), even without a database, so "server down" and
    "data missing" can be told apart.
    """
    refresh_if_needed()
    if not db.DB_PATH.exists():
        return {"status": "ok", "database": "missing", "companies": 0, "prices_as_of": None}
    conn = db.connect(db.DB_PATH)
    try:
        companies, prices_as_of = conn.execute(
            "SELECT COUNT(*), MAX(price_fetched_at) FROM companies"
        ).fetchone()
    finally:
        conn.close()
    return {"status": "ok", "database": "ok", "companies": companies, "prices_as_of": prices_as_of}


@app.get("/companies")
def list_companies(conn=Depends(get_db)):
    """All companies with every screener metric (latest fiscal year) and the fiscal year end date."""
    return db.load_companies(conn)


@app.get("/companies/{ticker}")
def company_detail(ticker: str, conn=Depends(get_db)):
    """One company with its metrics and yearly history (raw fields, FCF and the XBRL tag used)."""
    company = db.load_company_detail(conn, ticker)
    if company is None:
        raise HTTPException(status_code=404, detail=f"Unknown ticker: {ticker.upper()}")
    return company


@app.get("/metrics")
def list_metrics(conn=Depends(get_db)):
    """Metric definitions: key, label, group, formula, unit, higher_is_better."""
    return db.load_metric_definitions(conn)
