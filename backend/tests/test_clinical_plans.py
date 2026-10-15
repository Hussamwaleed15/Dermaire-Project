from datetime import datetime,timedelta,timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import Mock
import pytest
from fastapi import HTTPException
from app.models import User,Capture,CheckIn,DoctorPatientAccess
from app.models.clinical_plans import ClinicalPlan,ClinicalPlanEvent,ClinicalPlanAttempt
from app.models.notifications import Notification,NotificationJob
from app.schemas.clinical_plans import CreatePlan,ConfirmPlan,RevisePlan
from app.services import clinical_plans as service
from tests.test_doctor_loop import loop,grant,auth
from tests.test_postgres_gate import pg_engine,seed

ROOT="/api/v1/clinical-plans"
KEY="synthetic-plan-attempt-0001"


def body(access,**changes):
    due=(datetime.now(timezone.utc)+timedelta(days=14)).replace(tzinfo=None)
    return {"access_id":access.id,"kind":"follow_up","purpose":"Clinician planned follow-up visit",
            "local_due":due.isoformat(),"timezone":"UTC",**changes}


def create(loop,**changes):
    client,_,_,_,doctors=loop
    access=grant(loop)
    payload=body(access,**changes)
    result=client.post(ROOT,headers={**auth(doctors[0]),"Idempotency-Key":KEY},json=payload)
    assert result.status_code==201,result.text
    return result.json(),payload,access


def test_clinician_plan_replay_acknowledgment_and_reschedule(loop):
    client,db,patient,foreign,doctors=loop
    plan,payload,_=create(loop)
    assert plan["state"]=="proposed" and plan["acknowledged_at"] is None
    assert plan["image_inference"]["result"] is None
    headers={**auth(doctors[0]),"Idempotency-Key":KEY}
    assert client.post(ROOT,headers=headers,json=payload).json()==plan
    assert client.post(ROOT,headers=headers,json={**payload,"purpose":"A different clinical plan"}).status_code==409
    assert client.get(ROOT+f"/creation-attempts/{patient.id}/{KEY}",headers=auth(doctors[0])).json()["result"]==plan
    base=ROOT+"/"+plan["id"]
    assert client.get(base,headers=auth(foreign)).status_code==404
    assert client.post(base+"/acknowledge",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"consent":False}).status_code==409
    scheduled=client.post(base+"/acknowledge",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"consent":True})
    assert scheduled.status_code==200 and scheduled.json()["state"]=="scheduled"
    assert client.post(base+"/acknowledge",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"consent":True}).json()==scheduled.json()
    assert client.post(base+"/reschedule",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":2,"local_due":payload["local_due"],"timezone":"UTC"}).status_code==403
    revised=client.post(base+"/reschedule",headers=headers,json={"expected_revision":2,"local_due":payload["local_due"],"timezone":"Africa/Cairo"})
    assert revised.status_code==200 and revised.json()["state"]=="proposed" and revised.json()["acknowledged_at"] is None
    assert revised.json()["revision"]==3
    history=client.get(base+"/history",headers=auth(patient)).json()
    assert [r["revision"] for r in history["items"]]==[1,2,3]
    assert history["items"][0]["snapshot"]["plan"]==plan
    assert db.query(ClinicalPlanAttempt).count()==3


def test_grant_revocation_does_not_expose_doctor_receipts_but_owner_can_cancel(loop):
    client,db,patient,_,doctors=loop
    plan,_,access=create(loop)
    access.status="revoked";db.commit()
    base=ROOT+"/"+plan["id"]
    assert client.get(base,headers=auth(doctors[0])).status_code==403
    assert client.get(base+f"/attempts/create/{KEY}",headers=auth(doctors[0])).status_code==403
    assert client.get(base,headers=auth(patient)).status_code==200
    assert client.post(base+"/acknowledge",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"consent":True}).status_code==403
    assert client.post(base+"/cancel",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"reason":"Withdraw scheduling consent"}).json()["state"]=="cancelled"


def capture(db,owner,identifier,received=None):
    row=Capture(id=identifier,user_id=owner.id,state="accepted",source="camera",view="front",quality={"synthetic_contract_only":True},
        storage="azure_blob",image_blob_name=f"skin_photos/{owner.id}/{owner.id}_synthetic_{identifier}",server_version="synthetic-v1",
        received_at=received or datetime.now(timezone.utc))
    db.add(row);db.commit();return row


def test_plan_linked_private_comparison_without_fabricated_inference(loop):
    client,db,patient,foreign,doctors=loop
    observation=CheckIn(id="observation",user_id=patient.id,date_str="2026-10-15");db.add(observation);db.commit()
    baseline=capture(db,patient,"baseline",datetime.now(timezone.utc)-timedelta(days=2))
    plan,_,_=create(loop,kind="comparison",source_type="observation",source_id=observation.id,baseline_capture_id=baseline.id)
    base=ROOT+"/"+plan["id"]
    assert client.post(base+"/acknowledge",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"consent":True}).status_code==200
    followup=capture(db,patient,"followup")
    capture(db,foreign,"foreign-capture")
    for cid,code in (("foreign-capture",404),("baseline",409)):
        assert client.post(base+"/capture",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":2,"capture_id":cid}).status_code==code
    result=client.post(base+"/capture",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":2,"capture_id":followup.id})
    assert result.status_code==200 and result.json()["state"]=="captured"
    assert result.json()["image_inference"]["status"]=="unavailable" and result.json()["image_inference"]["model_version"] is None
    reviewed=client.post(base+"/review",headers={**auth(doctors[0]),"Idempotency-Key":KEY},json={"expected_revision":3,"assessment":"Clinician assessment recorded separately"})
    assert reviewed.status_code==200 and reviewed.json()["state"]=="reviewed"
    assert reviewed.json()["clinical_clearance"] is False
    assert db.query(ClinicalPlanEvent).count()==4


@pytest.mark.parametrize("changes,code",[
    ({"kind":"comparison"},422),
    ({"timezone":"Unknown/Zone"},422),
    ({"local_due":"2026-03-08T02:30:00","timezone":"America/New_York"},422),
    ({"local_due":"2026-11-01T01:30:00","timezone":"America/New_York"},422),
    ({"source_type":"routine","source_id":"foreign"},404),
])
def test_invalid_calendar_and_source(loop,changes,code):
    client,_,_,_,doctors=loop
    access=grant(loop)
    result=client.post(ROOT,headers={**auth(doctors[0]),"Idempotency-Key":KEY},json=body(access,**changes))
    assert result.status_code==code,result.text


@pytest.mark.parametrize("after_commit",[False,True])
def test_plan_uncertain_response_recovery(loop,monkeypatch,after_commit):
    _,db,_,_,doctors=loop
    access=grant(loop);payload=CreatePlan(**body(access))
    original=db.commit
    def fail():
        if after_commit:original()
        raise RuntimeError("Synthetic response loss")
    monkeypatch.setattr(db,"commit",fail)
    with pytest.raises(HTTPException) as error:service.create(db,doctors[0],payload,KEY)
    assert error.value.status_code==503
    monkeypatch.setattr(db,"commit",original)
    result=service.create(db,doctors[0],payload,KEY)
    assert result["revision"]==1 and db.query(ClinicalPlan).count()==db.query(ClinicalPlanAttempt).count()==1


def test_pg_plan_cas_has_one_winner(pg_engine):
    factory=seed(pg_engine)
    with factory() as db:
        access=DoctorPatientAccess(id="grant",patient_id="owner",doctor_id="doctor0",status="active",access_token="synthetic",expires_at=datetime.now(timezone.utc)+timedelta(days=1))
        db.add(access);db.commit()
        payload=CreatePlan(**body(access))
        plan=service.create(db,db.get(User,"doctor0"),payload,KEY)
    barrier=Barrier(2)
    def run(i):
        with factory() as db:
            actor=db.get(User,"doctor0");barrier.wait(timeout=5)
            try:return service.mutate(db,actor,plan["id"],"reschedule",RevisePlan(expected_revision=1,local_due=payload.local_due+timedelta(days=i+1),timezone="UTC"),KEY+str(i))["revision"]
            except HTTPException as error:db.rollback();return error.status_code
    with ThreadPoolExecutor(2) as pool:results=list(pool.map(run,range(2)))
    assert sorted(results)==[2,409]
    with factory() as db:assert db.query(ClinicalPlanEvent).count()==2


@pytest.mark.parametrize("who",["patient","doctor"])
def test_plan_account_erasure_removes_receipts_and_history(loop,monkeypatch,who):
    _,db,patient,_,doctors=loop
    plan,_,_=create(loop)
    from app.services.account_deletion import delete_account
    from app.services.deletion_journal import deletion_journal
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(deletion_journal,"record",Mock());monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    delete_account(db,patient.id if who=="patient" else doctors[0].id)
    assert db.query(ClinicalPlan).count()==db.query(ClinicalPlanAttempt).count()==db.query(ClinicalPlanEvent).count()==0


def test_plan_reminder_created_only_after_consent_and_cancelled_on_reschedule(loop):
    client,db,patient,_,doctors=loop
    from app.services.notifications import change_preferences,source_active
    from app.schemas.notifications import PreferencesIn
    change_preferences(db,patient,PreferencesIn(expected_revision=0,enabled_kinds=["follow_up"],push_enabled=False,timezone="UTC",quiet_start=0,quiet_end=0))
    plan,payload,_=create(loop)
    assert db.query(Notification).count()==0
    base=ROOT+"/"+plan["id"]
    assert client.post(base+"/acknowledge",headers={**auth(patient),"Idempotency-Key":KEY},json={"expected_revision":1,"consent":True}).status_code==200
    notice=db.query(Notification).one()
    assert notice.source_revision==2 and source_active(db,notice,datetime.now(timezone.utc))
    assert client.post(base+"/reschedule",headers={**auth(doctors[0]),"Idempotency-Key":KEY},json={"expected_revision":2,"local_due":payload["local_due"],"timezone":"UTC"}).status_code==200
    assert db.query(Notification).one().cancelled_at is not None


def test_populated_plan_migration_downgrade_is_refused(tmp_path,monkeypatch):
    from sqlalchemy import create_engine,text
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    url="sqlite:///"+(tmp_path/"plan-migration.db").as_posix()
    monkeypatch.setattr(settings,"DATABASE_URL",url);config=Config("alembic.ini")
    command.upgrade(config,"head")
    engine=create_engine(url)
    with engine.begin() as c:
        c.execute(text("INSERT INTO clinical_plans(id,user_id,doctor_id,access_id,kind,revision,state,purpose,due_at,schedule_provenance,source_snapshot,created_at) VALUES ('p','u','d','a','follow_up',1,'proposed','Synthetic',CURRENT_TIMESTAMP,'{}','{}',CURRENT_TIMESTAMP)"))
    with pytest.raises(RuntimeError,match="clinical plans"):command.downgrade(config,"20261015_05")
    engine.dispose()


def test_forged_private_capture_namespace_is_rejected(loop):
    _,db,patient,foreign,_=loop
    row=capture(db,patient,"forged")
    row.image_blob_name=f"skin_photos/{foreign.id}/{foreign.id}_private";db.commit()
    with pytest.raises(HTTPException) as error:service.private_capture(db,patient.id,row.id)
    assert error.value.status_code==404
