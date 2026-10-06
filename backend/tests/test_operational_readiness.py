import json
from unittest.mock import Mock
from app.core import database
from app.services.azure_blob import azure_blob_service
from app.core.config import Settings


def test_postgres_url_uses_installed_driver_and_preserves_tls():
    value = "postgresql://user:encoded%40password@db.invalid/dermaire?sslmode=require"
    config = Settings(_env_file=None, DATABASE_URL=value, ENVIRONMENT="test")
    assert config.DATABASE_URL == value.replace("postgresql://", "postgresql+psycopg://", 1)


def test_managed_startup_never_creates_schema(monkeypatch):
    create = Mock()
    monkeypatch.setattr(database.Base.metadata, "create_all", create)
    monkeypatch.setattr(database.settings, "ENVIRONMENT", "production")
    database.init_db()
    create.assert_not_called()


def test_readiness_storage_failure_and_liveness(client, monkeypatch):
    monkeypatch.setattr(azure_blob_service, "health", lambda: {"state": "degraded"})
    assert client.get("/health/live").status_code == 200
    assert client.get("/health/ready").status_code == 503


def test_readiness_db_failure(monkeypatch):
    from app.main import readiness
    db = Mock()
    db.execute.side_effect = RuntimeError("sensitive database error")
    monkeypatch.setattr(azure_blob_service, "health", lambda: {"state": "available"})
    response = readiness(db)
    assert response.status_code == 503
    assert b"sensitive" not in response.body


def test_request_telemetry_excludes_query_and_personal_path(client, caplog):
    response = client.get("/not-a-route/private@example.com?token=secret")
    assert response.headers["x-request-id"]
    events = [json.loads(r.message) for r in caplog.records if r.name == "dermaire.operations"]
    assert events[-1]["route"] == "unmatched"
    assert "private@example.com" not in json.dumps(events)
    assert "secret" not in json.dumps(events)
