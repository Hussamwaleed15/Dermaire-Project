"""Per-domain transactional receipts; unknown never means rejected or safe to resubmit."""
from datetime import datetime, timedelta, timezone
import hashlib
import json
from uuid import uuid5, NAMESPACE_URL
from fastapi import HTTPException
from app.models.clinical_attempts import ClinicalAttempt
from app.services.product_attempts import identity as validate_key
from app.services.temporal import utc


def key(value):
    if isinstance(value, list):
        if len(value) != 1:
            raise HTTPException(422, 'Provide exactly one Idempotency-Key')
        value = value[0]
    return value if isinstance(value, str) else None


def identity(doctor, patient, operation, key):
    validate_key(doctor, key)
    if operation not in ('note', 'review', 'claim'):
        raise HTTPException(422, 'Unknown clinical operation')
    return str(uuid5(NAMESPACE_URL, json.dumps(['clinical-attempt-1', doctor, patient, operation, key])))


def out(row):
    expired = utc(row.recorded_at) + timedelta(days=30) <= datetime.now(timezone.utc)
    return {'schema_version': 1, 'attempt_id': row.id, 'actor_id': row.doctor_id,
        'patient_id': row.patient_id, 'access_id': row.access_id, 'operation': row.operation,
        'resource_id': row.resource_id, 'recorded_at': utc(row.recorded_at),
        'expires_at': utc(row.recorded_at) + timedelta(days=30),
        'status': 'expired' if expired else 'committed',
        'result': None if expired else row.result_snapshot,
        'snapshot_basis': 'original_committed_not_current'}


def begin(db, doctor, patient, grant, operation, key, payload, response):
    if key is None:
        return None, None
    identifier = identity(doctor, patient, operation, key)
    fingerprint = hashlib.sha256(json.dumps(payload.model_dump(mode='json'), sort_keys=True,
        separators=(',', ':'), allow_nan=False).encode()).hexdigest()
    row = db.get(ClinicalAttempt, identifier)
    if row:
        if row.access_id != grant.id:
            raise HTTPException(409, 'Attempt belongs to a different consent grant')
        if row.payload_hash != fingerprint:
            raise HTTPException(409, 'Attempt key belongs to a different clinical payload')
        if out(row)['status'] == 'expired' or row.result_snapshot is None:
            raise HTTPException(410, 'Original clinical result unavailable; reconcile current history')
        headers(response, identifier, True)
        return None, row.result_snapshot
    return ClinicalAttempt(id=identifier, doctor_id=doctor, patient_id=patient,
        access_id=grant.id, operation=operation, payload_hash=fingerprint,
        recorded_at=datetime.now(timezone.utc).replace(tzinfo=None)), None


def stage(db, attempt, resource_id, snapshot, response):
    if attempt is not None:
        attempt.resource_id = resource_id
        attempt.result_snapshot = snapshot
        db.add(attempt)
        headers(response, attempt.id, False)


def headers(response, identifier, replay):
    response.headers['Operation-Attempt-Id'] = identifier
    response.headers['Operation-Replay'] = 'true' if replay else 'false'
    response.headers['Result-Snapshot'] = 'original_committed'
    response.headers['Cache-Control'] = 'no-store'
