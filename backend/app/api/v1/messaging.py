from fastapi import APIRouter, Depends, Header, HTTPException, Query, Response
from sqlalchemy.orm import Session
from app.api.deps import require_role
from app.core.database import get_db
from app.models import User
from app.models.messaging import MessageThread, ThreadMessage
from app.schemas.messaging import OpenThread, SendMessage, ReadMessages
from app.services import messaging as service
from datetime import datetime, timezone

router = APIRouter(prefix="/messaging", tags=["Consented messaging"])
participant = require_role(["patient", "doctor"])


def private(response):
    response.headers["Cache-Control"] = "no-store"


@router.post("/threads", status_code=201)
def open_thread(payload: OpenThread, response: Response,
                actor: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    private(response)
    return service.open_thread(db, actor, payload)


@router.get("/threads")
def list_threads(response: Response, after: str | None = None, limit: int = Query(50, ge=1, le=100),
                 actor: User = Depends(participant), db: Session = Depends(get_db)):
    private(response)
    column = MessageThread.patient_id if actor.role == "patient" else MessageThread.doctor_id
    query = db.query(MessageThread).filter(column == actor.id)
    if after:
        anchor = db.query(MessageThread).filter(column == actor.id, MessageThread.id == after).first()
        if anchor is None: raise HTTPException(422, "Invalid thread cursor")
        from sqlalchemy import or_, and_
        query = query.filter(or_(MessageThread.created_at > anchor.created_at,
            and_(MessageThread.created_at == anchor.created_at, MessageThread.id > anchor.id)))
    rows = query.order_by(MessageThread.created_at, MessageThread.id).limit(limit + 1).all()
    result = []
    for row in rows[:limit]:
        try:
            result.append(service.thread_out(service.authorize(db, actor, row.id)))
        except HTTPException as error:
            if error.status_code not in (403, 404): raise
    return {"items": result, "next_after": rows[limit-1].id if len(rows) > limit else None}


@router.post("/threads/{thread_id}/messages", status_code=201)
def send(thread_id: str, payload: SendMessage, response: Response,
         keys: list[str] | None = Header(None, alias="Idempotency-Key"),
         actor: User = Depends(participant), db: Session = Depends(get_db)):
    if not keys or len(keys) != 1: raise HTTPException(422, "One Idempotency-Key required")
    private(response)
    result = service.send(db, actor, thread_id, payload, keys[0])
    response.headers["Operation-Attempt-Id"] = result["id"]
    return result


@router.get("/threads/{thread_id}/attempts/{key}")
def attempt(thread_id: str, key: str, response: Response,
            actor: User = Depends(participant), db: Session = Depends(get_db)):
    private(response)
    return service.read_attempt(db, actor, thread_id, key)


@router.get("/threads/{thread_id}/messages")
def messages(thread_id: str, response: Response, after: int = Query(0, ge=0),
             as_of: int | None = Query(None, ge=0), limit: int = Query(50, ge=1, le=100),
             actor: User = Depends(participant), db: Session = Depends(get_db)):
    private(response)
    thread = service.authorize(db, actor, thread_id)
    high = thread.next_sequence - 1 if as_of is None else as_of
    if high >= thread.next_sequence or after > high:
        raise HTTPException(422, "Invalid conversation cursor")
    rows = db.query(ThreadMessage).filter(ThreadMessage.thread_id == thread.id,
        ThreadMessage.sequence > after, ThreadMessage.sequence <= high).order_by(ThreadMessage.sequence).limit(limit + 1).all()
    return {"items": [service.message_out(row) for row in rows[:limit]], "as_of_sequence": high,
            "next_after": rows[limit-1].sequence if len(rows) > limit else None,
            "patient_read": thread.patient_read, "doctor_read": thread.doctor_read}


@router.put("/threads/{thread_id}/read")
def mark_read(thread_id: str, payload: ReadMessages, response: Response,
              actor: User = Depends(participant), db: Session = Depends(get_db)):
    private(response)
    thread = service.authorize(db, actor, thread_id)
    if payload.through_sequence >= thread.next_sequence:
        raise HTTPException(422, "Cannot acknowledge unseen future messages")
    field = "patient_read" if actor.role == "patient" else "doctor_read"
    value = max(getattr(thread, field), payload.through_sequence)
    if value != getattr(thread, field):
        setattr(thread, field, value)
        service.audit(db, actor, "MESSAGES_READ", thread, through_sequence=value)
        service.save(db)
    return service.thread_out(thread)


@router.delete("/threads/{thread_id}/consent")
def withdraw(thread_id: str, response: Response,
             actor: User = Depends(require_role(["patient"])), db: Session = Depends(get_db)):
    private(response)
    # Withdrawal remains available even when the original clinical grant expired.
    thread = db.query(MessageThread).filter_by(id=thread_id, patient_id=actor.id).with_for_update().first()
    if thread is None: raise HTTPException(404, "Conversation not found")
    if thread.closed_at is None:
        thread.closed_at = datetime.now(timezone.utc)
        service.audit(db, actor, "MESSAGING_CONSENT_WITHDRAWN", thread)
        service.save(db)
    return {"id": thread.id, "status": "closed"}
