from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from threading import Barrier
from unittest.mock import Mock
import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session
from app.models import User, DoctorPatientAccess, AuditLog
from app.models.messaging import MessageThread, ThreadMessage
from app.schemas.messaging import OpenThread, SendMessage
from app.services import messaging as service
from tests.test_doctor_loop import loop, grant, auth
from tests.test_postgres_gate import pg_engine, seed

ROOT = "/api/v1/messaging/threads"
KEY = "synthetic-message-key-0001"


def opened(loop):
    client, db, patient, _, doctors = loop
    access = grant(loop)
    result = client.post(ROOT, headers=auth(patient), json={"access_id": access.id, "messaging_consent": True})
    assert result.status_code == 201, result.text
    return result.json()["id"], access


def test_consent_send_replay_readback_and_conflict(loop):
    client, db, patient, foreign, doctors = loop
    thread, _ = opened(loop)
    path = ROOT + f"/{thread}/messages"
    headers = {**auth(patient), "Idempotency-Key": KEY}
    first = client.post(path, headers=headers, json={"body": "Please review my progress"})
    assert first.status_code == 201, first.text
    assert first.headers["cache-control"] == "no-store"
    assert client.post(path, headers=headers, json={"body": "Please review my progress"}).json() == first.json()
    assert client.post(path, headers=headers, json={"body": "Different"}).status_code == 409
    assert client.get(ROOT+f"/{thread}/attempts/{KEY}", headers=auth(patient)).json()["result"] == first.json()
    assert client.get(ROOT+f"/{thread}/attempts/{KEY}", headers=auth(doctors[0])).json()["status"] == "unknown"
    assert db.query(ThreadMessage).count() == 1
    audits = db.query(AuditLog).filter_by(action="MESSAGE_COMMITTED").all()
    assert len(audits) == 1 and "Please review" not in str(audits[0].details)
    assert client.get(path, headers=auth(foreign)).status_code == 404
    assert client.get(path, headers=auth(doctors[1])).status_code == 404
    assert client.get(path).status_code == 401
    assert client.post(path, headers=auth(patient), json={"body":"Hello"}).status_code == 422
    assert client.post(path, headers={**auth(patient), "Idempotency-Key":"bad"}, json={"body":"Hello"}).status_code == 422


def test_enrollment_requires_patient_and_explicit_consent(loop):
    client, db, patient, foreign, doctors = loop
    access = grant(loop)
    body = {"access_id":access.id, "messaging_consent":False}
    assert client.post(ROOT, headers=auth(patient), json=body).status_code == 403
    body["messaging_consent"] = True
    assert client.post(ROOT, headers=auth(doctors[0]), json=body).status_code == 403
    assert client.post(ROOT, headers=auth(foreign), json=body).status_code == 404
    one = client.post(ROOT, headers=auth(patient), json=body).json()
    assert client.post(ROOT, headers=auth(patient), json=body).json() == one
    assert db.query(MessageThread).count() == 1


def test_consent_withdrawal_remains_available_after_policy_change(loop, monkeypatch):
    from app.core.config import settings
    client,_,patient,_,_=loop
    thread,_=opened(loop)
    monkeypatch.setattr(settings,"SAFETY_POLICY_ENFORCE",True)
    assert client.post(ROOT+f"/{thread}/messages",headers={**auth(patient),"Idempotency-Key":KEY},json={"body":"Hello"}).status_code == 403
    assert client.delete(ROOT+f"/{thread}/consent",headers=auth(patient)).status_code == 200


@pytest.mark.parametrize("mode", ["revoked", "expired", "withdrawn", "doctor_role_changed"])
def test_no_receipt_bypass_after_revocation(loop, mode):
    client, db, patient, _, doctors = loop
    thread, access = opened(loop)
    base = ROOT+f"/{thread}"
    headers = {**auth(patient), "Idempotency-Key":KEY}
    assert client.post(base+"/messages", headers=headers,json={"body":"Private"}).status_code == 201
    if mode == "revoked":
        access.status = "revoked"; db.commit()
        grant(loop)  # New VIEW grant cannot revive old conversation.
    elif mode == "expired":
        access.expires_at = datetime.now(timezone.utc)-timedelta(seconds=1); db.commit()
    elif mode == "doctor_role_changed":
        doctors[0].role = "support"; db.commit()
    else:
        assert client.delete(base+"/consent",headers=auth(patient)).status_code == 200
    for suffix in ("/messages", f"/attempts/{KEY}"):
        assert client.get(base+suffix,headers=auth(patient)).status_code == 403
    assert client.post(base+"/messages", headers=headers,json={"body":"Private"}).status_code == 403
    assert client.get(ROOT,headers=auth(patient)).json()["items"] == []
    assert client.delete(base+"/consent",headers=auth(patient)).status_code == 200


def test_pagination_frozen_high_watermark_and_monotone_read(loop):
    client, db, patient, _, doctors = loop
    thread,_ = opened(loop); base=ROOT+f"/{thread}"
    for i in range(3):
        assert client.post(base+"/messages",headers={**auth(patient),"Idempotency-Key":KEY+str(i)},json={"body":str(i)}).status_code == 201
    first = client.get(base+"/messages?limit=2",headers=auth(doctors[0])).json()
    assert first["as_of_sequence"] == 3 and first["next_after"] == 2
    client.post(base+"/messages",headers={**auth(doctors[0]),"Idempotency-Key":KEY},json={"body":"Reply"})
    second=client.get(base+"/messages?after=2&as_of=3",headers=auth(doctors[0])).json()
    assert [r["sequence"] for r in second["items"]] == [3]
    assert client.put(base+"/read",headers=auth(doctors[0]),json={"through_sequence":3}).json()["doctor_read"] == 3
    assert client.put(base+"/read",headers=auth(doctors[0]),json={"through_sequence":1}).json()["doctor_read"] == 3
    assert client.put(base+"/read",headers=auth(doctors[0]),json={"through_sequence":5}).status_code == 422
    assert client.get(base+"/messages?as_of=99",headers=auth(patient)).status_code == 422


@pytest.mark.parametrize("after_commit", [False,True])
def test_lost_response_recovery(loop, monkeypatch, after_commit):
    _,db,patient,_,_=loop
    thread,_=opened(loop)
    original=db.commit
    def fail():
        if after_commit: original()
        raise RuntimeError("Synthetic response loss")
    monkeypatch.setattr(db,"commit",fail)
    with pytest.raises(HTTPException) as error:
        service.send(db,patient,thread,SendMessage(body="Hello"),KEY)
    assert error.value.status_code == 503
    monkeypatch.setattr(db,"commit",original)
    state=service.read_attempt(db,patient,thread,KEY)
    assert state["status"] == ("committed" if after_commit else "unknown")
    result=service.send(db,patient,thread,SendMessage(body="Hello"),KEY)
    assert result["sequence"] == 1 and db.query(ThreadMessage).count() == 1


@pytest.mark.parametrize("participant", ["patient","doctor"])
def test_account_erase_removes_conversation(loop, monkeypatch, participant):
    _,db,patient,_,doctors=loop
    thread,_=opened(loop)
    service.send(db,patient,thread,SendMessage(body="Private"),KEY)
    from app.services.account_deletion import delete_account
    from app.services.deletion_journal import deletion_journal
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(deletion_journal,"record",Mock())
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    delete_account(db,patient.id if participant == "patient" else doctors[0].id)
    assert db.query(ThreadMessage).count() == db.query(MessageThread).count() == 0
    assert db.query(AuditLog).filter_by(action="MESSAGE_COMMITTED").one().details == {}


@pytest.mark.parametrize("different", [False,True])
def test_pg_parallel_sends(pg_engine, different):
    factory=seed(pg_engine)
    with factory() as db:
        grant=DoctorPatientAccess(id="access",patient_id="owner",doctor_id="doctor0",status="active",
            access_token="synthetic",expires_at=datetime.now(timezone.utc)+timedelta(days=1))
        db.add(grant); db.commit()
        thread=service.open_thread(db,db.get(User,"owner"),OpenThread(access_id="access",messaging_consent=True))["id"]
    barrier=Barrier(2)
    def run(i):
        with factory() as db:
            actor=db.get(User,"owner"); barrier.wait(timeout=5)
            try:
                return service.send(db,actor,thread,SendMessage(body="Hello"+str(i) if different else "Hello"),KEY)["id"]
            except HTTPException as error:
                db.rollback(); return error.status_code
    with ThreadPoolExecutor(2) as pool: results=list(pool.map(run,range(2)))
    if different: assert results.count(409) == 1
    else: assert results[0] == results[1]
    with factory() as db:
        assert db.query(ThreadMessage).count() == 1
        assert db.query(MessageThread).one().next_sequence == 2


def test_pg_distinct_concurrent_sends_preserve_sequences(pg_engine):
    factory=seed(pg_engine)
    with factory() as db:
        db.add(DoctorPatientAccess(id="access",patient_id="owner",doctor_id="doctor0",status="active",
            access_token="synthetic",expires_at=datetime.now(timezone.utc)+timedelta(days=1)))
        db.commit()
        thread=service.open_thread(db,db.get(User,"owner"),OpenThread(access_id="access",messaging_consent=True))["id"]
    barrier=Barrier(2)
    def run(i):
        with factory() as db:
            actor=db.get(User,"owner" if i == 0 else "doctor0"); barrier.wait(timeout=5)
            return service.send(db,actor,thread,SendMessage(body="Hello"),KEY+str(i))["sequence"]
    with ThreadPoolExecutor(2) as pool: results=list(pool.map(run,range(2)))
    assert sorted(results) == [1,2]


def test_messaging_populated_downgrade_refused(loop, tmp_path, monkeypatch):
    from sqlalchemy import create_engine, text
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    url="sqlite:///"+(tmp_path/"messaging-migration.db").as_posix()
    monkeypatch.setattr(settings,"DATABASE_URL",url)
    config=Config("alembic.ini")
    command.upgrade(config,"head")
    engine=__import__("sqlalchemy").create_engine(url)
    with engine.begin() as connection:
        connection.execute(text("INSERT INTO message_threads(id,patient_id,doctor_id,access_id,created_at,next_sequence,patient_read,doctor_read) VALUES ('t','p','d','a',CURRENT_TIMESTAMP,1,0,0)"))
    with pytest.raises(RuntimeError,match="consented clinical"):
        command.downgrade(config,"20261015_03")
    engine.dispose()


def test_pg_revocation_fences_a_waiting_send(pg_engine):
    from tests.test_postgres_gate import observe_lock_wait
    factory=seed(pg_engine)
    with factory() as db:
        db.add(DoctorPatientAccess(id="access",patient_id="owner",doctor_id="doctor0",status="active",
            access_token="synthetic",expires_at=datetime.now(timezone.utc)+timedelta(days=1)));db.commit()
        thread=service.open_thread(db,db.get(User,"owner"),OpenThread(access_id="access",messaging_consent=True))["id"]
    def send():
        with factory() as db:
            try:service.send(db,db.get(User,"owner"),thread,SendMessage(body="Private"),KEY)
            except HTTPException as error:db.rollback();return error.status_code
    with factory() as blocker:
        blocker.query(User).filter_by(id="owner").with_for_update().one()
        blocker.get(DoctorPatientAccess,"access").status="revoked";blocker.flush()
        with ThreadPoolExecutor(1) as pool:
            pending=pool.submit(send)
            observe_lock_wait(pg_engine)
            blocker.commit()
            assert pending.result(timeout=5)==403
    with factory() as db:assert db.query(ThreadMessage).count()==0


def test_thread_list_pagination_is_owner_scoped(loop):
    client,_,patient,foreign,_=loop
    ids=[opened(loop)[0] for _ in range(3)]
    first=client.get(ROOT+"?limit=2",headers=auth(patient)).json()
    second=client.get(ROOT+"?limit=2&after="+first["next_after"],headers=auth(patient)).json()
    assert {r["id"] for r in first["items"]+second["items"]}==set(ids)
    assert second["next_after"] is None
    assert client.get(ROOT+"?after="+ids[0],headers=auth(foreign)).status_code==422
