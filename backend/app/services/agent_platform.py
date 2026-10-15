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


class DisabledAgentModel:
    def respond(self, *, context, message):
        return {"schema_version":"agent-model-boundary-1","status":"unavailable","provider":None,
                "model_version":None,"invoked":False,"reason":"agent_model_not_integrated","response":None}


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
    session=db.query(AgentSession).filter_by(id=identifier,user_id=actor.id).with_for_update().first()
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
    fingerprint=digest(payload.model_dump())
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
    safety=evaluate_safety(db,actor,now())
    if safety.status=="urgent" and payload.kind!="request_checkin":
        raise HTTPException(409,"Urgent safety escalation requires clinician care; agent proposal blocked")
    row=AgentAction(id=action_id,session_id=session.id,user_id=actor.id,kind=payload.kind,state="preview",revision=1,
        payload=payload.model_dump(exclude={"expected_session_revision"}),payload_hash=fingerprint,
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
    if safety.status=="urgent" and row.kind!="request_checkin":raise HTTPException(409,"Urgent safety escalation requires clinician care")
    row.state="confirmed";row.revision+=1;row.confirmed_at=now()
    row.result={"request_id":row.id,"status":"self_tracking_request" if row.kind=="request_checkin" else "pending_clinician_review",
        "provenance":"user_confirmed_request","clinical_clearance":False,"medical_resources_modified":False,
        "notification_enqueued":False,"clinician_notified":False}
    audit(db,actor,"AGENT_REQUEST_CONFIRMED",session,action_id=row.id,kind=row.kind);save(db)
    return action_out(row)
