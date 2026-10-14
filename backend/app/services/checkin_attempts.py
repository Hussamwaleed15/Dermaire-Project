"""Bounded report/manual receipts stored atomically in the existing CheckIn JSON.

Absence is unknown, never evidence that a concurrent request failed. No raw keys.
"""
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from uuid import uuid5, NAMESPACE_URL
from fastapi import HTTPException
from app.models import CheckIn
from app.schemas import CheckInResponse, CheckInReceipt

WINDOW = timedelta(days=30)

def identity(owner, key):
    if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", key):
        raise HTTPException(422, "Idempotency-Key must contain 16-128 ASCII letters, digits, underscores or hyphens")
    return str(uuid5(NAMESPACE_URL, json.dumps(["checkin-report-v1", owner, key])))

def fingerprint(time, notes, experiment, report, scores):
    normalized = report.model_dump(mode="json") if report else None
    if normalized:
        normalized["symptoms"] = sorted(normalized["symptoms"])
    body = ["checkin-report-v1", time, notes, experiment or None, normalized,
        [float(value) if value else 0.0 if value is not None else None for value in scores]]
    return hashlib.sha256(json.dumps(body, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()

def utc(value):
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)

def metadata(row):
    observation = row.observation
    data = observation.get("attempt") if isinstance(observation, dict) else None
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        return None
    digest = data.get("payload_hash")
    return data if isinstance(digest, str) and re.fullmatch(r"[0-9a-f]{64}", digest) else None

def receipt(row):
    data = metadata(row)
    if not data:
        return None
    return {"schema_version": 1, "attempt_id": row.id, "operation": "checkin_report_manual",
        "owner_id": row.user_id, "actor_id": row.user_id, "resource_id": row.id,
        "status": "expired" if datetime.now(timezone.utc) >= utc(row.created_at)+WINDOW else "committed",
        "committed_at": utc(row.created_at).isoformat(), "expires_at": (utc(row.created_at)+WINDOW).isoformat()}

def response(row):
    result = CheckInResponse.model_validate(row)
    info = receipt(row)
    result.receipt = CheckInReceipt.model_validate(info) if info else None
    return result

def replay(db, owner, identifier, digest):
    row = db.query(CheckIn).filter_by(id=identifier, user_id=owner).first()
    if row is None:
        return None
    data = metadata(row)
    if not data or data.get("schema_version") != 1:
        raise HTTPException(409, "Attempt identity is unavailable")
    if receipt(row)["status"] == "expired":
        raise HTTPException(410, "Attempt replay window expired; reconcile the original record")
    if data.get("payload_hash") != digest:
        raise HTTPException(409, "Idempotency key belongs to a different check-in request")
    return response(row)

def lookup(db, owner, key):
    identifier = identity(owner, key)
    row = db.query(CheckIn).filter_by(id=identifier, user_id=owner).first()
    if row is None or not metadata(row):
        return {"schema_version": 1, "attempt_id": identifier, "operation": "checkin_report_manual",
            "owner_id": owner, "actor_id": owner, "status": "unknown", "result": None}
    info = receipt(row)
    return {**info, "result": response(row).model_dump(mode="json") if info["status"] == "committed" else None}
