"""Keep the server's copy of the database up to date.

On Render the database is not part of the code. A GitHub Actions workflow builds it every weekday
and publishes it on GitHub (see .github/workflows/refresh-data.yml). When the STOCKLENS_DB_URL
setting is present, the server downloads that file at startup, and again whenever its copy is
older than STOCKLENS_DB_MAX_AGE_HOURS. Locally the setting is empty, so nothing is downloaded.
"""
import os
import shutil
import threading
import time
import urllib.request

import config

# If a download fails, wait this long before trying again (so not every request waits for GitHub).
RETRY_AFTER_SECONDS = 600

_lock = threading.Lock()  # only one download at a time, even if several requests arrive together
_last_attempt = 0.0


def download_database(url, path):
    """Download to a temporary file first, then swap it in, so a half-finished download is never used."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".download")
    with urllib.request.urlopen(url, timeout=60) as response, open(temporary, "wb") as file:
        shutil.copyfileobj(response, file)
    os.replace(temporary, path)


def is_stale(path, max_age_hours):
    """True if the file is missing or older than max_age_hours."""
    if not path.exists():
        return True
    age_seconds = time.time() - path.stat().st_mtime
    return age_seconds > max_age_hours * 3600


def refresh_if_needed():
    """Download a fresh database if a URL is configured and our copy is missing or old.

    Returns True if a new file was downloaded. Never raises: if GitHub can't be reached,
    the server keeps serving the copy it already has.
    """
    global _last_attempt
    if not config.DB_URL or not is_stale(config.DB_PATH, config.DB_MAX_AGE_HOURS):
        return False

    with _lock:
        # Another request may have downloaded it while we waited for the lock.
        if not is_stale(config.DB_PATH, config.DB_MAX_AGE_HOURS):
            return False
        if time.time() - _last_attempt < RETRY_AFTER_SECONDS:
            return False
        _last_attempt = time.time()
        try:
            download_database(config.DB_URL, config.DB_PATH)
            print(f"Downloaded a fresh database from {config.DB_URL}")
            return True
        except Exception as error:  # network problem, GitHub down, file not published yet, ...
            print(f"Could not download the database ({error}); keeping the current copy")
            return False
