from datetime import datetime,timedelta,timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import Mock
import pytest
from fastapi import Request,Response,HTTPException
from app.models import User,Product,RoutineEntry,Experiment,ExperimentEvaluation,CheckIn,AuditLog,ConfigurationAttempt
from app.schemas.routine import RoutineCreate
from app.schemas.experiments import ExperimentCreate
from app.api.v1 import routine as routine_api,experiments as experiment_api
from app.core.security import create_access_token
from app.services import configuration_attempts as attempts
from app.services.deletion_journal import DeletionJournal
from tests.test_deletion_journal import Container
from tests.test_account_deletion import deletion_context
from tests.test_experiment_engine_v2 import context,draft,collect
from tests.test_postgres_gate import pg_engine,seed

KEY="synthetic-configuration-key-0001"
ROUTINE="/api/v1/routine"
EXPERIMENT="/api/v1/experiments"


def routine_body(**changes):
    return {"product_id":"owned-product","schedule":"AM","frequency":"daily","start_date":datetime.now(timezone.utc).date().isoformat(),**changes}


def test_routine_create_update_stop_freeze_original_results(deletion_context):
    client,db,auth=deletion_context
    headers={**auth,"Idempotency-Key":KEY}
    created=client.post(ROUTINE+"/entries",headers=headers,json=routine_body(instructions="Original"))
    assert created.status_code==201,created.text
    original=created.json();path=ROUTINE+"/entries/"+original["id"]
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body(instructions="Original")).json()==original
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body(instructions="Different")).status_code==409
    update_headers={**headers,"If-Match":created.headers["etag"]}
    edited=client.patch(path,headers=update_headers,json={"instructions":"Edited"})
    assert edited.status_code==200,edited.text
    assert client.patch(path,headers=update_headers,json={"instructions":"Edited"}).json()==edited.json()
    assert client.patch(path,headers={**update_headers,"If-Match":edited.headers["etag"]},json={"instructions":"Edited"}).status_code==409
    stopped=client.delete(path,headers={**headers,"If-Match":edited.headers["etag"]})
    assert stopped.status_code==204 and stopped.headers["operation-attempt-id"]
    assert client.delete(path,headers={**headers,"If-Match":edited.headers["etag"]}).status_code==204
    lookup=client.get(ROUTINE+f"/configuration-attempts/create/{KEY}",headers=auth)
    assert lookup.json()["result"]==original
    assert lookup.headers["cache-control"]=="no-store"
    assert db.query(ConfigurationAttempt).count()==3
    assert db.query(AuditLog).filter_by(action="CONFIGURATION_OPERATION_COMMITTED").count()==3
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body(instructions="Original")).json()==original
    assert created.headers["result-snapshot"]=="original_committed"


def test_experiment_draft_edit_cancel_attempts(context):
    client,db,auth,payload=context
    headers={**auth,"Idempotency-Key":KEY}
    created=client.post(EXPERIMENT,headers=headers,json=payload)
    assert created.status_code==201,created.text
    path=EXPERIMENT+"/"+created.json()["id"]
    edited=client.patch(path,headers={**headers,"If-Match":created.headers["etag"]},json={"notes":"Frozen edit"})
    assert edited.status_code==200
    cancelled=client.delete(path,headers={**headers,"If-Match":edited.headers["etag"]})
    assert cancelled.status_code==200 and cancelled.json()["status"]=="cancelled"
    assert client.delete(path,headers={**headers,"If-Match":edited.headers["etag"]}).json()==cancelled.json()
    assert client.post(EXPERIMENT,headers=headers,json=payload).json()==created.json()
    assert client.get(EXPERIMENT+f"/operation-attempts/edit/{KEY}?resource_id="+created.json()["id"],headers=auth).json()["result"]==edited.json()
    assert db.query(ConfigurationAttempt).filter_by(domain="experiment").count()==3


def test_activation_evaluation_finish_receipts_are_attempt_specific(context,monkeypatch):
    client,db,auth,_=context
    created=draft(context)
    path=EXPERIMENT+"/"+created.json()["id"]
    headers={**auth,"Idempotency-Key":KEY,"If-Match":created.headers["etag"]}
    active=client.post(path+"/activate",headers=headers)
    assert active.status_code==200,active.text
    assert client.post(path+"/activate",headers=headers).json()==active.json()
    assert client.post(path+"/activate",headers={**headers,"Routine-If-Match":'"1"'}).status_code==409
    collect(context,active.json(),monkeypatch)
    evaluation_headers={**auth,"Idempotency-Key":KEY,"If-Match":active.headers["etag"]}
    first=client.post(path+"/evaluate",headers=evaluation_headers)
    assert first.status_code==201,first.text
    assert client.post(path+"/evaluate",headers=evaluation_headers).json()==first.json()
    second=client.post(path+"/evaluate",headers={**auth,"Idempotency-Key":KEY+"second","If-Match":first.headers["experiment-etag"]})
    assert second.status_code==201 and second.json()["id"]!=first.json()["id"]
    assert client.get(EXPERIMENT+f"/operation-attempts/evaluate/{KEY}?resource_id="+created.json()["id"],headers=auth).json()["result"]==first.json()
    assert db.query(ExperimentEvaluation).filter_by(experiment_id=created.json()["id"]).count()==2
    finished=client.post(path+"/finish",headers={**auth,"Idempotency-Key":KEY,"If-Match":second.headers["experiment-etag"]},json={"status":"completed"})
    assert finished.status_code==200,finished.text
    assert finished.json()["status"]=="completed"
    assert client.post(path+"/finish",headers={**auth,"Idempotency-Key":KEY,"If-Match":second.headers["experiment-etag"]},json={"status":"completed"}).json()==finished.json()
    assert db.query(ConfigurationAttempt).filter_by(domain="experiment").count()==4


@pytest.mark.parametrize("after_commit",[False,True])
def test_routine_creation_uncertain_commit_replay(deletion_context,monkeypatch,after_commit):
    client,db,auth=deletion_context
    headers={**auth,"Idempotency-Key":KEY}
    original=db.commit
    def fail():
        if after_commit:original()
        raise RuntimeError("Synthetic lost response")
    monkeypatch.setattr(db,"commit",fail)
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body()).status_code==503
    monkeypatch.setattr(db,"commit",original)
    assert client.get(ROUTINE+f"/configuration-attempts/create/{KEY}",headers=auth).json()["status"]==("committed" if after_commit else "unknown")
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body()).status_code==201
    assert db.query(RoutineEntry).count()==db.query(ConfigurationAttempt).count()==1


@pytest.mark.parametrize("after_commit",[False,True])
def test_evaluation_commit_recovery_has_one_result(context,monkeypatch,after_commit):
    client,db,auth,_=context
    created=draft(context).json();path=EXPERIMENT+"/"+created["id"]
    active=client.post(path+"/activate",headers=auth)
    assert active.status_code==200
    collect(context,active.json(),monkeypatch)
    original=db.commit
    def fail():
        if after_commit:original()
        raise RuntimeError("Synthetic lost evaluation response")
    headers={**auth,"If-Match":active.headers["etag"],"Idempotency-Key":KEY}
    monkeypatch.setattr(db,"commit",fail)
    assert client.post(path+"/evaluate",headers=headers).status_code==503
    monkeypatch.setattr(db,"commit",original)
    assert client.post(path+"/evaluate",headers=headers).status_code==201
    assert db.query(ExperimentEvaluation).filter_by(experiment_id=created["id"]).count()==1
    assert db.query(ConfigurationAttempt).filter_by(operation="evaluate").count()==1


def test_attempt_foreign_expiry_invalid_scope_and_policy(deletion_context,monkeypatch):
    client,db,auth=deletion_context
    headers={**auth,"Idempotency-Key":KEY}
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body()).status_code==201
    path=ROUTINE+f"/configuration-attempts/create/{KEY}"
    foreign={"Authorization":"Bearer "+create_access_token("delete-doctor","doctor",hashed_password="unused")}
    assert client.get(path,headers=foreign).json()["status"]=="unknown"
    assert client.get(path).status_code==401
    assert client.get(ROUTINE+f"/configuration-attempts/update/{KEY}",headers=auth).status_code==422
    assert client.get(ROUTINE+f"/configuration-attempts/unknown/{KEY}",headers=auth).status_code==422
    row=db.query(ConfigurationAttempt).one();row.recorded_at=datetime.now(timezone.utc)-timedelta(days=31);db.commit()
    assert client.get(path,headers=auth).json()["status"]=="expired"
    assert client.post(ROUTINE+"/entries",headers=headers,json=routine_body()).status_code==410


def test_account_erasure_removes_configuration_snapshots(deletion_context,monkeypatch):
    client,db,auth=deletion_context
    client.post(ROUTINE+"/entries",headers={**auth,"Idempotency-Key":KEY},json=routine_body())
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    assert client.delete("/api/v1/users/me",headers=auth).status_code==204
    assert db.query(ConfigurationAttempt).count()==0


def test_product_journal_scrubs_orphan_configuration_snapshot(deletion_context):
    client,db,auth=deletion_context
    db.add(Product(id="erasable",user_id="delete-patient",name="Private product"));db.commit()
    result=client.post(ROUTINE+"/entries",headers={**auth,"Idempotency-Key":KEY},json=routine_body(product_id="erasable"))
    assert result.status_code==201
    db.delete(db.get(RoutineEntry,result.json()["id"]));db.commit()
    journal=DeletionJournal(Container(),"j"*32,True);journal.record_product("delete-patient","erasable")
    storage=Mock(is_live=True);storage.container_client.list_blobs.return_value=[]
    journal.replay(db,storage,Mock())
    assert db.query(ConfigurationAttempt).one().result_snapshot is None
    assert client.post(ROUTINE+"/entries",headers={**auth,"Idempotency-Key":KEY},json=routine_body(product_id="erasable")).status_code==410


@pytest.mark.parametrize("changed",[False,True])
def test_pg_routine_configuration_create_key_race(pg_engine,changed):
    factory=seed(pg_engine)
    with factory() as db:db.add(Product(id="product",user_id="owner",name="Synthetic"));db.commit()
    barrier=Barrier(2)
    def run(i):
        with factory() as db:
            actor=db.get(User,"owner");barrier.wait(timeout=5)
            payload=RoutineCreate(product_id="product",schedule="AM",frequency="daily",start_date=datetime.now(timezone.utc).date(),instructions="Different" if changed and i else "Original")
            request=Request({"type":"http","headers":[(b'idempotency-key',KEY.encode())]})
            try:return routine_api.create(payload,Response(),actor,db,request)["id"]
            except HTTPException as error:db.rollback();return error.status_code
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,range(2)))
    if changed:assert results.count(409)==1
    else:assert results[0]==results[1]
    with factory() as db:assert db.query(RoutineEntry).count()==db.query(ConfigurationAttempt).count()==1


def test_pg_configuration_seeded_migration_and_guard(pg_engine,monkeypatch):
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    from sqlalchemy.orm import Session
    monkeypatch.setattr(settings,"DATABASE_URL",pg_engine.url.render_as_string(hide_password=False))
    config=Config("alembic.ini");command.upgrade(config,"head");command.check(config)
    with Session(pg_engine) as db:
        db.add(User(id="owner",email="owner@synthetic.test",full_name="Synthetic",hashed_password="synthetic"));db.flush()
        db.add(ConfigurationAttempt(id="receipt",user_id="owner",domain="routine",operation="create",resource_id="entry",resource_revision=1,payload_hash="f"*64,result_kind="routine",result_snapshot={},recorded_at=datetime.now(timezone.utc)));db.commit()
    with pytest.raises(RuntimeError,match="committed configuration attempts"):command.downgrade(config,"20261015_08")


def pg_experiment(factory):
    with factory() as db:
        actor=db.get(User,"owner")
        db.add(Product(id="product",user_id=actor.id,name="Synthetic"));db.commit()
        day=datetime.now(timezone.utc).date()
        entry=routine_api.create(RoutineCreate(product_id="product",schedule="AM",frequency="daily",start_date=day),Response(),actor,db)
        for delta in range(1,6):
            at=datetime.combine(day-timedelta(days=delta),datetime.min.time(),timezone.utc)
            db.add(CheckIn(user_id=actor.id,date_str=at.date().isoformat(),created_at=at,hydration_score=50,texture_score=50,redness_score=50,ai_vision_analysis={"measurement_source":"manual"}))
        db.commit()
        row=experiment_api.create(ExperimentCreate(routine_entry_id=entry.id,intervention={"type":"change_schedule","schedule":"PM"},start_date=day,target_days=7),Response(),actor,db)
        return row.id


def test_pg_activation_duplicate_key_replays_one_multiresource_transition(pg_engine):
    factory=seed(pg_engine);identifier=pg_experiment(factory);barrier=Barrier(2)
    def run(_):
        with factory() as db:
            actor=db.get(User,"owner");barrier.wait(timeout=5)
            request=Request({"type":"http","headers":[(b'idempotency-key',KEY.encode()),(b'if-match',b'"1"'),(b'routine-if-match',b'"1"')]})
            return experiment_api.activate(identifier,request,Response(),actor,db)
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,range(2)))
    assert results[0]==results[1]
    with factory() as db:
        assert db.query(ConfigurationAttempt).filter_by(operation="activate").count()==1
        assert db.get(Product,"product").in_experiment
        assert db.query(RoutineEntry).one().schedule=="PM"


@pytest.mark.parametrize("different_key",[False,True])
def test_pg_evaluation_key_result_identity_and_cas(pg_engine,different_key):
    factory=seed(pg_engine);identifier=pg_experiment(factory)
    with factory() as db:
        request=Request({"type":"http","headers":[(b'if-match',b'"1"'),(b'routine-if-match',b'"1"')]})
        active=experiment_api.activate(identifier,request,Response(),db.get(User,"owner"),db)
        revision=active.revision
    barrier=Barrier(2)
    def run(index):
        with factory() as db:
            actor=db.get(User,"owner");barrier.wait(timeout=5)
            request=Request({"type":"http","headers":[(b'idempotency-key',(KEY+str(index) if different_key else KEY).encode()),(b'if-match',f'"{revision}"'.encode())]})
            try:return experiment_api.evaluate(identifier,request,Response(),actor,db)["id"]
            except HTTPException as error:db.rollback();return error.status_code
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,range(2)))
    if different_key:assert results.count(412)==1
    else:assert results[0]==results[1]
    with factory() as db:
        assert db.query(ExperimentEvaluation).count()==1
        assert db.query(ConfigurationAttempt).filter_by(operation="evaluate").count()==1
