from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import Mock
import pytest
from app.models import User, AuditLog
from app.models.notifications import NotificationPreference, NotificationDevice, Notification, NotificationJob
from app.schemas.notifications import PreferencesIn, DeviceIn
from app.services import notifications as service
from app.services import messaging
from app.schemas.messaging import SendMessage
from tests.test_doctor_loop import loop, auth
from tests.test_messaging import opened, KEY
from tests.test_postgres_gate import pg_engine, seed

ROOT="/api/v1/notifications"
TOKEN="synthetic-private-device-token"


def pref(**changes):
    return PreferencesIn(expected_revision=0,enabled_kinds=["message"],push_enabled=True,
                         timezone="UTC",quiet_start=0,quiet_end=0,**changes)


def setup_delivery(loop):
    _,db,patient,_,doctors=loop
    thread,_=opened(loop)
    service.change_preferences(db,doctors[0],pref())
    device=service.register(db,doctors[0],{"jti":"synthetic-session","exp":(datetime.now(timezone.utc)+timedelta(days=1)).timestamp()},
        DeviceIn(installation_id="synthetic-device-01",token=TOKEN,platform="android",push_consent=True))
    messaging.send(db,patient,thread,SendMessage(body="Private clinical content"),KEY)
    return device,thread


def test_opt_in_inbox_device_encryption_and_disabled_provider(loop):
    client,db,patient,foreign,doctors=loop
    assert client.get(ROOT+"/preferences",headers=auth(patient)).json()["enabled_kinds"] == []
    device,thread=setup_delivery(loop)
    row=db.get(NotificationDevice,device["id"])
    assert TOKEN not in row.token_encrypted and service.cipher().decrypt(row.token_encrypted.encode()).decode()==TOKEN
    assert db.query(Notification).count()==db.query(NotificationJob).count()==1
    inbox=client.get(ROOT,headers=auth(doctors[0]))
    assert inbox.headers["cache-control"]=="no-store" and len(inbox.json()["items"])==1
    assert "Private clinical" not in inbox.text and TOKEN not in inbox.text
    notice=inbox.json()["items"][0]["id"]
    assert client.get(ROOT,headers=auth(foreign)).json()["items"]==[]
    assert client.put(ROOT+f"/{notice}/read",headers=auth(foreign)).status_code==404
    result=client.put(ROOT+f"/{notice}/read",headers=auth(doctors[0])).json()
    assert result["receipt"]=="app_read_acknowledged" and result["delivery_confirmed"] is False
    assert client.put(ROOT+f"/{notice}/read",headers=auth(doctors[0])).json()==result
    output=service.dispatch_one(db)
    assert output["provider_outcome"]=="unavailable" and output["delivery_confirmed"] is False
    assert db.query(NotificationJob).one().state=="provider_unavailable"


def test_fake_local_pipeline_is_generic_and_deduplicated(loop):
    _,db,patient,_,_=loop
    setup_delivery(loop)
    class Fake:
        calls=[]
        def send(self,**request):
            self.calls.append(request)
            return "accepted"
    fake=Fake()
    output=service.dispatch_one(db,fake)
    assert output["provider_outcome"]=="accepted" and not output["delivery_confirmed"]
    assert fake.calls[0]["payload"]=={"title":"Dermaire","body":"You have an update"}
    assert service.dispatch_one(db,fake) is None
    assert len(fake.calls)==1 and db.query(NotificationJob).one().state=="provider_accepted"


@pytest.mark.parametrize("mode",["logout","password","session_expired","device_revoked","grant_revoked","consent_withdrawn","preference_off"])
def test_no_dispatch_after_revocation(loop,mode):
    client,db,patient,_,doctors=loop
    device,thread=setup_delivery(loop)
    row=db.get(NotificationDevice,device["id"])
    if mode=="logout": db.add(AuditLog(actor_id=doctors[0].id,action="SESSION_REVOKED",target_resource=row.session_id,details={}))
    elif mode=="password": doctors[0].hashed_password="changed"
    elif mode=="session_expired": row.session_expires_at=datetime.now(timezone.utc)-timedelta(seconds=1)
    elif mode=="device_revoked": row.revoked_at=datetime.now(timezone.utc)
    elif mode=="grant_revoked":
        from app.models import DoctorPatientAccess
        db.query(DoctorPatientAccess).update({"status":"revoked"})
    elif mode=="consent_withdrawn":
        from app.models.messaging import MessageThread
        db.get(MessageThread,thread).closed_at=datetime.now(timezone.utc)
    else: db.query(NotificationPreference).one().push_enabled=False
    db.commit()
    fake=Mock(); fake.send.side_effect=AssertionError("No external dispatch")
    assert service.dispatch_one(db,fake)["state"]=="cancelled"
    fake.send.assert_not_called()


def test_lease_fencing_retry_backoff_and_revoke_during_dispatch(loop):
    _,db,_,_,doctors=loop
    device,_=setup_delivery(loop)
    now=datetime.now(timezone.utc)
    first=service.claim(db,now)
    assert first and not service.finish(db,first["id"],"wrong-token","accepted",now)
    assert not service.finish(db,first["id"],first["lease_token"],"accepted",now+timedelta(seconds=61))
    second=service.claim(db,now+timedelta(seconds=62))
    assert second["lease_token"]!=first["lease_token"]
    assert not service.finish(db,first["id"],first["lease_token"],"accepted",now+timedelta(seconds=63))
    assert service.finish(db,second["id"],second["lease_token"],"retry",now+timedelta(seconds=63))
    job=db.get(NotificationJob,second["id"])
    assert job.state=="retry" and job.attempts==2
    assert service.claim(db,now+timedelta(seconds=64)) is None
    third=service.claim(db,now+timedelta(seconds=200))
    db.get(NotificationDevice,device["id"]).revoked_at=now; db.commit()
    assert service.finish(db,third["id"],third["lease_token"],"accepted",now+timedelta(seconds=201))
    assert db.get(NotificationJob,third["id"]).state=="cancelled"


def test_quiet_hours_retry_and_cas_preferences(loop):
    client,db,_,_,doctors=loop
    setup_delivery(loop)
    now=datetime.now(timezone.utc)
    row=service.preferences(db,doctors[0].id)
    minute=now.hour*60+now.minute
    row.quiet_start=minute; row.quiet_end=(minute+60)%1440; db.commit()
    assert service.dispatch_one(db,now=now)["state"]=="quiet_hours"
    assert db.query(NotificationJob).one().attempts==0
    body=pref().model_dump()
    assert client.put(ROOT+"/preferences",headers=auth(doctors[0]),json=body).status_code==409
    body.update(expected_revision=1,enabled_kinds=[],push_enabled=False)
    assert client.put(ROOT+"/preferences",headers=auth(doctors[0]),json=body).json()["revision"]==2
    assert db.query(Notification).one().cancelled_at is not None
    assert db.query(NotificationJob).one().state=="cancelled"


def test_provider_error_and_secret_rotation_fail_closed(loop,monkeypatch):
    from app.core.config import settings
    _,db,_,_,_=loop
    setup_delivery(loop)
    fake=Mock();fake.send.side_effect=RuntimeError("Do not log provider secrets")
    assert service.dispatch_one(db,fake)["provider_outcome"]=="retry"
    job=db.query(NotificationJob).one(); job.available_at=datetime.now(timezone.utc)-timedelta(seconds=1);db.commit()
    monkeypatch.setattr(settings,"SECRET_KEY","synthetic-rotated-encryption-key")
    assert service.dispatch_one(db,fake)["state"]=="cancelled"
    assert fake.send.call_count==1


def test_notification_optout_survives_policy_change(loop,monkeypatch):
    from app.core.config import settings
    client,db,_,_,doctors=loop
    setup_delivery(loop)
    monkeypatch.setattr(settings,"SAFETY_POLICY_ENFORCE",True)
    result=client.delete(ROOT+"/preferences?expected_revision=1",headers=auth(doctors[0]))
    assert result.status_code==200 and result.json()["enabled_kinds"]==[]
    assert db.query(NotificationJob).one().state=="cancelled"


def test_registration_session_binding_and_account_switch(loop):
    client,db,patient,foreign,_=loop
    for actor in (patient,foreign): service.change_preferences(db,actor,pref())
    body={"installation_id":"synthetic-installation","token":TOKEN,"platform":"android","push_consent":True}
    headers=auth(patient)
    first=client.post(ROOT+"/devices",headers=headers,json=body)
    assert first.status_code==201 and TOKEN not in first.text
    assert client.post(ROOT+"/devices",headers=headers,json=body).json()==first.json()
    assert client.post(ROOT+"/devices",headers=auth(foreign),json=body).status_code==409
    assert client.delete(ROOT+"/devices/"+first.json()["id"],headers=auth(foreign)).status_code==404
    assert client.post("/api/v1/auth/logout",headers=headers).status_code==204
    second=client.post(ROOT+"/devices",headers=auth(foreign),json=body)
    assert second.status_code==201
    assert db.get(NotificationDevice,first.json()["id"]).revoked_at is not None


@pytest.mark.parametrize("who",["patient","doctor"])
def test_delete_either_participant_erases_message_notifications(loop,monkeypatch,who):
    _,db,patient,_,doctors=loop
    setup_delivery(loop)
    from app.services.account_deletion import delete_account
    from app.services.deletion_journal import deletion_journal
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(deletion_journal,"record",Mock());monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    delete_account(db,patient.id if who=="patient" else doctors[0].id)
    assert db.query(Notification).count()==db.query(NotificationJob).count()==0


def test_pg_worker_claim_has_one_lease(pg_engine):
    factory=seed(pg_engine)
    from app.models import DoctorPatientAccess
    from app.schemas.messaging import OpenThread
    with factory() as db:
        patient=db.get(User,"owner");doctor=db.get(User,"doctor0")
        db.add(DoctorPatientAccess(id="grant",patient_id=patient.id,doctor_id=doctor.id,status="active",access_token="synthetic",expires_at=datetime.now(timezone.utc)+timedelta(days=1)));db.commit()
        thread=messaging.open_thread(db,patient,OpenThread(access_id="grant",messaging_consent=True))["id"]
        service.change_preferences(db,doctor,pref())
        service.register(db,doctor,{"jti":"synthetic","exp":(datetime.now(timezone.utc)+timedelta(days=1)).timestamp()},DeviceIn(installation_id="synthetic-installation",token=TOKEN,platform="ios",push_consent=True))
        messaging.send(db,patient,thread,SendMessage(body="Hello"),KEY)
    barrier=Barrier(2)
    def run(_):
        with factory() as db: barrier.wait(timeout=5); return service.claim(db)
    with ThreadPoolExecutor(2) as pool: results=list(pool.map(run,range(2)))
    assert sum(bool(r and "id" in r) for r in results)==1
