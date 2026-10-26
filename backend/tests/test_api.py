"""API tests with FastAPI's TestClient, using a small test database (not the real one)."""
import pytest
from fastapi.testclient import TestClient

from api.main import app, get_db
from pipeline import db
from pipeline.metrics import compute_all
from tests.test_calculations import make_years


def make_company(ticker, sector, years):
    is_financial = sector == "Financials"
    latest = max(years)
    company = {
        "ticker": ticker, "name": f"{ticker} Inc.", "sector": sector, "cik": 1,
        "price": 100.0, "shares_outstanding": 10, "price_fetched_at": "2026-10-26T12:00:00",
        "latest_fiscal_year": latest, "latest_fiscal_year_end": years[latest]["end_date"],
        "not_applicable": ["current_ratio", "debt_to_equity"] if is_financial else [],
        "years": years,
    }
    company.update(compute_all(years, 100.0, 10, is_financial))
    return company


@pytest.fixture
def client(tmp_path):
    test_db = tmp_path / "test.db"
    db.write_database([
        make_company("AAA", "Information Technology", make_years({
            2024: {"revenue": 100, "net_income": 10, "operating_cash_flow": 20, "capex": 5,
                   "current_assets": 30, "current_liabilities": 20},
            2025: {"revenue": 120, "net_income": 15, "eps_diluted": 4.0, "operating_cash_flow": 25,
                   "capex": 5, "current_assets": 30, "current_liabilities": 20},
        })),
        make_company("BNK", "Financials", make_years({
            2025: {"revenue": 50, "net_income": 5, "current_assets": 30, "current_liabilities": 20},
        })),
    ], path=test_db)

    def get_test_db():
        conn = db.connect(test_db)
        try:
            yield conn
        finally:
            conn.close()

    app.dependency_overrides[get_db] = get_test_db
    yield TestClient(app)
    app.dependency_overrides.clear()


def test_companies_list(client):
    response = client.get("/companies")
    assert response.status_code == 200
    companies = {c["ticker"]: c for c in response.json()}
    assert set(companies) == {"AAA", "BNK"}

    aaa = companies["AAA"]
    assert aaa["latest_fiscal_year"] == 2025
    assert aaa["latest_fiscal_year_end"] == "2025-12-31"
    assert aaa["revenue_growth"] == pytest.approx(20.0)
    assert aaa["pe"] == pytest.approx(25.0)
    assert aaa["operating_margin"] is None  # missing stays null in JSON, never 0


def test_financials_are_flagged_not_applicable(client):
    bank = next(c for c in client.get("/companies").json() if c["ticker"] == "BNK")
    assert bank["not_applicable"] == ["current_ratio", "debt_to_equity"]
    assert bank["current_ratio"] is None


def test_company_detail_has_history(client):
    response = client.get("/companies/aaa")  # lower case works too
    assert response.status_code == 200
    detail = response.json()
    assert detail["ticker"] == "AAA"
    assert [h["fiscal_year"] for h in detail["history"]] == [2024, 2025]
    assert detail["history"][1]["revenue"] == 120
    assert detail["history"][1]["fcf"] == 20
    assert detail["history"][1]["tags"]["revenue"] == "TestTag"


def test_unknown_ticker_is_404(client):
    assert client.get("/companies/NOPE").status_code == 404


def test_metrics_definitions(client):
    metrics = {m["key"]: m for m in client.get("/metrics").json()}
    assert len(metrics) == 16
    assert metrics["roe"]["unit"] == "%"
    assert metrics["pe"]["higher_is_better"] is False
    for key in ("pe", "pb", "ps"):
        assert "(FY)" in metrics[key]["label"]
        assert "latest fiscal year" in metrics[key]["formula"]


def test_cors_header(client):
    response = client.get("/companies", headers={"Origin": "http://localhost:1234"})
    assert response.headers["access-control-allow-origin"] == "*"
