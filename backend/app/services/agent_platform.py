"""Consented local request broker. No autonomous medical actions or model calls."""
import hashlib
import json
from datetime import datetime,timezone,timedelta
from sqlalchemy import inspect
from fastapi import HTTPException
from app.core.security import credential_stamp
from app.models import User,AuditLog,Product,RoutineEntry,Experiment,CheckIn,DailyContext,RoutineAdherence,Capture,Measurement,ProductIntelligence,DoctorReviewAction,CaptureObservation
from app.models.agent_platform import AgentSession,AgentTurn,AgentAction
from app.services.context_builder import build_context
from app.services.safety import evaluate_safety
from app.services.temporal import utc
from app.services.messaging import attempt_id
from app.services.model_providers import agent_provider_state


class DisabledAgentModel:
    def respond(self, *, context, message):
        return agent_provider_state()[1].model_dump()


def now():return datetime.now(timezone.utc)


def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(",",":"),default=str,allow_nan=False).encode()).hexdigest()


def evidence_digest(db,user):
    # Bound the *entire* relevant row vector; refuse oversized contexts rather
    # than silently pretending omitted older rows cannot change an action.
    vector={"profile":{name:getattr(user,name) for name in ("skin_type","skin_concerns","profile_context","updated_at","safety_accepted_at","safety_policy_version")}}
    count=0
    for model in (Product,RoutineEntry,Experiment,CheckIn,DailyContext,RoutineAdherence,Capture,Measurement,ProductIntelligence,CaptureObservation,DoctorReviewAction):
        owner=model.patient_id if model is DoctorReviewAction else model.user_id
        rows=db.query(model).filter(owner==user.id).order_by(model.id).limit(5001-count).all()
        count+=len(rows)
        if count>5000:raise HTTPException(503,"Agent context exceeds the bounded evidence budget")
        # Values are hashed locally, never sent to a provider, stored as agent
        # memory or exposed in action logs. The actual retrieval uses the existing
        # redacted 240-fact / 24KB projection and its freshness labels.
        vector[model.__tablename__]=[{c.key:getattr(row,c.key) for c in inspect(model).columns} for row in rows]
    return digest(vector)


def audit(db,actor,action,session,**data):
    db.add(AuditLog(actor_id=actor.id,action=action,target_resource="agent_sessions",details={"session_id":session.id,**data}))


def save(db):
    try:db.commit()
    except Exception:
        db.rollback();raise HTTPException(503,"Agent operation unconfirmed; read back the original id/key") from None


def authorize(db,actor,identifier,scope="longitudinal_read"):
    session=db.query(AgentSession).filter_by(id=identifier,user_id=actor.id).populate_existing().with_for_update().first()
    if not session:raise HTTPException(404,"Agent session not found")
    if (actor.role!="patient" or session.revoked_at or utc(session.expires_at)<=now()
        or session.credential!=credential_stamp(actor.hashed_password)
        or db.query(AuditLog).filter_by(actor_id=actor.id,action="SESSION_REVOKED",target_resource=session.auth_session_id).first()
        or scope not in session.scopes):raise HTTPException(403,"Agent consent/session is no longer active")
    return session


def session_out(row):
    return {"id":row.id,"revision":row.revision,"expires_at":utc(row.expires_at),"scopes":row.scopes,
        "context_at":utc(row.context_at),"context_digest":row.context_digest,"context":row.context,
        "consistency":"owner_locked_multiple_reads_not_atomic_snapshot","tool_calls":row.tool_calls,"max_tool_calls":8,
        "model":DisabledAgentModel().respond(context=None,message=None),"medical_execution_enabled":False}


def create(db,actor,claims,payload,key):
    if actor.role!="patient" or payload.longitudinal_read_consent is not True:raise HTTPException(403,"Explicit patient retrieval consent required")
    identifier=attempt_id("agent-session",actor.id,key)
    existing=db.get(AgentSession,identifier)
    scopes=["longitudinal_read"]+(["proposal_actions"] if payload.proposal_actions_consent else [])
    if existing:
        authorize(db,actor,identifier)
        if existing.scopes!=scopes or existing.auth_session_id!=claims["jti"]:raise HTTPException(409,"Session key is bound to different consent/session")
        return session_out(existing)
    at=now()
    if db.query(AgentSession).filter(AgentSession.user_id==actor.id,AgentSession.revoked_at.is_(None),AgentSession.expires_at>at).count()>=5:
        raise HTTPException(409,"Active agent session limit reached; revoke an existing session")
    row=AgentSession(id=identifier,user_id=actor.id,auth_session_id=claims["jti"],credential=credential_stamp(actor.hashed_password),
        expires_at=min(at+timedelta(hours=1),datetime.fromtimestamp(claims["exp"],timezone.utc)),revision=1,scopes=scopes,
        context=build_context(db,actor,now=at).model_dump(mode="json"),context_digest=evidence_digest(db,actor),context_at=at,tool_calls=1)
    db.add(row);audit(db,actor,"AGENT_CONSENT_GRANTED",row,consent_version=1,scopes=scopes);save(db)
    return session_out(row)


def refresh(db,actor,identifier,payload):
    row=authorize(db,actor,identifier)
    if row.revision!=payload.expected_revision:raise HTTPException(409,"Agent session revision changed")
    if row.tool_calls>=8:raise HTTPException(409,"Session tool budget exhausted; start a new consented session")
    at=now();row.context=build_context(db,actor,now=at).model_dump(mode="json")
    row.context_digest=evidence_digest(db,actor);row.context_at=at;row.revision+=1;row.tool_calls+=1
    audit(db,actor,"AGENT_CONTEXT_REFRESHED",row,revision=row.revision);save(db)
    return session_out(row)


def turn(db,actor,identifier,payload,key):
    row=authorize(db,actor,identifier)
    turn_id=attempt_id(identifier,actor.id,key)
    previous=db.get(AgentTurn,turn_id)
    if previous:
        if previous.body!=payload.message:raise HTTPException(409,"Turn key belongs to a different message")
    else:
        if db.query(AgentTurn).filter_by(session_id=row.id).count()>=40:raise HTTPException(409,"Conversation turn budget exhausted")
        db.add(AgentTurn(id=turn_id,session_id=row.id,body=payload.message))
        audit(db,actor,"AGENT_TURN_RECORDED",row,turn_id=turn_id);save(db)
    # Untrusted text is data only. It cannot select or invoke a tool, infer
    # authority, change consent, or become a generated clinical response.
    return {"id":turn_id,"model":DisabledAgentModel().respond(context=None,message=None),"actions_executed":0}


def action_out(row):
    return {"id":row.id,"kind":row.kind,"state":row.state,"revision":row.revision,"payload":row.payload,
        "previewed_at":utc(row.previewed_at),"confirmed_at":utc(row.confirmed_at) if row.confirmed_at else None,
        "preview_valid_until":utc(row.previewed_at)+timedelta(minutes=5),
        "result":row.result,"requires_explicit_confirmation":row.state=="preview","medical_change":False}


def preview(db,actor,identifier,payload,key):
    session=authorize(db,actor,identifier,"proposal_actions")
    action_id=attempt_id(identifier+":action",actor.id,key)
    previous=db.get(AgentAction,action_id)
    # Preserve pre-extension receipt hashes for existing action kinds.
    optional_fields={"notification_id"} if payload.notification_id is None else set()
    fingerprint=digest(payload.model_dump(exclude=optional_fields))
    if previous:
        if previous.payload_hash!=fingerprint:raise HTTPException(409,"Action key belongs to a different preview")
        return action_out(previous)
    if payload.expected_session_revision!=session.revision:raise HTTPException(409,"Agent session revision changed")
    if session.tool_calls>=8:raise HTTPException(409,"Session tool budget exhausted")
    if utc(session.context_at)+timedelta(minutes=5)<=now() or evidence_digest(db,actor)!=session.context_digest:
        raise HTTPException(409,"Agent context is stale; refresh before preview")
    if payload.kind=="propose_routine_adjustment":
        routine=db.query(RoutineEntry).filter_by(id=payload.routine_id,user_id=actor.id,active=True).first()
        if not routine:raise HTTPException(404,"Owned active routine required")
        if routine.revision!=payload.routine_revision:raise HTTPException(409,"Routine revision changed")
    if payload.kind=="mark_notification_read":
        unread_notification(db,actor,payload.notification_id)
    safety=evaluate_safety(db,actor,now())
    if safety.status=="urgent" and payload.kind not in ("request_checkin","mark_notification_read"):
        raise HTTPException(409,"Urgent safety escalation requires clinician care; agent proposal blocked")
    row=AgentAction(id=action_id,session_id=session.id,user_id=actor.id,kind=payload.kind,state="preview",revision=1,
        payload=payload.model_dump(exclude={"expected_session_revision"}|optional_fields),payload_hash=fingerprint,
        context_digest=session.context_digest,previewed_at=now())
    db.add(row);session.tool_calls+=1
    audit(db,actor,"AGENT_ACTION_PREVIEWED",session,action_id=row.id,kind=row.kind);save(db)
    return action_out(row)


def confirm(db,actor,identifier,action_id,payload):
    session=authorize(db,actor,identifier,"proposal_actions")
    row=db.query(AgentAction).filter_by(id=action_id,session_id=session.id,user_id=actor.id).with_for_update().first()
    if not row:raise HTTPException(404,"Agent action not found")
    if payload.confirm is not True:raise HTTPException(403,"Explicit user confirmation required")
    if row.state=="confirmed":
        if payload.expected_revision!=1:raise HTTPException(409,"Confirmation revision changed")
        return action_out(row)
    if row.state!="preview" or payload.expected_revision!=row.revision:raise HTTPException(409,"Action revision changed")
    if utc(row.previewed_at)+timedelta(minutes=5)<=now() or evidence_digest(db,actor)!=row.context_digest:
        raise HTTPException(409,"Preview evidence is stale; prepare a new preview")
    safety=evaluate_safety(db,actor,now())
    if safety.status=="urgent" and row.kind not in ("request_checkin","mark_notification_read"):raise HTTPException(409,"Urgent safety escalation requires clinician care")
    notice=unread_notification(db,actor,row.payload["notification_id"],locked=True) if row.kind=="mark_notification_read" else None
    row.state="confirmed";row.revision+=1;row.confirmed_at=now()
    row.result={"request_id":row.id,"status":"self_tracking_request" if row.kind=="request_checkin" else "pending_clinician_review",
        "provenance":"user_confirmed_request","clinical_clearance":False,"medical_resources_modified":False,
        "notification_enqueued":False,"clinician_notified":False}
    if row.kind=="mark_notification_read":
        notice.read_at=now()
        row.result={**row.result,"status":"executed","tool":"mark_notification_read","notification_id":notice.id,"read_at":notice.read_at.isoformat(),"provenance":"user_confirmed_nonclinical_action"}
    audit(db,actor,"AGENT_REQUEST_CONFIRMED",session,action_id=row.id,kind=row.kind);save(db)
    return action_out(row)

# Clinician requests are explicitly submitted by the patient. They never mutate
# treatment and are fenced by the original grant, auth session and one-hour TTL.
def request_row(db, actor, identifier):
    from app.services.messaging import current_grant
    row=db.get(AgentAction,identifier)
    if not row or not row.result or actor.id not in (row.user_id,row.result.get("doctor_id")):
        raise HTTPException(404,"Clinician request not found")
    lock_request_doctor(db,row.result["doctor_id"])
    grant=current_grant(db,actor,row.result["access_id"])
    if (grant.patient_id,grant.doctor_id)!=(row.user_id,row.result["doctor_id"]):
        raise HTTPException(403,"Original request grant changed")
    session=db.get(AgentSession,row.session_id)
    patient=db.get(User,row.user_id)
    authorize(db,patient,session.id,"proposal_actions")
    row=db.query(AgentAction).filter_by(id=identifier).populate_existing().with_for_update().first()
    if not row or row.state!="confirmed" or not row.result or row.result.get("access_id")!=grant.id or row.result.get("doctor_id")!=grant.doctor_id:
        raise HTTPException(404,"Clinician request no longer active")
    return row


def submit_request(db,actor,identifier,payload):
    from app.services.messaging import current_grant
    row=db.query(AgentAction).filter_by(id=identifier,user_id=actor.id).first()
    if not row:raise HTTPException(404,"Agent action not found")
    from app.models import DoctorPatientAccess
    selected_grant=db.query(DoctorPatientAccess).filter_by(id=payload.access_id,patient_id=actor.id).first()
    if not selected_grant:raise HTTPException(404,"Clinician grant not found")
    lock_request_doctor(db,selected_grant.doctor_id,nowait=True)
    grant=current_grant(db,actor,payload.access_id)
    session=authorize(db,actor,row.session_id,"proposal_actions")
    row=db.query(AgentAction).filter_by(id=identifier).populate_existing().with_for_update().one()
    if payload.clinician_request_consent is not True:raise HTTPException(403,"Explicit clinician request consent required")
    if row.result and row.result.get("access_id"):
        if row.result["access_id"]!=payload.access_id or payload.expected_revision!=2:
            raise HTTPException(409,"Submission already bound to another grant or revision")
        return action_out(row)
    if row.state!="confirmed" or row.kind in ("request_checkin","mark_notification_read") or row.revision!=payload.expected_revision:
        raise HTTPException(409,"Confirmed clinician-directed proposal and current revision required")
    if evaluate_safety(db,actor,now()).status=="urgent":raise HTTPException(409,"Urgent safety escalation requires clinician care")
    row.result={**row.result,"status":"pending_clinician_review","access_id":grant.id,"doctor_id":grant.doctor_id,
        "consent_version":1,"submitted_at":now().isoformat(),"expires_at":utc(session.expires_at).isoformat(),
        "decision":None,"notification_enqueued":False,"clinician_notified":False}
    row.revision+=1
    notify_request(db,row,grant.doctor_id)
    audit(db,actor,"AGENT_CLINICIAN_REQUEST_SUBMITTED",session,action_id=row.id,doctor_id=grant.doctor_id)
    save(db)
    return action_out(row)


def decide_request(db,actor,identifier,payload):
    if actor.role!="doctor":raise HTTPException(403,"Clinician authority required")
    row=request_row(db,actor,identifier)
    result=row.result
    if result["doctor_id"]!=actor.id:raise HTTPException(404,"Clinician request not found")
    if result.get("decision")==payload.decision and result.get("decision_base_revision")==payload.expected_revision:
        return action_out(row)
    if row.revision!=payload.expected_revision:raise HTTPException(409,"Request revision changed")
    allowed={"pending_clinician_review":{"accepted","rejected"},"accepted":{"reviewed"}}
    if payload.decision not in allowed.get(result["status"],set()):raise HTTPException(409,"Invalid clinician request transition")
    row.result={**result,"status":payload.decision,"decision":payload.decision,
        "decision_base_revision":payload.expected_revision,"decided_at":now().isoformat(),
        "clinical_clearance":False,"medical_resources_modified":False}
    row.revision+=1
    notify_request(db,row,row.user_id)
    audit(db,actor,"AGENT_CLINICIAN_REQUEST_DECIDED",db.get(AgentSession,row.session_id),action_id=row.id,decision=payload.decision)
    save(db)
    return action_out(row)


def unread_notification(db,actor,identifier,locked=False):
    from app.models.notifications import Notification
    query=db.query(Notification).filter_by(id=identifier,user_id=actor.id)
    if locked:query=query.populate_existing().with_for_update()
    notice=query.first()
    if not notice:raise HTTPException(404,"Owned notification required")
    from app.services.notifications import source_active
    if notice.cancelled_at or utc(notice.due_at)>now() or notice.read_at is not None or not source_active(db,notice,now()):
        raise HTTPException(409,"Notification no longer matches unread preview")
    return notice


def request_notice_active(db,notice,at):
    from app.models import DoctorPatientAccess
    from app.services.doctor_consent import granted_scopes
    row=db.get(AgentAction,notice.source_id)
    if not row or row.state!="confirmed" or row.revision!=notice.source_revision or not row.result:return False
    result=row.result
    if notice.user_id not in (row.user_id,result.get("doctor_id")):return False
    session=db.get(AgentSession,row.session_id)
    patient=db.get(User,row.user_id)
    doctor=db.get(User,result.get("doctor_id"))
    grant=db.get(DoctorPatientAccess,result.get("access_id"))
    return bool(session and patient and doctor and doctor.role=="doctor" and not session.revoked_at and utc(session.expires_at)>at
        and session.credential==credential_stamp(patient.hashed_password) and "proposal_actions" in session.scopes
        and not db.query(AuditLog).filter_by(actor_id=patient.id,action="SESSION_REVOKED",target_resource=session.auth_session_id).first()
        and grant and grant.status=="active" and utc(grant.expires_at)>at and "VIEW" in granted_scopes(grant)
        and (grant.patient_id,grant.doctor_id)==(row.user_id,doctor.id))


def cancel_request_notices(db,identifier):
    from app.models.notifications import Notification
    from app.services.notifications import cancel
    for notice in db.query(Notification).filter_by(kind="agent_request",source_id=identifier,cancelled_at=None):cancel(db,notice)


def notify_request(db,row,recipient):
    from app.services.notifications import enqueue
    cancel_request_notices(db,row.id)
    notice=enqueue(db,recipient,"agent_request",row.id,row.revision,now())
    row.result={**row.result,"notification_enqueued":notice is not None,"clinician_notified":False}


def expire_requests(db,limit=100):
    """Bounded local memory cleanup; TTL is enforced before cleanup as well."""
    sessions=db.query(AgentSession).filter(AgentSession.expires_at<=now(),AgentSession.revoked_at.is_(None)).order_by(AgentSession.expires_at,AgentSession.id).limit(min(max(limit,1),100)).with_for_update(skip_locked=True).all()
    for session in sessions:
        session.revoked_at=now();session.context=None;session.scopes=[];session.context_digest="0"*64;session.revision+=1
        db.query(AgentTurn).filter_by(session_id=session.id).delete(synchronize_session=False)
        for action in db.query(AgentAction).filter_by(session_id=session.id).with_for_update():
            cancel_request_notices(db,action.id)
            action.state="revoked";action.payload={};action.result=None;action.payload_hash="0"*64;action.context_digest="0"*64;action.revision+=1
        actor=db.get(User,session.user_id)
        if actor:audit(db,actor,"AGENT_SESSION_EXPIRED",session)
    save(db)
    return {"expired_sessions":len(sessions),"limit":min(max(limit,1),100)}


def lock_request_doctor(db,identifier,nowait=False):
    # Auth may already hold the patient row. Patient submission uses NOWAIT
    # to avoid inversion with doctor-authenticated writes/deletion. Doctor flows
    # hold doctor before patient. The doctor row fences deletion JSON snapshots.
    from sqlalchemy.exc import OperationalError
    try:
        doctor=db.query(User).filter_by(id=identifier,role="doctor").populate_existing().with_for_update(nowait=nowait).first()
    except OperationalError as error:
        db.rollback()
        if getattr(error.orig,"sqlstate",None)=="55P03":
            raise HTTPException(409,"Clinician account is busy; retry original submission after reconciliation") from None
        raise
    if not doctor:raise HTTPException(403,"Original clinician account is unavailable")
    return doctor
