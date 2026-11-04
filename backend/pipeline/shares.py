"""Shares outstanding from the SEC (instead of Yahoo), needed for market cap = price × shares.

Every 10-K and 10-Q states on its cover page how many shares exist on a recent date
(dei:EntityCommonStockSharesOutstanding). The companyfacts file leaves out numbers that are split by
share class, so companies with several classes (Alphabet, Meta, Visa, ...) have no cover-page number
there. For them we try two other SEC share counts. Sources, in order (the first fresh one wins):

  1. cover page             dei:EntityCommonStockSharesOutstanding          shares on a recent date
  2. balance sheet          us-gaap:CommonStockSharesOutstanding            shares on the quarter's end date
  3. average in the period  us-gaap:WeightedAverageNumberOfSharesOutstandingBasic
                                                                            average during the latest quarter/year

"Fresh" means: dated at most MAX_AGE_DAYS before the company's latest fiscal year end, so a figure
from a 2015 filing is never used for 2026 numbers. If no SEC source qualifies, the pipeline falls
back to Yahoo Finance (see refresh.py).
"""
from datetime import date, timedelta

SHARE_SOURCES = [
    ("dei", "EntityCommonStockSharesOutstanding", "SEC cover page"),
    ("us-gaap", "CommonStockSharesOutstanding", "SEC balance sheet"),
    ("us-gaap", "WeightedAverageNumberOfSharesOutstandingBasic", "SEC average shares in the period"),
]

FILING_FORMS = {"10-K", "10-K/A", "10-Q", "10-Q/A"}

MAX_AGE_DAYS = 365


def _newest_entry(facts, namespace, tag):
    """The entry with the latest date (ties: the latest filing), or None."""
    entries = facts.get(namespace, {}).get(tag, {}).get("units", {}).get("shares", [])
    entries = [e for e in entries if e.get("form") in FILING_FORMS and e.get("val")]
    if not entries:
        return None
    return max(entries, key=lambda e: (e["end"], e.get("filed", "")))


def extract_shares(companyfacts, latest_fiscal_year_end):
    """Return {"value", "as_of", "source"} from the first fresh SEC source, or None.

    latest_fiscal_year_end: "YYYY-MM-DD" of the latest 10-K year, used to judge freshness.
    """
    facts = companyfacts.get("facts", {})
    oldest_allowed = (date.fromisoformat(latest_fiscal_year_end) - timedelta(days=MAX_AGE_DAYS)).isoformat()
    for namespace, tag, label in SHARE_SOURCES:
        entry = _newest_entry(facts, namespace, tag)
        if entry is not None and entry["end"] >= oldest_allowed:
            return {"value": float(entry["val"]), "as_of": entry["end"], "source": f"{label} ({entry['form']})"}
    return None
