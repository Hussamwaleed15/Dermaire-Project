from datetime import datetime,timezone
from fastapi import APIRouter,Depends,Header,HTTPException,Response,Query
from sqlalchemy.orm import Session
from app.api.deps import require_role,get_token_payload
from app.core.database import get_db
from app.models import User
from app.models.agent_platform import AgentSession,AgentTurn,AgentAction
from app.schemas.agent_platform import SessionIn,RevisionIn,TurnIn,ActionIn,ConfirmAction,SubmitRequest,DecideRequest
from app.services import agent_platform as service
from app.api.v1.clinical_plans import key_of

router=APIRouter(prefix="/agent",tags=["Consented local agent foundations"])
patient=require_role(["patient"])


def private(response):response.headers["Cache-Control"]="no-store"


@router.get("/capabilities")
def capabilities(response: Response,actor: User=Depends(patient)):
    private(response)
    return {"schema_version":"agent-platform-1","model":service.DisabledAgentModel().respond(context=None,message=None),
        "provider_config":service.agent_provider_state()[0].model_dump(),
        "actions":["request_checkin","propose_followup","propose_routine_adjustment","mark_notification_read"],
        "action_effect":"confirmed_requests_or_allowlisted_nonclinical_action","medical_execution_enabled":False,
        "autonomous_agent":False,"max_tool_calls":8,"context_freshness_seconds":300}


@router.post("/sessions",status_code=201)
def create(payload: SessionIn,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),
           actor: User=Depends(patient),claims: dict=Depends(get_token_payload),db: Session=Depends(get_db)):
    private(response)
    return service.create(db,actor,claims,payload,key_of(keys))


@router.get("/sessions")
def sessions(response: Response,limit: int=Query(20,ge=1,le=100),before: str | None=None,
             actor: User=Depends(patient),db: Session=Depends(get_db)):
    """Discover active sessions for the current account and original login.

    This deliberately returns only recovery metadata, never stored private
    context or turns. Each discovered session still has its original login,
    credential, expiry and revocation checked before it is returned.
    """
    private(response)
    query=db.query(AgentSession).filter_by(user_id=actor.id)
    if before:
        anchor=query.filter(AgentSession.id==before).first()
        if not anchor:raise HTTPException(422,"Invalid agent session cursor")
        from sqlalchemy import or_,and_
        query=query.filter(or_(AgentSession.expires_at<anchor.expires_at,
            and_(AgentSession.expires_at==anchor.expires_at,AgentSession.id<anchor.id)))
    rows=query.order_by(AgentSession.expires_at.desc(),AgentSession.id.desc()).limit(limit+1).all()
    items=[]
    for row in rows[:limit]:
        try:service.authorize(db,actor,row.id)
        except HTTPException as error:
            if error.status_code not in (403,404):raise
            continue
        items.append(service.session_summary(row))
    return {"items":items,"limit":limit,"next_before":rows[limit-1].id if len(rows)>limit else None,
        "context_included":False,"turns_included":False}


@router.get("/sessions/{session_id}")
def detail(session_id: str,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    return service.session_out(service.authorize(db,actor,session_id))


@router.post("/sessions/{session_id}/context")
def refresh(session_id: str,payload: RevisionIn,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    return service.refresh(db,actor,session_id,payload)


@router.post("/sessions/{session_id}/turns",status_code=201)
def turn(session_id: str,payload: TurnIn,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    return service.turn(db,actor,session_id,payload,key_of(keys))


@router.get("/sessions/{session_id}/turns")
def turns(session_id: str,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response);service.authorize(db,actor,session_id)
    rows=db.query(AgentTurn).filter_by(session_id=session_id).order_by(AgentTurn.created_at,AgentTurn.id).limit(40).all()
    return {"items":[{"id":r.id,"message":r.body,"created_at":service.utc(r.created_at),"authority":"untrusted_user_text"} for r in rows],
        "model_status":"unavailable","generated_assistant_turns":[]}


@router.post("/sessions/{session_id}/actions/preview",status_code=201)
def preview(session_id: str,payload: ActionIn,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    return service.preview(db,actor,session_id,payload,key_of(keys))


@router.get("/sessions/{session_id}/actions")
def actions(session_id: str,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response);service.authorize(db,actor,session_id,"proposal_actions")
    return {"items":[service.action_out(r) for r in db.query(AgentAction).filter_by(session_id=session_id).order_by(AgentAction.previewed_at,AgentAction.id).limit(8)]}


@router.get("/sessions/{session_id}/action-attempts/{key}")
def action_attempt(session_id: str,key: str,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response);service.authorize(db,actor,session_id,"proposal_actions")
    identifier=service.attempt_id(session_id+":action",actor.id,key)
    row=db.get(AgentAction,identifier)
    return {"attempt_id":identifier,"status":"committed" if row else "unknown","result":service.action_out(row) if row else None}


@router.post("/sessions/{session_id}/actions/{action_id}/confirm")
def confirm(session_id: str,action_id: str,payload: ConfirmAction,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    return service.confirm(db,actor,session_id,action_id,payload)


@router.delete("/sessions/{session_id}")
def revoke(session_id: str,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    row=db.query(AgentSession).filter_by(id=session_id,user_id=actor.id).with_for_update().first()
    if not row:raise HTTPException(404,"Agent session not found")
    if not row.revoked_at:
        row.revoked_at=datetime.now(timezone.utc);row.context=None;row.scopes=[];row.revision+=1;row.context_digest="0"*64
        db.query(AgentTurn).filter_by(session_id=row.id).delete(synchronize_session=False)
        for action in db.query(AgentAction).filter_by(session_id=row.id):service.cancel_request_notices(db,action.id)
        db.query(AgentAction).filter_by(session_id=row.id).update({"state":"revoked","payload":{},"result":None,"payload_hash":"0"*64,"context_digest":"0"*64},synchronize_session=False)
        service.audit(db,actor,"AGENT_CONSENT_REVOKED",row);service.save(db)
    return {"id":row.id,"state":"revoked","memory_erased":True}

@router.post("/requests/{action_id}/submit")
def submit_request(action_id: str,payload: SubmitRequest,
                   response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    return service.submit_request(db,actor,action_id,payload)


@router.get("/requests")
def request_inbox(response: Response,limit: int=Query(50,ge=1,le=100),before: str | None=None,
                  actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    private(response)
    # JSON extraction works on SQLite legacy and PostgreSQL; never return another
    # doctor's request or bypass current consent on historical rows.
    query=db.query(AgentAction).filter(AgentAction.result["doctor_id"].as_string()==actor.id)
    if before:
        anchor=query.filter(AgentAction.id==before).first()
        if not anchor:raise HTTPException(422,"Invalid clinician request cursor")
        from sqlalchemy import or_,and_
        query=query.filter(or_(AgentAction.previewed_at<anchor.previewed_at,
            and_(AgentAction.previewed_at==anchor.previewed_at,AgentAction.id<anchor.id)))
    rows=query.order_by(AgentAction.previewed_at.desc(),AgentAction.id.desc()).limit(limit+1).all()
    authorized={}
    # Acquire shared patient locks consistently across doctors while keeping the
    # response in its documented newest-first order.
    for row in sorted(rows,key=lambda item:(item.user_id,item.id)):
        try:
            current=service.request_row(db,actor,row.id)
            authorized[row.id]={**service.action_out(current),"patient_ref":{
                "patient_id":current.user_id,"access_id":current.result["access_id"],
                "authority":"current_original_grant"}}
        except HTTPException as error:
            if error.status_code not in (403,404):raise
    return {"items":[authorized[row.id] for row in rows[:limit] if row.id in authorized],"limit":limit,
        "next_before":rows[limit-1].id if len(rows)>limit else None,
        "medical_execution_enabled":False,"notification_delivery":"unavailable"}


@router.post("/requests/{action_id}/decision")
def decide_request(action_id: str,payload: DecideRequest,
                   response: Response,actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    private(response)
    return service.decide_request(db,actor,action_id,payload)


@router.delete("/requests/{action_id}")
def withdraw_request(action_id: str,response: Response,actor: User=Depends(patient),db: Session=Depends(get_db)):
    private(response)
    row=db.query(AgentAction).filter_by(id=action_id,user_id=actor.id).with_for_update().first()
    if not row:raise HTTPException(404,"Clinician request not found")
    if row.state!="revoked":
        service.cancel_request_notices(db,row.id)
        row.state="revoked";row.payload={};row.result=None;row.revision+=1
        row.payload_hash="0"*64;row.context_digest="0"*64
        service.audit(db,actor,"AGENT_REQUEST_WITHDRAWN",db.get(AgentSession,row.session_id),action_id=row.id)
        service.save(db)
    return {"id":row.id,"state":"revoked","memory_erased":True}
