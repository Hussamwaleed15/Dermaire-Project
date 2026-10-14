"""Durable committed adherence attempts. Absence never proves failure."""
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from uuid import uuid5, NAMESPACE_URL
from fastapi import HTTPException
from app.models import RoutineAdherence

WINDOW = timedelta(days=30)


def identity(owner, key):
    if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", key):
        raise HTTPException(422, "Idempotency-Key requires 16-128 ASCII letters, digits, underscores or hyphens")
    return str(uuid5(NAMESPACE_URL, json.dumps(["routine-adherence-v1", owner, owner, key])))


def fingerprint(payload):
    body = ["routine-adherence-v1", payload.model_dump(mode="json")]
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def utc(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def metadata(row):
    value = row.attempt_metadata
    if value is None:
        return None
    if not isinstance(value, dict) or value.get("schema_version") != 1 or not isinstance(value.get("payload_hash"), str) or not re.fullmatch(r"[0-9a-f]{64}", value["payload_hash"]):
        raise HTTPException(503, "Adherence receipt unavailable; reconcile before retrying")
    return value


def receipt(row):
    if metadata(row) is None:
        return None
    return {"schema_version": 1, "operation": "routine_adherence", "attempt_id": row.id,
        "owner_id": row.user_id, "actor_id": row.user_id, "resource_id": row.id,
        "configuration_revision": row.configuration_snapshot.get("revision"),
        "status": "expired" if datetime.now(timezone.utc) >= utc(row.created_at)+WINDOW else "committed",
        "committed_at": utc(row.created_at), "expires_at": utc(row.created_at)+WINDOW}


def replay(db, owner, identifier, digest):
    row = db.query(RoutineAdherence).filter_by(id=identifier, user_id=owner).first()
    if row is None:
        return None
    value = metadata(row)
    if value is None:
        raise HTTPException(409, "Attempt identity is unavailable")
    if receipt(row)["status"] == "expired":
        raise HTTPException(410, "Adherence replay window expired; reconcile original history")
    if value["payload_hash"] != digest:
        raise HTTPException(409, "Idempotency key belongs to a different adherence request")
    return row


def lookup(db, owner, key):
    from app.schemas.routine import AdherenceOut
    identifier = identity(owner, key)
    row = db.query(RoutineAdherence).filter_by(id=identifier, user_id=owner).first()
    if row is None:
        return {"schema_version":1, "operation":"routine_adherence", "attempt_id":identifier,
            "owner_id":owner, "actor_id":owner, "status":"unknown", "result":None}
    info = receipt(row)
    if info is None:
        raise HTTPException(503, "Adherence receipt unavailable; reconcile original history")
    return {**info, "result":AdherenceOut.model_validate(row) if info["status"] == "committed" else None}
