"""Transactional inbox and leased local outbox. No configured live provider."""
import base64
import hashlib
import json
from datetime import datetime, timezone, timedelta
from uuid import uuid4, uuid5, NAMESPACE_URL
from cryptography.fernet import Fernet
from cryptography.fernet import InvalidToken
from sqlalchemy.exc import IntegrityError
from fastapi import HTTPException
from sqlalchemy import or_
from app.core.config import settings
from app.core.security import credential_stamp
from app.models import User, AuditLog
from app.models.notifications import NotificationPreference, NotificationDevice, Notification, NotificationJob, NotificationJobAttempt
from app.services.temporal import utc
from app.services.wall_time import quiet_at


class DisabledPushProvider:
    name = "disabled"
    def send(self, *, token, payload, idempotency_key):
        return "unavailable"


def attempt_history(db, job, now):
    rows=db.query(NotificationJobAttempt).filter_by(job_id=job.id).order_by(NotificationJobAttempt.number,NotificationJobAttempt.id).all()
    result=[]
    for row in rows:
        ambiguous=row.state=="leased" and (job.state!="leased" or not job.lease_until or utc(job.lease_until)<=now)
        result.append({"id":row.id,"number":row.number,"state":"unknown" if ambiguous else row.state,
            "started_at":utc(row.started_at),"finished_at":utc(row.finished_at) if row.finished_at else None,
            "authorization_cancelled":job.state=="cancelled","delivery_confirmed":False})
    return result


def cipher():
    return Fernet(base64.urlsafe_b64encode(hashlib.sha256((settings.SECRET_KEY+":notification-device-v1").encode()).digest()))


def preferences(db, owner):
    return db.query(NotificationPreference).filter_by(user_id=owner).first()


def preference_out(row):
    return {"revision": row.revision if row else 0,
            "enabled_kinds": row.enabled_kinds if row else [], "push_enabled": row.push_enabled if row else False,
            "timezone": row.timezone if row else "UTC", "quiet_start": row.quiet_start if row else 0,
            "quiet_end": row.quiet_end if row else 0, "provider": "disabled", "actual_delivery": "unavailable"}


def change_preferences(db, actor, payload):
    db.query(User).filter_by(id=actor.id).with_for_update().one()
    row=db.query(NotificationPreference).filter_by(user_id=actor.id).populate_existing().first()
    if payload.expected_revision != (row.revision if row else 0):
        raise HTTPException(409,"Notification preferences changed; refresh revision")
    if row is None:
        row=NotificationPreference(user_id=actor.id,revision=0); db.add(row)
    for key,value in payload.model_dump(exclude={"expected_revision"}).items(): setattr(row,key,value)
    row.revision += 1
    if "routine" not in row.enabled_kinds:
        from app.models.notifications import RoutineReminderSetting
        db.query(RoutineReminderSetting).filter_by(user_id=actor.id,enabled=True).update(
            {"enabled":False,"revision":RoutineReminderSetting.revision+1},synchronize_session=False)
    # Revocation cancels outstanding effects atomically. Re-enabling never revives them.
    notices=db.query(Notification).filter_by(user_id=actor.id,cancelled_at=None).all()
    for notice in notices:
        if notice.kind not in row.enabled_kinds: cancel(db,notice)
    if not row.push_enabled:
        ids=[n.id for n in notices]
        db.query(NotificationJob).filter(NotificationJob.notification_id.in_(ids),NotificationJob.state != "provider_accepted").update(
            {"state":"cancelled","lease_token":None,"lease_until":None},synchronize_session=False)
    db.commit()
    return preference_out(row)


def register(db, actor, claims, payload):
    if payload.push_consent is not True: raise HTTPException(403,"Explicit push consent required")
    pref=preferences(db,actor.id)
    if not pref or not pref.push_enabled: raise HTTPException(403,"Push preferences are disabled")
    identifier=str(uuid5(NAMESPACE_URL,json.dumps(["device-v1",actor.id,claims["jti"],payload.installation_id])))
    digest=hashlib.sha256(payload.token.encode()).hexdigest()
    other=db.query(NotificationDevice).filter(NotificationDevice.token_hash==digest,NotificationDevice.id!=identifier).with_for_update().first()
    if other:
        if device_active(db,other,datetime.now(timezone.utc)):
            raise HTTPException(409,"Token already registered to an active session; revoke it before switching")
        other.revoked_at=datetime.now(timezone.utc); other.token_encrypted=""
        other.token_hash=hashlib.sha256(("revoked:"+other.id).encode()).hexdigest()
        db.flush()
    row=db.get(NotificationDevice,identifier)
    if row is None:
        row=NotificationDevice(id=identifier,user_id=actor.id); db.add(row)
    row.session_id=claims["jti"]; row.credential=credential_stamp(actor.hashed_password)
    row.session_expires_at=datetime.fromtimestamp(claims["exp"],timezone.utc)
    row.token_hash=digest; row.token_encrypted=cipher().encrypt(payload.token.encode()).decode()
    row.platform=payload.platform; row.revoked_at=None
    try:
        db.flush()
        at=datetime.now(timezone.utc)
        for notice in db.query(Notification).filter(Notification.user_id==actor.id,Notification.cancelled_at.is_(None),Notification.due_at>at):
            if notice.kind not in pref.enabled_kinds or not source_active(db,notice,at):continue
            job=db.query(NotificationJob).filter_by(notification_id=notice.id,device_id=row.id).first()
            if job is None:db.add(NotificationJob(notification_id=notice.id,device_id=row.id,available_at=notice.due_at))
            elif job.state=="cancelled":
                job.state="queued";job.available_at=notice.due_at;job.lease_token=None;job.lease_until=None
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409,"Device registration changed concurrently; refresh and retry") from None
    return {"id":row.id,"platform":row.platform,"status":"registered","provider":"disabled"}


def enqueue(db, owner, kind, source, revision, due_at):
    """Call inside the domain transaction; does not commit or promise push delivery."""
    if kind not in ("message","follow_up","comparison","routine","agent_request"): raise ValueError("Unknown notification kind")
    pref=preferences(db,owner)
    if not pref or kind not in pref.enabled_kinds: return None
    identifier=str(uuid5(NAMESPACE_URL,json.dumps(["notification-v1",owner,kind,source,revision])))
    row=db.get(Notification,identifier)
    if row: return row
    row=Notification(id=identifier,user_id=owner,kind=kind,source_id=source,source_revision=revision,due_at=due_at)
    db.add(row); db.flush()
    if pref.push_enabled:
        for device in db.query(NotificationDevice).filter_by(user_id=owner,revoked_at=None):
            db.add(NotificationJob(notification_id=row.id,device_id=device.id,available_at=due_at))
    return row


def cancel(db, notice):
    notice.cancelled_at=datetime.now(timezone.utc)
    db.query(NotificationJob).filter(NotificationJob.notification_id==notice.id,NotificationJob.state != "provider_accepted").update(
        {"state":"cancelled","lease_token":None,"lease_until":None},synchronize_session=False)


def device_active(db, device, now):
    user=db.get(User,device.user_id)
    return (user is not None and device.revoked_at is None and utc(device.session_expires_at)>now
        and device.credential == credential_stamp(user.hashed_password)
        and not db.query(AuditLog).filter_by(actor_id=device.user_id,action="SESSION_REVOKED",target_resource=device.session_id).first())


def source_active(db, notice, now):
    if notice.kind == "agent_request":
        from app.services.agent_platform import request_notice_active
        return request_notice_active(db,notice,now)
    if notice.kind == "routine":
        from app.models import RoutineEntry
        from app.models.notifications import RoutineReminderSetting
        entry=db.get(RoutineEntry,notice.source_id)
        valid = bool(entry and entry.user_id==notice.user_id and entry.active and entry.revision==notice.source_revision)
        if notice.reminder_id:
            setting=db.get(RoutineReminderSetting,notice.reminder_id)
            valid = valid and bool(setting and setting.enabled and setting.user_id==notice.user_id
                and setting.routine_entry_id==notice.source_id and setting.revision==notice.reminder_revision)
        return valid
    if notice.kind in ("follow_up","comparison"):
        from app.models.clinical_plans import ClinicalPlan
        from app.models import DoctorPatientAccess
        from app.services.doctor_consent import granted_scopes
        plan=db.get(ClinicalPlan,notice.source_id)
        grant=db.get(DoctorPatientAccess,plan.access_id) if plan else None
        doctor=db.get(User,plan.doctor_id) if plan else None
        return bool(plan and plan.user_id==notice.user_id and plan.state=="scheduled" and plan.revision==notice.source_revision
            and grant and grant.status=="active" and utc(grant.expires_at)>now and "VIEW" in granted_scopes(grant)
            and (grant.patient_id,grant.doctor_id)==(plan.user_id,plan.doctor_id) and doctor and doctor.role=="doctor")
    if notice.kind != "message": return False
    from app.models.messaging import ThreadMessage, MessageThread
    from app.models import DoctorPatientAccess
    from app.services.doctor_consent import granted_scopes
    message=db.get(ThreadMessage,notice.source_id)
    thread=db.get(MessageThread,message.thread_id) if message else None
    grant=db.get(DoctorPatientAccess,thread.access_id) if thread else None
    doctor=db.get(User,thread.doctor_id) if thread else None
    return bool(thread and not thread.closed_at and grant and grant.status=="active"
        and utc(grant.expires_at)>now and doctor and doctor.role=="doctor"
        and (grant.patient_id,grant.doctor_id)==(thread.patient_id,thread.doctor_id)
        and notice.user_id in (thread.patient_id,thread.doctor_id) and "VIEW" in granted_scopes(grant))


def claim(db, now=None):
    now=now or datetime.now(timezone.utc)
    row=db.query(NotificationJob).filter(
        or_(NotificationJob.state.in_(["queued","retry","provider_unavailable"]),
            (NotificationJob.state=="leased") & (NotificationJob.lease_until<=now)),
        NotificationJob.available_at<=now).order_by(NotificationJob.available_at,NotificationJob.id).populate_existing().with_for_update(skip_locked=True).first()
    if row is None: return None
    notice=db.get(Notification,row.notification_id); device=db.get(NotificationDevice,row.device_id)
    pref=preferences(db,notice.user_id)
    if (notice.cancelled_at or not source_active(db,notice,now) or not pref or not pref.push_enabled or notice.kind not in pref.enabled_kinds
            or not device_active(db,device,now)
            or (notice.reminder_id is not None and utc(notice.due_at)+timedelta(hours=24)<=now)):
        row.state="cancelled"; row.lease_token=None; row.lease_until=None; db.commit()
        return {"state":"cancelled"}
    if quiet_at(now,pref.timezone,pref.quiet_start,pref.quiet_end):
        row.state="retry"; row.available_at=now+timedelta(minutes=5); db.commit()
        return {"state":"quiet_hours"}
    # A crashed/expired lease cannot prove whether transport ran or was accepted.
    db.query(NotificationJobAttempt).filter_by(job_id=row.id,state="leased").update(
        {"state":"unknown","finished_at":now},synchronize_session=False)
    row.state="leased"; row.lease_token=str(uuid4()); row.lease_until=now+timedelta(seconds=60); row.attempts+=1
    try: token=cipher().decrypt(device.token_encrypted.encode()).decode()
    except InvalidToken:
        device.revoked_at=now; device.token_encrypted=""; row.state="cancelled"
        row.lease_token=None; row.lease_until=None; db.commit()
        return {"state":"cancelled"}
    db.add(NotificationJobAttempt(id=str(uuid5(NAMESPACE_URL,"push-attempt:"+row.id+":"+row.lease_token)),
        job_id=row.id,number=row.attempts,state="leased",started_at=now))
    result={"id":row.id,"lease_token":row.lease_token,"token":token,
            "payload":{"title":"Dermaire","body":"You have an update"}}
    db.commit()
    return result


def finish(db, job_id, lease_token, outcome, now=None):
    if outcome not in ("unavailable","accepted","retry"): raise ValueError("Invalid provider outcome")
    now=now or datetime.now(timezone.utc)
    row=db.query(NotificationJob).filter_by(id=job_id,state="leased",lease_token=lease_token).populate_existing().with_for_update().first()
    if row is None or utc(row.lease_until)<=now: return False
    # Recheck revocation before recording an outcome. External transport cannot
    # be made atomic with DB revocation; no exactly-once delivery claim.
    device=db.get(NotificationDevice,row.device_id); notice=db.get(Notification,row.notification_id)
    pref=preferences(db,notice.user_id)
    if notice.cancelled_at or not source_active(db,notice,now) or not pref or not pref.push_enabled or notice.kind not in pref.enabled_kinds or not device_active(db,device,now):
        row.state="cancelled"
    else:
        row.state={"accepted":"provider_accepted","unavailable":"provider_unavailable","retry":"retry"}[outcome]
        row.available_at=now+timedelta(seconds=min(3600,30*2**min(row.attempts,7)))
    attempt=db.get(NotificationJobAttempt,str(uuid5(NAMESPACE_URL,"push-attempt:"+row.id+":"+lease_token)))
    if attempt:
        attempt.state=row.state if row.state!="cancelled" else "unknown"
        attempt.finished_at=now
    row.lease_token=None; row.lease_until=None; db.commit()
    return True


def dispatch_one(db, provider=None, now=None):
    lease=claim(db,now)
    if not lease or "id" not in lease: return lease
    try:
        outcome=(provider or DisabledPushProvider()).send(token=lease["token"],payload=lease["payload"],idempotency_key=lease["id"])
        if outcome not in ("unavailable","accepted","retry"): outcome="retry"
    except Exception:
        outcome="retry"  # Never log device token or provider response.
    finish(db,lease["id"],lease["lease_token"],outcome,now)
    return {"id":lease["id"],"provider_outcome":outcome,"delivery_confirmed":False}
