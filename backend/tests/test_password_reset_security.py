from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import hashlib

import pytest
from sqlalchemy.orm import sessionmaker

from app.api.v1.auth import ResetPasswordRequest, reset_password
from app.core.config import Settings, settings
from app.core.database import Base
from app.core.exceptions import DermaireException
from app.core.security import get_password_hash, verify_password
from app.models import AuditLog, User
from app.services.password_reset import claim_request_slot, token_digest
from tests.test_postgres_gate import pg_engine


GENERIC = {
    "message": "If an account exists for this email, a password reset code has been sent."
}


def add_user(db, identifier="reset-user"):
    user = User(
        id=identifier,
        email=identifier + "@example.com",
        full_name="Synthetic",
        hashed_password=get_password_hash("OldPassword123!"),
        role="patient",
    )
    db.add(user)
    db.commit()
    return user


def test_token_exposure_is_rejected_in_managed_environments():
    for environment in ("production", "staging"):
        with pytest.raises(ValueError, match="EXPOSE_PASSWORD_RESET_TOKEN"):
            Settings(
                _env_file=None,
                ENVIRONMENT=environment,
                SECRET_KEY="a" * 64,
                EXPOSE_PASSWORD_RESET_TOKEN=True,
            )


def test_request_is_generic_when_account_missing_or_delivery_fails(
    client, db_session, monkeypatch
):
    user = add_user(db_session, "delivery-failure")
    monkeypatch.setattr(settings, "EXPOSE_PASSWORD_RESET_TOKEN", False)

    def fail_without_logging_token(_recipient, _token):
        raise RuntimeError("synthetic provider failure")

    monkeypatch.setattr(
        "app.api.v1.auth.send_password_reset_email", fail_without_logging_token
    )
    existing = client.post("/api/v1/auth/forgot-password", json={"email": user.email})
    missing = client.post(
        "/api/v1/auth/forgot-password", json={"email": "missing@example.com"}
    )
    assert existing.status_code == missing.status_code == 200
    assert existing.json() == missing.json() == GENERIC
    assert "reset_token" not in existing.text


def test_repeat_requests_are_limited_and_only_latest_code_is_usable(
    client, db_session, monkeypatch
):
    user = add_user(db_session, "repeat-reset")
    monkeypatch.setattr(settings, "EXPOSE_PASSWORD_RESET_TOKEN", True)
    tokens = []
    for _ in range(settings.PASSWORD_RESET_RATE_LIMIT):
        response = client.post("/api/v1/auth/forgot-password", json={"email": user.email})
        assert response.status_code == 200
        tokens.append(response.json()["reset_token"])
    limited = client.post("/api/v1/auth/forgot-password", json={"email": user.email})
    assert limited.json() == GENERIC

    stored = db_session.get(User, user.id)
    db_session.refresh(stored)
    assert stored.reset_token_hash.startswith("hmac-sha256$")
    assert tokens[-1] not in stored.reset_token_hash
    assert hashlib.sha256(tokens[-1].encode()).hexdigest() != stored.reset_token_hash

    invalid = client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": tokens[0], "new_password": "NewPassword123!",
    })
    assert invalid.status_code == 400
    success = client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": tokens[-1], "new_password": "NewPassword123!",
    })
    assert success.status_code == 200
    assert verify_password("NewPassword123!", db_session.get(User, user.id).hashed_password)
    reused = client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": tokens[-1], "new_password": "AnotherPassword123!",
    })
    assert reused.status_code == 400


def test_expired_code_is_rejected(client, db_session):
    user = add_user(db_session, "expired-reset")
    user.reset_token_hash = token_digest("12345678")
    user.reset_token_expires = datetime.now(timezone.utc) - timedelta(seconds=1)
    db_session.commit()
    response = client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": "12345678", "new_password": "NewPassword123!",
    })
    assert response.status_code == 400


def test_five_wrong_guesses_invalidate_code_and_payload_shape_is_bounded(
    client, db_session
):
    user = add_user(db_session, "guess-reset")
    user.reset_token_hash = token_digest("12345678")
    user.reset_token_expires = datetime.now(timezone.utc) + timedelta(minutes=5)
    db_session.commit()
    for attempt in range(5):
        response = client.post("/api/v1/auth/reset-password", json={
            "email": user.email,
            "token": "87654321",
            "new_password": "NewPassword123!",
        })
        assert response.status_code == (429 if attempt == 4 else 400)
    valid_after_lock = client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": "12345678", "new_password": "NewPassword123!",
    })
    assert valid_after_lock.status_code == 400
    assert client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": "short", "new_password": "NewPassword123!",
    }).status_code == 422
    assert client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": "12345678", "new_password": "short",
    }).status_code == 422


def test_pg_concurrent_code_use_succeeds_once(pg_engine):
    Base.metadata.create_all(pg_engine)
    factory = sessionmaker(bind=pg_engine, expire_on_commit=False)
    with factory() as db:
        user = add_user(db, "pg-reset")
        user.reset_token_hash = token_digest("12345678")
        user.reset_token_expires = datetime.now(timezone.utc) + timedelta(minutes=5)
        db.commit()

    def submit(_):
        with factory() as db:
            try:
                reset_password(ResetPasswordRequest(
                    email="pg-reset@example.com",
                    token="12345678",
                    new_password="NewPassword123!",
                ), db)
                return "success"
            except DermaireException:
                return "rejected"

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(submit, range(2)))
    assert sorted(results) == ["rejected", "success"]


def test_pg_rate_limit_is_shared_and_atomic(pg_engine, monkeypatch):
    Base.metadata.create_all(pg_engine)
    factory = sessionmaker(bind=pg_engine)
    monkeypatch.setattr(settings, "PASSWORD_RESET_RATE_LIMIT", 3)

    def claim(_):
        with factory() as db:
            allowed = claim_request_slot(db, "shared@example.com")
            db.commit()
            return allowed

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(claim, range(8)))
    assert results.count(True) == 3
    with factory() as db:
        assert db.query(AuditLog).filter_by(action="PASSWORD_RESET_RATE_SLOT").count() == 3
