"""Tests for "download only what changed" (pipeline/sec_updates.py). Nothing here goes online."""
from datetime import date

import pytest

from pipeline import sec_client, sec_updates
from pipeline.sec_updates import load_daily_index, outdated_files, parse_daily_index

DAILY_INDEX = """Description:           Daily Index of EDGAR Dissemination Feed by Company Name
Last Data Received:    November 3, 2026

CIK|Company Name|Form Type|Date Filed|File Name
--------------------------------------------------------------------------------
320193|Apple Inc.|10-Q|20261103|edgar/data/320193/0000320193-26-000020.txt
19617|JPMORGAN CHASE & CO|8-K|20261103|edgar/data/19617/0000019617-26-000001.txt
34088|EXXON MOBIL CORP|10-K/A|20261103|edgar/data/34088/0000034088-26-000070.txt
"""

TUESDAY = date(2026, 11, 3)
FRIDAY = date(2026, 10, 30)
APPLE, JPM, XOM = "CIK0000320193.json", "CIK0000019617.json", "CIK0000034088.json"


def test_parse_daily_index_keeps_only_reports():
    # Apple's 10-Q and Exxon's corrected 10-K count; JPMorgan's 8-K (a news filing) does not.
    assert parse_daily_index(DAILY_INDEX) == {320193, 34088}


def test_a_company_with_a_new_report_is_downloaded_again():
    filers = {TUESDAY: {320193, 34088}}
    manifest = {APPLE: "2026-10-30", JPM: "2026-10-30", XOM: "2026-11-04", "company_tickers.json": "2026-10-30"}
    # Apple filed on Tuesday, after its file was saved on Friday -> outdated.
    # JPM filed no report -> still up to date. XOM's file was saved after its filing -> up to date.
    assert outdated_files(manifest, date(2026, 11, 4), lambda day: filers.get(day, set())) == [APPLE]


def test_a_filing_on_the_download_day_counts():
    # Saved on Tuesday morning, filed on Tuesday afternoon: we can't tell, so download again.
    filers = {TUESDAY: {320193}}
    assert outdated_files({APPLE: "2026-11-03"}, date(2026, 11, 4), lambda day: filers.get(day, set())) == [APPLE]


def test_files_older_than_the_maximum_age_are_always_refreshed():
    assert outdated_files({APPLE: "2026-09-01"}, date(2026, 11, 4), lambda day: set()) == [APPLE]


def test_no_request_on_weekends(monkeypatch):
    def must_not_be_called(url):
        raise AssertionError("no request on a weekend")

    monkeypatch.setattr(sec_updates, "download_text", must_not_be_called)
    assert load_daily_index(date(2026, 11, 1)) is None  # a Sunday


@pytest.fixture
def raw(tmp_path, monkeypatch):
    """A temporary data/raw folder."""
    monkeypatch.setattr(sec_updates, "RAW_DIR", tmp_path)
    monkeypatch.setattr(sec_updates, "DAILY_INDEX_DIR", tmp_path / "daily-index")
    monkeypatch.setattr(sec_client, "MANIFEST", tmp_path / "downloaded.json")
    return tmp_path


def test_remove_outdated_files_deletes_exactly_the_right_files(raw, monkeypatch):
    for name in [APPLE, JPM, "CIK0000000001.json", "company_tickers.json"]:
        (raw / name).write_text("{}")
    sec_client.save_manifest({APPLE: "2026-10-30", JPM: "2026-10-30", "company_tickers.json": "2026-10-30"})
    monkeypatch.setattr(sec_updates, "load_daily_index", lambda day: DAILY_INDEX if day == TUESDAY else None)

    sec_updates.remove_outdated_files(today=date(2026, 11, 4))

    assert not (raw / APPLE).exists()  # new 10-Q -> download again
    assert (raw / JPM).exists()  # only an 8-K -> keep
    assert not (raw / "CIK0000000001.json").exists()  # no download date -> download again
    assert not (raw / "company_tickers.json").exists()  # the ticker list is always fetched fresh
    assert sec_client.load_manifest() == {JPM: "2026-10-30"}


def test_downloads_are_recorded(raw, monkeypatch):
    monkeypatch.setattr(sec_client, "download_json", lambda url: {"facts": {}})
    sec_client.get_cached_json("https://example.invalid/x", raw / APPLE)
    assert sec_client.load_manifest() == {APPLE: date.today().isoformat()}
