from unittest.mock import Mock
import pytest
from tests.test_account_deletion import deletion_context
from app.models import DailyContext
from app.core.security import create_access_token
from app.services.azure_blob import azure_blob_service

DAY = "/api/v1/context/2026-10-01"

def test_owner_reads_writes_restart_and_no_defaults(deletion_context):
    client, db, auth = deletion_context
    empty = client.get(DAY, headers=auth).json()
    assert empty["recorded"] is False
    assert empty["cycle_day"] is None and empty["unusual_conditions"] is None
    assert client.get(DAY).status_code == 401
    payload = {"cycle_day": 14, "unusual_conditions": True}
    result = client.put(DAY, headers=auth, json=payload)
    assert result.status_code == 200 and result.json()["recorded"] is True
    db.expire_all()
    assert client.get(DAY, headers=auth).json() == result.json()
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get(DAY, headers=other).json()["recorded"] is False
    assert client.get("/api/v1/context/2026-10-02", headers=auth).json()["recorded"] is False
    assert client.put(DAY, headers=auth, json={}).json()["cycle_day"] is None
    assert db.query(DailyContext).count() == 1

@pytest.mark.parametrize("payload", [{"cycle_day": 0}, {"cycle_day": 61}, {"cycle_day": 1.5},
    {"cycle_day": True}, {"unusual_conditions": "false"}, {"temperature": 22}])
def test_invalid_input_never_saved(deletion_context, payload):
    client, db, auth = deletion_context
    assert client.put(DAY, headers=auth, json=payload).status_code == 422
    assert db.query(DailyContext).count() == 0

def test_failed_write_is_not_confirmed(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    monkeypatch.setattr(db, "commit", Mock(side_effect=RuntimeError("Unavailable")))
    with pytest.raises(RuntimeError):
        client.put(DAY, headers=auth, json={"cycle_day": 12})
    db.rollback()
    assert db.query(DailyContext).count() == 0

def test_context_deleted_with_account(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    client.put(DAY, headers=auth, json={"cycle_day": 12})
    monkeypatch.setattr(azure_blob_service, "delete_image", Mock())
    monkeypatch.setattr(azure_blob_service, "delete_owned_images", Mock())
    assert client.delete("/api/v1/users/me", headers=auth).status_code == 204
    assert db.query(DailyContext).count() == 0


def test_read_failure_is_not_unrecorded_success(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    query = db.query
    def unavailable(model):
        if model is DailyContext:
            raise RuntimeError("Unavailable")
        return query(model)
    monkeypatch.setattr(db, "query", unavailable)
    with pytest.raises(RuntimeError):
        client.get(DAY, headers=auth)
