"""Tests for downloading the database on the server. A local file stands in for GitHub (file:// URL)."""
import os
import time

import pytest

import config
from api import database_file


@pytest.fixture
def published(tmp_path):
    """A 'published' database file, like the one GitHub Actions uploads."""
    source = tmp_path / "published.db"
    source.write_bytes(b"fresh database")
    return source


@pytest.fixture
def server(tmp_path, monkeypatch, published):
    """Point the settings at a temporary server copy and the 'published' file."""
    server_copy = tmp_path / "server" / "stocklens.db"
    monkeypatch.setattr(config, "DB_PATH", server_copy)
    monkeypatch.setattr(config, "DB_URL", published.as_uri())
    monkeypatch.setattr(config, "DB_MAX_AGE_HOURS", 6)
    monkeypatch.setattr(database_file, "_last_attempt", 0.0)
    return server_copy


def make_old(path, hours):
    old = time.time() - hours * 3600
    os.utime(path, (old, old))


def test_downloads_when_missing(server):
    assert database_file.refresh_if_needed() is True
    assert server.read_bytes() == b"fresh database"


def test_does_not_download_when_fresh(server):
    server.parent.mkdir(parents=True)
    server.write_bytes(b"current copy")
    assert database_file.refresh_if_needed() is False
    assert server.read_bytes() == b"current copy"


def test_downloads_again_when_too_old(server):
    server.parent.mkdir(parents=True)
    server.write_bytes(b"yesterday's copy")
    make_old(server, hours=7)
    assert database_file.refresh_if_needed() is True
    assert server.read_bytes() == b"fresh database"


def test_no_url_means_no_download(server, monkeypatch):
    monkeypatch.setattr(config, "DB_URL", "")
    assert database_file.refresh_if_needed() is False
    assert not server.exists()


def test_failed_download_keeps_the_old_copy_and_waits_before_retrying(server, monkeypatch, tmp_path):
    server.parent.mkdir(parents=True)
    server.write_bytes(b"yesterday's copy")
    make_old(server, hours=7)
    monkeypatch.setattr(config, "DB_URL", (tmp_path / "not-published-yet.db").as_uri())

    assert database_file.refresh_if_needed() is False
    assert server.read_bytes() == b"yesterday's copy"
    assert not server.with_suffix(".download").exists()  # no half-finished file left behind

    # Even once the file exists, we don't hammer GitHub: the next try waits RETRY_AFTER_SECONDS.
    (tmp_path / "not-published-yet.db").write_bytes(b"fresh database")
    assert database_file.refresh_if_needed() is False
    monkeypatch.setattr(database_file, "_last_attempt", 0.0)
    assert database_file.refresh_if_needed() is True


def test_is_stale():
    assert database_file.is_stale(config.BACKEND_DIR / "no-such-file.db", 6) is True
