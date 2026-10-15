from datetime import timedelta, datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import Mock
import pytest
from fastapi import HTTPException, Request
from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from app.core.database import Base
from app.models import RoutineAdherence, RoutineEntry, User, Product, AuditLog
from app.schemas.routine import AdherenceCreate
from app.api.v1.routine import log
from app.services import adherence_attempts as attempts
from app.services.routine import today
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create
from tests.test_postgres_gate import pg_engine

ROOT="/api/v1/routine/adherence"
KEY="synthetic-adherence-key-001"


def payload(entry):
    return dict(routine_entry_id=entry["id"],date=today().isoformat(),slot="AM",status="completed",note="Synthetic")


def test_lost_response_replay_fresh_session_and_history(deletion_context):
    client,db,auth=deletion_context
    entry=create(client,auth).json();data=payload(entry);headers={**auth,"Idempotency-Key":KEY}
    first=client.post(ROOT,headers=headers,json=data)
    assert first.status_code == 201
    saved=first.json();assert saved["receipt"]["configuration_revision"] == 1
    assert "payload_hash" not in str(saved) and KEY not in str(saved)
    assert client.post(ROOT,headers=headers,json=data).json() == saved
    with Session(db.get_bind()) as fresh:
        found=attempts.lookup(fresh,"delete-patient",KEY)
        assert found["status"] == "committed" and found["result"].id == saved["id"]
    # Replay precedes current configuration checks; original evidence is immutable.
    assert client.delete("/api/v1/routine/entries/"+entry["id"],headers=auth).status_code == 204
    assert client.post(ROOT,headers=headers,json=data).json() == saved
    assert client.post(ROOT,headers=headers,json={**data,"status":"skipped"}).status_code == 409
    found=client.get(ROOT+"/attempts/"+KEY,headers=auth).json()
    assert found["result"] == saved and found["actor_id"] == found["owner_id"] == "delete-patient"
    assert db.query(AuditLog).filter_by(action="ROUTINE_ADHERENCE_REPORTED").count() == 1


def test_ttl_conflicting_slot_unknown_and_isolation(deletion_context):
    from app.core.security import create_access_token
    client,db,auth=deletion_context
    data=payload(create(client,auth).json());headers={**auth,"Idempotency-Key":KEY}
    saved=client.post(ROOT,headers=headers,json=data).json()
    other={"Authorization":"Bearer "+create_access_token("delete-doctor","doctor",hashed_password="unused")}
    assert client.get(ROOT+"/attempts/"+KEY,headers=other).json()["status"] == "unknown"
    assert client.post(ROOT,headers={**other,"Idempotency-Key":KEY},json=data).status_code == 404
    another=KEY+"-different"
    assert client.post(ROOT,headers={**auth,"Idempotency-Key":another},json=data).status_code == 409
    assert client.get(ROOT+"/attempts/"+another,headers=auth).json()["status"] == "unknown"
    db.get(RoutineAdherence,saved["id"]).created_at=datetime.now(timezone.utc)-timedelta(days=30,seconds=1);db.commit()
    expired=client.get(ROOT+"/attempts/"+KEY,headers=auth).json()
    assert expired["status"] == "expired" and expired["result"] is None and expired["resource_id"] == saved["id"]
    assert client.post(ROOT,headers=headers,json=data).status_code == 410
    assert client.get(ROOT,headers=auth).json()[0]["id"] == saved["id"]
    assert client.get(ROOT+"/attempts/"+KEY).status_code == 401


@pytest.mark.parametrize("key",["","short","bad key00000000000","a"*129])
def test_invalid_key(deletion_context,key):
    client,db,auth=deletion_context
    data=payload(create(client,auth).json())
    assert client.post(ROOT,headers={**auth,"Idempotency-Key":key},json=data).status_code == 422
    assert db.query(RoutineAdherence).count() == 0


def test_duplicate_no_key_corrupt_receipt_and_rollback(deletion_context,monkeypatch):
    client,db,auth=deletion_context
    data=payload(create(client,auth).json())
    assert client.post(ROOT,headers=[*auth.items(),("Idempotency-Key",KEY),("Idempotency-Key",KEY)],json=data).status_code == 422
    commit=db.commit
    monkeypatch.setattr(db,"commit",Mock(side_effect=RuntimeError("synthetic failure")))
    assert client.post(ROOT,headers={**auth,"Idempotency-Key":KEY},json=data).status_code == 503
    assert client.get(ROOT+"/attempts/"+KEY,headers=auth).json()["status"] == "unknown"
    assert db.query(RoutineAdherence).count() == 0
    assert db.query(AuditLog).filter_by(action="ROUTINE_ADHERENCE_REPORTED").count() == 0
    monkeypatch.setattr(db,"commit",commit)
    saved=client.post(ROOT,headers={**auth,"Idempotency-Key":KEY},json=data).json()
    row=db.get(RoutineAdherence,saved["id"]);row.attempt_metadata={"schema_version":1,"payload_hash":"bad"};db.commit()
    assert client.get(ROOT+"/attempts/"+KEY,headers=auth).status_code == 503


def test_legacy_adherence_has_no_receipt(deletion_context):
    client,db,auth=deletion_context
    data=payload(create(client,auth).json())
    assert client.post(ROOT,headers=auth,json=data).json()["receipt"] is None
    assert client.post(ROOT,headers={**auth,"Idempotency-Key":KEY},json=data).status_code == 409
    assert client.get(ROOT+"/attempts/"+KEY,headers=auth).json()["status"] == "unknown"


def test_account_erasure_removes_attempt(deletion_context,monkeypatch):
    from app.services.azure_blob import azure_blob_service
    client,db,auth=deletion_context
    data=payload(create(client,auth).json());saved=client.post(ROOT,headers={**auth,"Idempotency-Key":KEY},json=data).json()
    monkeypatch.setattr(azure_blob_service,"delete_image",Mock());monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    assert client.delete("/api/v1/users/me",headers=auth).status_code == 204
    assert db.get(RoutineAdherence,saved["id"]) is None
    assert client.get(ROOT+"/attempts/"+KEY,headers=auth).status_code == 401


def race(engine,conflicting):
    Base.metadata.create_all(engine);factory=sessionmaker(bind=engine,autoflush=False)
    with factory() as db:
        db.add(User(id="owner",email="owner@synthetic.test",full_name="Synthetic",hashed_password="test"));db.commit()
        db.add(Product(id="product",user_id="owner",name="Synthetic"));db.commit()
        db.add(RoutineEntry(id="entry",user_id="owner",product_id="product",schedule="AM",frequency="daily",start_date=today()));db.commit()
    barrier=Barrier(2)
    def submit(index):
        with factory() as db:
            user=db.get(User,"owner");barrier.wait(timeout=5)
            request=Request({"type":"http","headers":[(b"idempotency-key",KEY.encode())]})
            data=AdherenceCreate(routine_entry_id="entry",date=today(),slot="AM",status="skipped" if conflicting and index else "completed")
            try:
                row=log(data,request,user,db);return 201,row.id
            except HTTPException as exc:
                db.rollback();return exc.status_code,None
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(submit,range(2)))
    assert sorted(code for code,_ in results) == ([201,409] if conflicting else [201,201])
    if not conflicting:assert results[0][1] == results[1][1]
    with factory() as db:
        assert db.query(RoutineAdherence).count() == 1
        assert db.query(AuditLog).filter_by(action="ROUTINE_ADHERENCE_REPORTED").count() == 1
        assert attempts.lookup(db,"owner",KEY)["status"] == "committed"


@pytest.mark.parametrize("conflicting",[False,True])
def test_sqlite_adherence_attempt_race(tmp_path,conflicting):
    engine=create_engine("sqlite:///"+(tmp_path/"adherence.db").as_posix(),connect_args={"check_same_thread":False,"timeout":10})
    try:race(engine,conflicting)
    finally:engine.dispose()


@pytest.mark.parametrize("conflicting",[False,True])
def test_pg_adherence_attempt_race(pg_engine,conflicting):race(pg_engine,conflicting)


def migrate(engine,monkeypatch):
    from pathlib import Path
    from sqlalchemy import MetaData, text
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    monkeypatch.setattr(settings,"DATABASE_URL",engine.url.render_as_string(hide_password=False))
    cfg=Config(str(Path(__file__).parents[1]/"alembic.ini"));command.upgrade(cfg,"20261014_03")
    metadata=MetaData();metadata.reflect(engine)
    now=datetime.now(timezone.utc).replace(tzinfo=None)
    with engine.begin() as c:
        c.execute(metadata.tables["users"].insert().values(id="owner",email="owner@synthetic.test",hashed_password="test",full_name="Synthetic",role="patient",reset_token_attempts=0))
        c.execute(metadata.tables["products"].insert().values(id="product",user_id="owner",name="Synthetic",category="treatment"))
        c.execute(metadata.tables["routine_entries"].insert().values(id="entry",user_id="owner",product_id="product",schedule="AM",frequency="daily",start_date=today(),active=True,am_order=0,pm_order=0,source="user_configured",created_at=now,updated_at=now))
        c.execute(metadata.tables["routine_adherence"].insert().values(id="report",user_id="owner",routine_entry_id="entry",date=today(),slot="AM",status="completed",source="user_reported",created_at=now,configuration_snapshot={"revision":1,"instructions":"Preserved"},note="Preserved"))
    command.upgrade(cfg,"head");command.check(cfg)
    with Session(engine) as db:
        row=db.get(RoutineAdherence,"report")
        assert row.note == "Preserved" and row.configuration_snapshot == {"revision":1,"instructions":"Preserved"} and row.receipt is None
    command.downgrade(cfg,"20261014_03");command.upgrade(cfg,"20261014_04")
    with Session(engine) as db:
        row=db.get(RoutineAdherence,"report");row.attempt_metadata={"schema_version":1,"payload_hash":"a"*64};db.commit()
    with pytest.raises(RuntimeError,match="durable adherence attempts"):
        command.downgrade(cfg,"20261014_03")


def test_adherence_sqlite_migration(tmp_path,monkeypatch):
    engine=create_engine("sqlite:///"+(tmp_path/"migration.db").as_posix())
    try:migrate(engine,monkeypatch)
    finally:engine.dispose()


def test_adherence_pg_migration(pg_engine,monkeypatch):migrate(pg_engine,monkeypatch)
