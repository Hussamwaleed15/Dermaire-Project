import json
import pytest
from unittest.mock import Mock
from app.core import database
from app.services.azure_blob import azure_blob_service
from app.core.config import Settings


def test_postgres_url_uses_installed_driver_and_preserves_tls():
    value = "postgresql://user:encoded%40password@db.invalid/dermaire?sslmode=require"
    config = Settings(_env_file=None, DATABASE_URL=value, ENVIRONMENT="test")
    assert config.DATABASE_URL == value.replace(
        "postgresql://", "postgresql+psycopg://", 1
    )


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


def test_managed_readiness_requires_independent_journal(monkeypatch):
    from app.main import readiness
    from app.core.config import settings
    from app.services.deletion_journal import deletion_journal

    db = Mock()
    db.execute.return_value.scalars.return_value.all.return_value = ["20261008_01"]
    monkeypatch.setattr(settings, "ENVIRONMENT", "staging")
    monkeypatch.setattr(azure_blob_service, "health", lambda: {"state": "available"})
    monkeypatch.setattr(deletion_journal, "health", lambda: "unavailable")
    assert readiness(db).status_code == 503
    monkeypatch.setattr(deletion_journal, "health", lambda: "available")
    assert readiness(db).status_code == 200


@pytest.mark.parametrize(
    "revision", [["20261006_01"], [], ["unknown"], ["20261008_01", "other"]]
)
def test_managed_readiness_rejects_unreconciled_revision(monkeypatch, revision):
    from app.main import readiness
    from app.core.config import settings
    from app.services.deletion_journal import deletion_journal

    db = Mock()
    db.execute.return_value.scalars.return_value.all.return_value = revision
    monkeypatch.setattr(settings, "ENVIRONMENT", "production")
    monkeypatch.setattr(azure_blob_service, "health", lambda: {"state": "available"})
    monkeypatch.setattr(deletion_journal, "health", lambda: "available")
    assert readiness(db).status_code == 503


def test_database_timeout_is_retryable_and_private(client, monkeypatch):
    from sqlalchemy.exc import OperationalError
    from app.core.database import get_db
    from app.main import app

    def unavailable():
        raise OperationalError(
            "SELECT private",
            {"email": "private@example.invalid"},
            RuntimeError("sensitive SQL driver text"),
        )
        yield

    previous = app.dependency_overrides.get(get_db)
    app.dependency_overrides[get_db] = unavailable
    try:
        response = client.get("/health/ready")
        assert response.status_code == 503
        assert response.json()["errorCode"] == "DATABASE_UNAVAILABLE"
        assert (
            "sensitive" not in response.text
            and "private@example.invalid" not in response.text
        )
    finally:
        if previous is None:
            app.dependency_overrides.pop(get_db, None)
        else:
            app.dependency_overrides[get_db] = previous


def test_request_telemetry_excludes_query_and_personal_path(client, caplog):
    response = client.get("/not-a-route/private@example.com?token=secret")
    assert response.headers["x-request-id"]
    events = [
        json.loads(r.message) for r in caplog.records if r.name == "dermaire.operations"
    ]
    assert events[-1]["route"] == "unmatched"
    assert "private@example.com" not in json.dumps(events)
    assert "secret" not in json.dumps(events)
