"""Coverage report: which companies miss which numbers, and why.

    python -m pipeline.coverage [output file, default data/coverage.md]

Reads the finished database and writes a Markdown report. The daily GitHub Actions run uploads it
next to stocklens.db (release "data-latest"). The reasons are the same texts the app shows when you
hover over a "—", e.g. "Diluted EPS is zero or negative (a loss year)".
"""
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

from config import BACKEND_DIR
from pipeline import db
from pipeline.refresh import load_universe

DEFAULT_OUTPUT = BACKEND_DIR / "data" / "coverage.md"


def general_reason(reason):
    """Group reasons that only differ by year: "... in the FY2025 10-K" -> "... in the latest 10-K"."""
    return re.sub(r"FY\d{4} 10-K", "latest 10-K", re.sub(r"for FY\d{4}", "for an earlier year", reason))


def build_report(companies, metrics, universe_tickers):
    """Return the report as Markdown text. companies: db.load_companies(); metrics: definitions."""
    total = len(companies)
    lines = ["# StockLens data coverage", ""]
    # The day most prices are from (the Polygon trading day; Yahoo backups carry today's date).
    price_days = Counter(c["price_fetched_at"][:10] for c in companies if c["price_fetched_at"])
    prices_as_of = price_days.most_common(1)[0][0] if price_days else "unknown"
    lines += [f"{total} companies in the database · prices as of {prices_as_of}.",
              "A missing value is shown as \"—\" in the app (never as 0), with the reason below.", ""]

    # 1. Overview per metric
    lines += ["## Per metric", "", "| Metric | Has a value | Not applicable | Missing |", "|---|---:|---:|---:|"]
    missing_by_metric = {}
    for metric in metrics:
        key = metric["key"]
        not_applicable = [c for c in companies if key in c["not_applicable"]]
        missing = [c for c in companies if c[key] is None and key not in c["not_applicable"]]
        missing_by_metric[key] = missing
        have = total - len(missing) - len(not_applicable)
        lines.append(f"| {metric['label']} | {have} ({have / total:.0%}) | {len(not_applicable)} | {len(missing)} |")
    lines.append("")

    # 2. Why values are missing
    lines += ["## Why values are missing", ""]
    for metric in metrics:
        missing = missing_by_metric[metric["key"]]
        if not missing:
            continue
        lines.append(f"**{metric['label']}** ({len(missing)} missing)")
        by_reason = defaultdict(list)
        for company in missing:
            reason = company["missing_reasons"].get(metric["key"], "Not available")
            by_reason[general_reason(reason)].append(company["ticker"])
        for reason, tickers in sorted(by_reason.items(), key=lambda item: -len(item[1])):
            lines.append(f"- {len(tickers)} × {reason}: {', '.join(sorted(tickers))}")
        lines.append("")

    # 3. Backups and companies that could not be included
    lines += ["## Data from the backup source (Yahoo Finance)", ""]
    yahoo_price = sorted(c["ticker"] for c in companies if (c["price_source"] or "").startswith("Yahoo"))
    yahoo_shares = sorted(c["ticker"] for c in companies if (c["shares_source"] or "").startswith("Yahoo"))
    lines.append(f"- Price (no Polygon close): {', '.join(yahoo_price) or 'none'}")
    lines.append(f"- Shares outstanding (no recent SEC share count): {', '.join(yahoo_shares) or 'none'}")
    lines.append("")

    in_database = {c["ticker"] for c in companies}
    skipped = sorted(set(universe_tickers) - in_database)
    lines += ["## In universe.csv but not in the database", "",
              f"{', '.join(skipped) or 'none'}",
              "", "(Usually a company without an annual 10-K at the SEC yet, e.g. a recent spin-off.)", ""]
    return "\n".join(lines)


def main():
    output = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUTPUT
    conn = db.connect(db.DB_PATH)
    report = build_report(
        db.load_companies(conn), db.load_metric_definitions(conn), [row["ticker"] for row in load_universe()],
    )
    conn.close()
    output.write_text(report, encoding="utf-8")
    print(f"Wrote the coverage report to {output}")


if __name__ == "__main__":
    main()
