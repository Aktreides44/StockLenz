"""Sanity check of a freshly built database, run by GitHub Actions before publishing it.

    python -m pipeline.check_database

Exits with an error (so the workflow stops and yesterday's database stays online) if
too few companies made it into the database, or too few of them have a price
(e.g. when Yahoo blocks the request).
"""
import sys

from pipeline import db
from pipeline.refresh import load_universe

# At least this share of the companies in universe.csv must be present, and have a price.
MIN_SHARE = 0.9


def check(conn, expected_companies):
    """Return a list of problems (empty = looks good)."""
    total, with_price = conn.execute("SELECT COUNT(*), COUNT(price) FROM companies").fetchone()
    problems = []
    if total < MIN_SHARE * expected_companies:
        problems.append(f"only {total} of {expected_companies} companies in the database")
    if with_price < MIN_SHARE * total:
        problems.append(f"only {with_price} of {total} companies have a price")
    return problems


def main():
    if not db.DB_PATH.exists():
        print(f"FAILED: no database at {db.DB_PATH}")
        sys.exit(1)
    conn = db.connect(db.DB_PATH)
    problems = check(conn, expected_companies=len(load_universe()))
    total, with_price = conn.execute("SELECT COUNT(*), COUNT(price) FROM companies").fetchone()
    conn.close()

    if problems:
        print("FAILED: " + "; ".join(problems))
        sys.exit(1)
    print(f"OK: {total} companies, {with_price} with a price")


if __name__ == "__main__":
    main()
