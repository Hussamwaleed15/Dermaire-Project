import hashlib
import json
import re
from datetime import datetime, timezone, timedelta
from uuid import uuid5, NAMESPACE_URL
from fastapi import HTTPException
from app.models import User, DoctorPatientAccess, AuditLog
from app.models.messaging import MessageThread, ThreadMessage
from app.services.doctor_consent import granted_scopes
from app.services.temporal import utc


def save(db):
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Message operation unconfirmed; reconcile using the same key") from None


def audit(db, actor, action, thread, **details):
    # Content never enters audit or push payloads.
    db.add(AuditLog(actor_id=actor.id, action=action, target_resource="message_threads",
                    details={"thread_id": thread.id, "patient_id": thread.patient_id, **details}))


def current_grant(db, actor, grant_id):
    grant = db.query(DoctorPatientAccess).filter_by(id=grant_id).first()
    if grant is None or actor.id not in (grant.patient_id, grant.doctor_id):
        raise HTTPException(404, "Conversation not found")
    # Patient lock matches existing revoke and clinician-write fencing. Reads also
    # hold it until response construction; no historical receipt bypasses this gate.
    patient = db.query(User).filter_by(id=grant.patient_id, role="patient").with_for_update().first()
    grant = db.query(DoctorPatientAccess).filter_by(id=grant_id).populate_existing().with_for_update().one()
    doctor = db.get(User, grant.doctor_id)
    if (not patient or not doctor or doctor.role != "doctor" or actor.role not in ("patient", "doctor")
            or grant.status != "active" or utc(grant.expires_at) <= datetime.now(timezone.utc)
            or "VIEW" not in granted_scopes(grant)):
        raise HTTPException(403, "Conversation access is no longer active")
    return grant


def authorize(db, actor, thread_id, *, allow_closed=False):
    thread = db.query(MessageThread).filter_by(id=thread_id).first()
    if thread is None or actor.id not in (thread.patient_id, thread.doctor_id):
        raise HTTPException(404, "Conversation not found")
    grant = current_grant(db, actor, thread.access_id)
    if (grant.patient_id, grant.doctor_id) != (thread.patient_id, thread.doctor_id):
        raise HTTPException(403, "Original conversation grant changed")
    thread = db.query(MessageThread).filter_by(id=thread_id).populate_existing().with_for_update().one()
    if thread.closed_at is not None and not allow_closed:
        raise HTTPException(403, "Patient withdrew messaging consent")
    return thread


def thread_out(row):
    return {"id": row.id, "patient_id": row.patient_id, "doctor_id": row.doctor_id,
            "access_id": row.access_id, "created_at": utc(row.created_at),
            "closed_at": utc(row.closed_at) if row.closed_at else None,
            "latest_sequence": row.next_sequence - 1, "patient_read": row.patient_read,
            "doctor_read": row.doctor_read, "emergency_service": False,
            "retention": "account_lifetime_erased_if_either_participant_deletes_account"}


def message_out(row):
    return {"id": row.id, "thread_id": row.thread_id, "actor_id": row.actor_id,
            "sequence": row.sequence, "body": row.body, "created_at": utc(row.created_at),
            "provenance": "participant_authored", "clinical_clearance": False}


def open_thread(db, patient, payload):
    if patient.role != "patient" or payload.messaging_consent is not True:
        raise HTTPException(403, "Explicit patient messaging consent required")
    grant = current_grant(db, patient, payload.access_id)
    row = db.query(MessageThread).filter_by(access_id=grant.id).first()
    if row:
        if row.closed_at:
            raise HTTPException(409, "Withdrawn conversation requires a new grant and consent")
        return thread_out(row)
    row = MessageThread(patient_id=patient.id, doctor_id=grant.doctor_id, access_id=grant.id)
    db.add(row); db.flush()
    audit(db, patient, "MESSAGING_CONSENT_GRANTED", row, consent_version=1)
    result = thread_out(row)
    save(db)
    return result


def attempt_id(thread_id, actor_id, key):
    if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", key):
        raise HTTPException(422, "Idempotency-Key requires 16-128 ASCII letters, digits, underscores or hyphens")
    return str(uuid5(NAMESPACE_URL, json.dumps(["message-send-v1", thread_id, actor_id, key])))


def send(db, actor, thread_id, payload, key):
    thread = authorize(db, actor, thread_id)
    identifier = attempt_id(thread.id, actor.id, key)
    digest = hashlib.sha256(payload.body.encode("utf-8")).hexdigest()
    row = db.get(ThreadMessage, identifier)
    if row:
        if utc(row.created_at) + timedelta(days=30) <= datetime.now(timezone.utc):
            raise HTTPException(410, "Replay expired; reconcile message history")
        if row.payload_hash != digest:
            raise HTTPException(409, "Idempotency key is bound to different content")
        return message_out(row)
    row = ThreadMessage(id=identifier, thread_id=thread.id, actor_id=actor.id,
                        sequence=thread.next_sequence, body=payload.body, payload_hash=digest)
    thread.next_sequence += 1
    db.add(row); db.flush()
    audit(db, actor, "MESSAGE_COMMITTED", thread, message_id=row.id, sequence=row.sequence)
    result = message_out(row)
    save(db)
    return result


def read_attempt(db, actor, thread_id, key):
    thread = authorize(db, actor, thread_id)
    identifier = attempt_id(thread.id, actor.id, key)
    row = db.get(ThreadMessage, identifier)
    if row is None:
        return {"attempt_id": identifier, "status": "unknown", "result": None}
    expired = utc(row.created_at) + timedelta(days=30) <= datetime.now(timezone.utc)
    return {"attempt_id": identifier, "status": "expired" if expired else "committed",
            "result": None if expired else message_out(row)}
