"""Synthetic local reminder contracts; no device or clinical evidence."""
from datetime import datetime,date,timedelta,timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import pytest
from sqlalchemy.orm import sessionmaker
from app.models import User,Product,RoutineEntry
from app.models.notifications import Notification,NotificationJob,RoutineReminderSetting
from app.schemas.notifications import PreferencesIn,RoutineReminderIn
from app.services import notifications,routine_reminders
from tests.test_doctor_loop import loop,auth
from tests.test_postgres_gate import pg_engine,seed

ROOT="/api/v1/notifications"


def configure(db,user,**changes):
    notifications.change_preferences(db,user,PreferencesIn(expected_revision=0,enabled_kinds=["routine"],
        push_enabled=False,timezone="UTC",quiet_start=0,quiet_end=0))
    db.add(Product(id="reminder-product",user_id=user.id,name="Synthetic"));db.flush()
    db.add(RoutineEntry(id="reminder-entry",user_id=user.id,product_id="reminder-product",schedule="BOTH",
        frequency="daily",start_date=date(2026,1,1),active=True));db.commit()
    body=dict(expected_revision=0,enabled=True,timezone="UTC",am_minute=540,pm_minute=1260,fold=0,gap_policy="skip")
    body.update(changes)
    result=routine_reminders.configure(db,user,"reminder-entry",RoutineReminderIn(**body))
    setting=db.query(RoutineReminderSetting).one()
    setting.effective_at=datetime(2026,1,1,tzinfo=timezone.utc);db.commit()
    return result


def test_explicit_settings_occurrence_dedup_and_no_backfill(loop):
    client,db,user,foreign,_=loop
    configure(db,user)
    at=datetime(2026,10,15,8,tzinfo=timezone.utc)
    assert routine_reminders.generate(db,now=at)["occurrences_created"]==4
    assert routine_reminders.generate(db,now=at)["occurrences_created"]==0
    rows=db.query(Notification).all()
    assert len({row.id for row in rows})==4 and all(row.reminder_revision==1 for row in rows)
    assert client.get(ROOT+"/routine-reminders/reminder-entry",headers=auth(foreign)).status_code==404
    assert client.get(ROOT+"/routine-reminders/reminder-entry",headers=auth(user)).json()["revision"]==1
    assert client.get(ROOT+"/history",headers=auth(foreign)).json()["items"]==[]
    assert db.query(NotificationJob).count()==0
    later=datetime(2026,10,20,8,tzinfo=timezone.utc)
    routine_reminders.generate(db,now=later,days=1)
    assert not any(at+timedelta(days=2)<=notifications.utc(r.due_at)<later for r in db.query(Notification))


@pytest.mark.parametrize("zone,at,minute,fold,expected",[
    ("America/New_York",datetime(2026,3,8,0,tzinfo=timezone.utc),150,0,0),
    ("America/New_York",datetime(2026,11,1,0,tzinfo=timezone.utc),90,0,5),
    ("America/New_York",datetime(2026,11,1,0,tzinfo=timezone.utc),90,1,6),
])
def test_gap_skip_and_overlap_once(loop,zone,at,minute,fold,expected):
    _,db,user,_,_=loop
    configure(db,user,timezone=zone,am_minute=minute,pm_minute=minute,fold=fold)
    entry=db.get(RoutineEntry,"reminder-entry");entry.schedule="AM";db.commit()
    routine_reminders.generate(db,now=at,days=1)
    rows=[r for r in db.query(Notification) if notifications.utc(r.due_at).date()==at.date()]
    assert len(rows)==(1 if expected else 0)
    if expected:assert notifications.utc(rows[0].due_at).hour==expected


def test_cas_disable_cancel_and_unread(loop):
    client,db,user,foreign,_=loop
    configure(db,user)
    routine_reminders.generate(db,now=datetime(2026,10,1,8,tzinfo=timezone.utc),days=1)
    notice=db.query(Notification).first()
    assert client.put(ROOT+f"/{notice.id}/read",headers=auth(user)).status_code==200
    assert client.put(ROOT+f"/{notice.id}/unread",headers=auth(foreign)).status_code==404
    assert client.put(ROOT+f"/{notice.id}/unread",headers=auth(user)).json()["unread"] is True
    body=dict(expected_revision=0,enabled=False,timezone="UTC",am_minute=540,pm_minute=1260,fold=0,gap_policy="skip")
    assert client.put(ROOT+"/routine-reminders/reminder-entry",headers=auth(user),json=body).status_code==409
    body["expected_revision"]=1
    assert client.put(ROOT+"/routine-reminders/reminder-entry",headers=auth(user),json=body).status_code==200
    assert all(r.cancelled_at for r in db.query(Notification))
    assert client.put(ROOT+f"/{notice.id}/unread",headers=auth(user)).status_code==404
    assert client.get(ROOT+"/history",headers=auth(user)).json()["items"][0]["state"]=="cancelled"


def test_revoked_consent_never_reenables_old_schedule(loop):
    _,db,user,_,_=loop
    configure(db,user)
    notifications.change_preferences(db,user,PreferencesIn(expected_revision=1,enabled_kinds=[],push_enabled=False,
        timezone="UTC",quiet_start=0,quiet_end=0))
    notifications.change_preferences(db,user,PreferencesIn(expected_revision=2,enabled_kinds=["routine"],push_enabled=False,
        timezone="UTC",quiet_start=0,quiet_end=0))
    assert db.query(RoutineReminderSetting).one().enabled is False
    assert routine_reminders.generate(db)["occurrences_created"]==0


def test_bounds_and_worker_no_invented_delivery(loop):
    from app.workers.notifications import cycle
    _,db,_,_,_=loop
    factory=sessionmaker(bind=db.get_bind())
    assert cycle(factory)["delivery_confirmed"] is False
    with pytest.raises(ValueError):routine_reminders.generate(db,days=8)
    with pytest.raises(ValueError):cycle(factory,max_jobs=1001)


def test_pg_concurrent_generation_and_rollback(pg_engine):
    factory=seed(pg_engine)
    with factory() as db:configure(db,db.get(User,"owner"))
    barrier=Barrier(2)
    def run(_):
        with factory() as db:
            barrier.wait(timeout=5)
            return routine_reminders.generate(db,now=datetime(2026,10,15,8,tzinfo=timezone.utc))["occurrences_created"]
    with ThreadPoolExecutor(2) as pool:counts=list(pool.map(run,range(2)))
    assert sorted(counts)==[0,4]
    with factory() as db:
        assert db.query(Notification).count()==4
        entry=db.get(RoutineEntry,"reminder-entry");entry.active=False;entry.end_date=date(2026,10,15)
        db.flush();db.rollback()
        assert all(notifications.source_active(db,row,datetime.now(timezone.utc)) for row in db.query(Notification))


def test_logout_atomically_fences_device_jobs(loop):
    from tests.test_notifications import setup_delivery,TOKEN
    from app.core.security import create_access_token
    from app.models.notifications import NotificationDevice
    client,db,_,_,doctors=loop
    device,_=setup_delivery(loop)
    # Use the registered device session as actual authenticated logout session.
    token=create_access_token(doctors[0].id,"doctor",hashed_password=doctors[0].hashed_password)
    import jwt
    from app.core.config import settings
    claims=jwt.decode(token,settings.SECRET_KEY,algorithms=[settings.ALGORITHM])
    db.get(NotificationDevice,device["id"]).session_id=claims["jti"];db.commit()
    lease=notifications.claim(db)
    assert lease and "id" in lease
    response=client.post("/api/v1/auth/logout",headers={"Authorization":"Bearer "+token})
    assert response.status_code==204
    assert db.get(NotificationDevice,device["id"]).token_encrypted==""
    assert db.query(NotificationJob).one().state=="cancelled"
    assert not notifications.finish(db,lease["id"],lease["lease_token"],"accepted")


def test_pg_setting_deleted_while_generator_waits_is_skipped(pg_engine):
    from tests.test_postgres_gate import observe_lock_wait
    factory=seed(pg_engine)
    with factory() as db:configure(db,db.get(User,"owner"))
    with factory() as deleting:
        deleting.query(User).filter_by(id="owner").with_for_update().one()
        def generate_waiting():
            with factory() as worker:
                return routine_reminders.generate(worker,now=datetime(2026,10,15,8,tzinfo=timezone.utc))
        with ThreadPoolExecutor(1) as pool:
            result=pool.submit(generate_waiting)
            observe_lock_wait(pg_engine)
            deleting.query(RoutineReminderSetting).delete(synchronize_session=False)
            deleting.commit()
            assert result.result(timeout=5)["occurrences_created"]==0
    with factory() as db:assert db.query(Notification).count()==0


def test_pg_preloaded_preferences_and_settings_do_not_bypass_cas(pg_engine):
    from fastapi import HTTPException
    factory=seed(pg_engine)
    with factory() as db:configure(db,db.get(User,"owner"))
    with factory() as stale, factory() as writer:
        stale_pref=notifications.preferences(stale,"owner")
        stale_setting=stale.query(RoutineReminderSetting).one()
        notifications.change_preferences(writer,writer.get(User,"owner"),PreferencesIn(expected_revision=1,
            enabled_kinds=["routine"],push_enabled=False,timezone="Africa/Cairo",quiet_start=0,quiet_end=0))
        with pytest.raises(HTTPException) as error:
            notifications.change_preferences(stale,stale.get(User,"owner"),PreferencesIn(expected_revision=1,
                enabled_kinds=[],push_enabled=False,timezone="UTC",quiet_start=0,quiet_end=0))
        assert error.value.status_code==409
        stale.rollback()
        body=dict(expected_revision=1,enabled=True,timezone="Africa/Cairo",am_minute=540,pm_minute=1260,fold=1,gap_policy="skip")
        routine_reminders.configure(writer,writer.get(User,"owner"),"reminder-entry",RoutineReminderIn(**body))
        with pytest.raises(HTTPException) as error:
            routine_reminders.configure(stale,stale.get(User,"owner"),"reminder-entry",RoutineReminderIn(**body))
        assert error.value.status_code==409
        stale.rollback()


def test_durable_attempt_history_retry_unknown_and_acceptance(loop):
    from tests.test_notifications import setup_delivery
    from app.models.notifications import NotificationJobAttempt
    _,db,_,_,_=loop
    setup_delivery(loop)
    at=datetime.now(timezone.utc)
    first=notifications.claim(db,at)
    assert notifications.attempt_history(db,db.get(NotificationJob,first["id"]),at)[0]["state"]=="leased"
    second=notifications.claim(db,at+timedelta(seconds=61))
    assert db.query(NotificationJobAttempt).filter_by(state="unknown").count()==1
    assert not notifications.finish(db,first["id"],first["lease_token"],"accepted",at+timedelta(seconds=62))
    assert notifications.finish(db,second["id"],second["lease_token"],"retry",at+timedelta(seconds=62))
    third=notifications.claim(db,at+timedelta(seconds=200))
    assert notifications.finish(db,third["id"],third["lease_token"],"accepted",at+timedelta(seconds=201))
    history=notifications.attempt_history(db,db.get(NotificationJob,first["id"]),at+timedelta(seconds=202))
    assert [item["state"] for item in history]==["unknown","retry","provider_accepted"]
    assert all(not item["delivery_confirmed"] for item in history)


@pytest.mark.parametrize("who",["patient","doctor"])
def test_attempt_history_erased_bilaterally(loop,monkeypatch,who):
    from unittest.mock import Mock
    from tests.test_notifications import setup_delivery
    from app.models.notifications import NotificationJobAttempt
    from app.services.account_deletion import delete_account
    from app.services.deletion_journal import deletion_journal
    from app.services.azure_blob import azure_blob_service
    _,db,patient,_,doctors=loop
    setup_delivery(loop);notifications.dispatch_one(db)
    assert db.query(NotificationJobAttempt).count()==1
    monkeypatch.setattr(deletion_journal,"record",Mock())
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    delete_account(db,patient.id if who=="patient" else doctors[0].id)
    assert db.query(NotificationJobAttempt).count()==0
