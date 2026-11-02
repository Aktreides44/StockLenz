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

# Where the SQLite database lives. Default: backend/data/stocklens.db
DB_PATH = Path(os.getenv("STOCKLENS_DB_PATH", str(BACKEND_DIR / "data" / "stocklens.db")))
