import hashlib
from datetime import datetime, timedelta, timezone

import jwt
import pytest

from app.core.config import settings
from app.core.security import create_access_token
from app.models import User
from tests.test_account_deletion import deletion_context


def headers(token):
    return {"Authorization": "Bearer " + token}


def test_valid_and_logged_out_session(deletion_context):
    client, db, auth = deletion_context
    assert client.get("/api/v1/users/me", headers=auth).status_code == 200
    other = create_access_token("delete-patient", "patient", hashed_password="unused")
    assert client.post("/api/v1/auth/logout", headers=auth).status_code == 204
    assert client.get("/api/v1/users/me", headers=auth).status_code == 401
    assert client.delete("/api/v1/users/me", headers=auth).status_code == 401
    assert client.get("/api/v1/users/me", headers=headers(other)).status_code == 200


@pytest.mark.parametrize("kind", ["expired", "invalid", "bad-signature", "missing-exp", "bad-exp", "bad-credential", "legacy"])
def test_reject_bad_sessions(deletion_context, kind):
    client, db, auth = deletion_context
    token = auth["Authorization"][7:]
    if kind == "expired":
        token = create_access_token("delete-patient", "patient", expires_delta=timedelta(seconds=-1), hashed_password="unused")
    elif kind == "bad-signature":
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        token = jwt.encode(payload, "test-only-untrusted-key-that-is-long-enough", algorithm=settings.ALGORITHM)
    elif kind == "invalid":
        token = "invalid"
    else:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        if kind == "bad-exp":
            payload["exp"] = {}
        elif kind == "bad-credential":
            payload["credential"] = "invalid"
        else:
            payload.pop("exp" if kind == "missing-exp" else "credential")
        token = jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    assert client.get("/api/v1/users/me", headers=headers(token)).status_code == 401
    assert client.delete("/api/v1/users/me", headers=headers(token)).status_code == 401


def test_password_reset_invalidates_old_sessions(deletion_context):
    client, db, auth = deletion_context
    user = db.query(User).filter(User.id == "delete-patient").one()
    user.reset_token_hash = hashlib.sha256(b"12345678").hexdigest()
    user.reset_token_expires = datetime.now(timezone.utc) + timedelta(minutes=5)
    db.commit()
    assert client.post("/api/v1/auth/reset-password", json={
        "email": user.email, "token": "12345678", "new_password": "NewPassword123!",
    }).status_code == 200
    assert client.get("/api/v1/users/me", headers=auth).status_code == 401
    assert client.delete("/api/v1/users/me", headers=auth).status_code == 401
    login = client.post("/api/v1/auth/login", json={"email": user.email, "password": "NewPassword123!"})
    assert login.status_code == 200
    assert client.get("/api/v1/users/me", headers=headers(login.json()["access_token"])).status_code == 200
