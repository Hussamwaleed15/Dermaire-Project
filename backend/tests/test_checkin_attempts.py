import asyncio
import json
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from app.core.database import Base
from app.core.security import create_access_token
from app.models import CheckIn, AuditLog, User
from app.schemas import CheckInReport
from app.api.v1.checkins import submit_daily_checkin
from app.services import checkin_attempts
from app.services.azure_blob import azure_blob_service
from tests.test_account_deletion import deletion_context

KEY = "synthetic-attempt-0001"
DATA = {"report": json.dumps({"overall_change": "same", "symptoms": ["dryness", "redness"]})}
URL = "/api/v1/checkins"

def headers(auth, key=KEY):
    return {**auth, "Idempotency-Key": key}

def test_replay_lost_reply_restart_and_payload_conflict(deletion_context):
    client, db, auth = deletion_context
    first = client.post(URL, headers=headers(auth), data=DATA)
    assert first.status_code == 201
    identifier = first.json()["id"]
    lookup = client.get(URL+"/attempts/"+KEY, headers=auth).json()
    assert lookup["status"] == "committed" and lookup["result"]["id"] == identifier
    assert lookup["actor_id"] == lookup["owner_id"] == "delete-patient"
    db.expire_all()
    # Independent new session provides durable lookup after a process loses its response.
    with Session(db.get_bind()) as fresh:
        assert checkin_attempts.lookup(fresh, "delete-patient", KEY)["result"]["id"] == identifier
    same = {"report": json.dumps({"symptoms": ["redness", "dryness", "dryness"], "overall_change": "same", "safety": None})}
    replay = client.post(URL, headers=headers(auth), data=same)
    assert replay.status_code == 201 and replay.json()["id"] == identifier
    assert replay.json()["observation"] == first.json()["observation"]
    assert replay.json()["receipt"] == first.json()["receipt"]
    assert "payload_hash" not in str(lookup) and "attempt" not in first.json()["observation"]
    assert client.post(URL, headers=headers(auth), data={**DATA, "notes": "changed"}).status_code == 409
    assert db.query(AuditLog).filter_by(action="CHECKIN_COMPLETED").count() == 1

@pytest.mark.parametrize("key", ["", "short", "has space00000000", "\u00e9"*16, "a"*129])
def test_malformed_and_missing_auth(deletion_context, key):
    client, db, auth = deletion_context
    if not key.isascii():
        from fastapi import HTTPException
        with pytest.raises(HTTPException) as denied:
            checkin_attempts.identity("delete-patient", key)
        assert denied.value.status_code == 422
    else:
        assert client.post(URL, headers=headers(auth, key), data=DATA).status_code == 422
    assert client.get(URL+"/attempts/"+KEY).status_code == 401
    assert client.post(URL, data=DATA).status_code == 401

@pytest.mark.parametrize("data", [DATA, {"hydration_score": "50", "texture_score": "60", "redness_score": "70"}])
def test_manual_report_cross_owner_and_expiry(deletion_context, data):
    client, db, auth = deletion_context
    own = client.post(URL, headers=headers(auth), data=data)
    assert own.status_code == 201
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get(URL+"/attempts/"+KEY, headers=other).json()["status"] == "unknown"
    foreign = client.post(URL, headers=headers(other), data=data)
    assert foreign.status_code == 201 and foreign.json()["id"] != own.json()["id"]
    row = db.get(CheckIn, own.json()["id"])
    row.created_at = datetime.now(timezone.utc)-timedelta(days=31)
    db.commit()
    assert client.get(URL+"/attempts/"+KEY, headers=auth).json()["status"] == "expired"
    assert client.post(URL, headers=headers(auth), data=data).status_code == 410
    assert client.post(URL, headers=headers(other), data=data).status_code == 201

def test_rollback_unknown_and_retry(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    commit = db.commit
    monkeypatch.setattr(db, "commit", Mock(side_effect=RuntimeError("synthetic rollback")))
    assert client.post(URL, headers=headers(auth), data=DATA).status_code == 503
    assert client.get(URL+"/attempts/"+KEY, headers=auth).json()["status"] == "unknown"
    assert db.query(AuditLog).filter_by(action="CHECKIN_COMPLETED").count() == 0
    monkeypatch.setattr(db, "commit", commit)
    assert client.post(URL, headers=headers(auth), data=DATA).status_code == 201
    assert client.post(URL, headers=headers(auth), data=DATA).status_code == 201

def test_account_erasure_removes_receipt_and_denies_replay(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    saved = client.post(URL, headers=headers(auth), data=DATA).json()
    monkeypatch.setattr(azure_blob_service, "delete_image", Mock())
    monkeypatch.setattr(azure_blob_service, "delete_owned_images", Mock())
    assert client.delete("/api/v1/users/me", headers=auth).status_code == 204
    assert db.get(CheckIn, saved["id"]) is None
    assert client.get(URL+"/attempts/"+KEY, headers=auth).status_code == 401
    assert client.post(URL, headers=headers(auth), data=DATA).status_code == 401

@pytest.mark.parametrize("conflicting", [False, True])
def test_parallel_unique_commit_and_inflight_unknown(tmp_path, monkeypatch, conflicting):
    engine = create_engine("sqlite:///"+(tmp_path/"attempts.db").as_posix(), connect_args={"check_same_thread": False, "timeout": 10})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine)
    with factory() as db:
        db.add(User(id="owner", email="owner@synthetic.test", full_name="Synthetic", hashed_password="test"))
        db.commit()
    barrier = Barrier(2)
    original = Session.flush
    def simultaneous(db, *args, **kwargs):
        if any(isinstance(row, CheckIn) for row in db.new):
            # Neither reservation is committed: a separate read must be unknown.
            with factory() as reader:
                assert checkin_attempts.lookup(reader, "owner", KEY)["status"] == "unknown"
            barrier.wait(timeout=10)
        return original(db, *args, **kwargs)
    monkeypatch.setattr(Session, "flush", simultaneous)
    def submit(index):
        from fastapi import HTTPException
        with factory() as db:
            try:
                result = asyncio.run(submit_daily_checkin(time_of_day="Morning", hydration_score=None,
                    texture_score=None, redness_score=None, notes="changed" if conflicting and index else None,
                    experiment_id=None, photo=None, report=DATA["report"], idempotency_key=KEY,
                    current_user=db.get(User, "owner"), db=db))
                return 201, result.id
            except HTTPException as exc:
                return exc.status_code, None
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(submit, index) for index in range(2)]
        results = [future.result(timeout=20) for future in futures]
    assert sorted(code for code, _ in results) == ([201,409] if conflicting else [201,201])
    if not conflicting:
        assert results[0][1] == results[1][1]
    with factory() as db:
        assert db.query(CheckIn).count() == 1
        assert db.query(AuditLog).filter_by(action="CHECKIN_COMPLETED").count() == 1
    engine.dispose()
