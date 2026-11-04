"""Download only what changed: decide which saved SEC files are out of date.

The raw companyfacts files in data/raw/ are kept between runs (on GitHub by the Actions cache).
A company's file only needs a new download when the company filed a new report since we saved it.
The SEC publishes, for every business day, a list of all filings of that day ("daily index"):
    CIK|Company Name|Form Type|Date Filed|Filename
    320193|Apple Inc.|10-Q|20260731|edgar/data/320193/0000320193-26-000020.txt
We read those lists for the days since each file was downloaded, and delete the saved file of
every company that filed a 10-K or 10-Q since then. The normal caching in sec_client.py then
downloads exactly those again. As a safety net, files older than MAX_AGE_DAYS are always refreshed.

When each file was downloaded is kept in data/raw/downloaded.json (written by sec_client.py).
"""
from datetime import date, timedelta

import requests

from pipeline.sec_client import RAW_DIR, download_text, load_manifest, save_manifest

DAILY_INDEX_URL = "https://www.sec.gov/Archives/edgar/daily-index/{year}/QTR{quarter}/master.{day}.idx"
DAILY_INDEX_DIR = RAW_DIR / "daily-index"

# Filings that change the numbers we use (annual and quarterly reports, incl. corrections).
REPORT_FORMS = {"10-K", "10-K/A", "10-Q", "10-Q/A", "10-KT", "10-KT/A"}

MAX_AGE_DAYS = 30


def parse_daily_index(text):
    """The CIKs that filed a 10-K or 10-Q in one daily index file."""
    ciks = set()
    for line in text.splitlines():
        parts = line.split("|")
        if len(parts) == 5 and parts[0].isdigit() and parts[2] in REPORT_FORMS:
            ciks.add(int(parts[0]))
    return ciks


def load_daily_index(day):
    """The text of one day's index, or None for days without one (weekends, holidays, not out yet).

    Index files of past days never change, so they are saved in data/raw/daily-index/.
    """
    if day.weekday() >= 5:  # Saturday, Sunday: no filings, no request
        return None
    saved = DAILY_INDEX_DIR / f"master.{day:%Y%m%d}.idx"
    if saved.exists():
        return saved.read_text(encoding="latin-1")
    url = DAILY_INDEX_URL.format(year=day.year, quarter=(day.month - 1) // 3 + 1, day=f"{day:%Y%m%d}")
    try:
        text = download_text(url)
    except requests.HTTPError:  # 403/404: a holiday, or the list for this day is not published yet
        return None
    saved.parent.mkdir(parents=True, exist_ok=True)
    saved.write_text(text, encoding="latin-1")
    return text


def outdated_files(manifest, today, filers_on, max_age_days=MAX_AGE_DAYS):
    """Which saved companyfacts files must be downloaded again.

    manifest: {file name: download date}; filers_on(day) -> set of CIKs that filed a report that day.
    A file is outdated if it is older than max_age_days, or if its company filed a report on or
    after the day the file was downloaded (on the same day the report may have come after us).
    """
    outdated = []
    for file_name, downloaded in manifest.items():
        if not file_name.startswith("CIK"):
            continue
        downloaded_on = date.fromisoformat(downloaded)
        if (today - downloaded_on).days > max_age_days:
            outdated.append(file_name)
            continue
        cik = int(file_name[3:13])
        day = downloaded_on
        while day <= today:
            if cik in filers_on(day):
                outdated.append(file_name)
                break
            day += timedelta(days=1)
    return sorted(outdated)


def remove_outdated_files(today=None):
    """Delete the saved files that need a new download, and print a short summary.

    Also deletes saved files without a download date (e.g. from before this file existed) and
    the SEC ticker list (always fetched fresh), and old daily index files that are no longer needed.
    """
    today = today or date.today()
    manifest = load_manifest()

    filers_cache = {}

    def filers_on(day):
        if day not in filers_cache:
            text = load_daily_index(day)
            filers_cache[day] = parse_daily_index(text) if text else set()
        return filers_cache[day]

    outdated = outdated_files(manifest, today, filers_on)
    undated = [path.name for path in RAW_DIR.glob("CIK*.json") if path.name not in manifest]
    for file_name in outdated + undated + ["company_tickers.json"]:
        (RAW_DIR / file_name).unlink(missing_ok=True)
        manifest.pop(file_name, None)
    save_manifest(manifest)

    oldest_needed = today - timedelta(days=MAX_AGE_DAYS + 1)
    for path in DAILY_INDEX_DIR.glob("master.*.idx"):
        if path.name < f"master.{oldest_needed:%Y%m%d}.idx":
            path.unlink()

    kept = sum(1 for name in manifest if name.startswith("CIK"))
    print(f"SEC files: {kept} saved files still up to date, {len(outdated)} to download again "
          f"(new filings or older than {MAX_AGE_DAYS} days), {len(undated)} without a download date")
