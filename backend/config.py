"""All settings in one place, read from environment variables.

Locally the values come from backend/.env (loaded below). On a server such as Render there is no
.env file: the same names are set as environment variables in the dashboard instead.
A variable that is already set in the environment always wins over the .env file.
"""
import os
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent

load_dotenv(BACKEND_DIR / ".env")

# Identifies us to the SEC; required for every SEC request.
# Example: "StockLens student project you@example.com"
SEC_USER_AGENT = os.getenv("SEC_USER_AGENT")

# Polygon.io (Massive) API key for the daily closing prices. Empty = use Yahoo Finance for all prices.
POLYGON_API_KEY = os.getenv("POLYGON_API_KEY", "")

# Where the SQLite database lives. Default: backend/data/stocklens.db
DB_PATH = Path(os.getenv("STOCKLENS_DB_PATH", str(BACKEND_DIR / "data" / "stocklens.db")))

# Server only: where to download the database from (set on Render; the daily GitHub Actions run
# publishes it there). Empty = don't download, just use the file at DB_PATH (local development).
DB_URL = os.getenv("STOCKLENS_DB_URL", "")

# How old (in hours) the downloaded copy may get before the server fetches it again.
DB_MAX_AGE_HOURS = float(os.getenv("STOCKLENS_DB_MAX_AGE_HOURS", "6"))
