"""StockLens API: read-only access to the SQLite database built by `python -m pipeline.refresh`.

It never calls the SEC or Yahoo at request time; it only reads the database.

Start it from the backend folder:
    python -m uvicorn api.main:app --reload
Then open http://127.0.0.1:8000/docs
"""
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from pipeline import db

app = FastAPI(title="StockLens API", description="Fundamental stock screener data (SEC 10-K + latest price)")

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
    if not db.DB_PATH.exists():
        raise HTTPException(status_code=503, detail="Database not found. Run `python -m pipeline.refresh` first.")
    conn = db.connect()
    try:
        yield conn
    finally:
        conn.close()


@app.get("/")
def index():
    return {
        "name": "StockLens API",
        "endpoints": ["/companies", "/companies/{ticker}", "/metrics", "/docs"],
    }


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
