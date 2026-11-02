"""Settings come from environment variables, and those win over backend/.env."""
import importlib

import config


def test_environment_variables_override_defaults(monkeypatch, tmp_path):
    monkeypatch.setenv("STOCKLENS_DB_PATH", str(tmp_path / "server.db"))
    monkeypatch.setenv("SEC_USER_AGENT", "StockLens test runner test@example.org")
    try:
        reloaded = importlib.reload(config)
        assert reloaded.DB_PATH == tmp_path / "server.db"
        assert reloaded.SEC_USER_AGENT == "StockLens test runner test@example.org"
    finally:
        monkeypatch.undo()
        importlib.reload(config)  # back to the normal settings for the other tests


def test_default_database_location():
    assert config.DB_PATH.name == "stocklens.db"
    assert config.DB_PATH.parent == config.BACKEND_DIR / "data"
