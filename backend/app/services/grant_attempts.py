"""Patient consent receipts; never revive a claimed, expired or revoked QR."""
from datetime import datetime, timedelta, timezone
import hashlib
import json
from uuid import uuid5, NAMESPACE_URL
from fastapi import HTTPException
from app.models import GrantAttempt, DoctorPatientAccess, User, AuditLog
from app.services.doctor_consent import consent_of
from app.core.security import credential_stamp
from app.services.clinical_attempts import headers, key as parse_key
from app.services.product_attempts import identity as validate_key
from app.services.temporal import utc


def identity(owner, operation, key):
    validate_key(owner, key)
    if operation not in ('issue', 'revoke', 'revoke_all'):
        raise HTTPException(422, 'Unknown consent operation')
    return str(uuid5(NAMESPACE_URL, json.dumps(['grant-attempt-1', owner, operation, key])))


def available(db, row):
    if utc(row.recorded_at) + timedelta(days=30) <= datetime.now(timezone.utc) or row.result_snapshot is None:
        return 'expired'
    if row.operation == 'issue':
        grant = db.get(DoctorPatientAccess, row.access_id)
        if not grant or grant.status != 'pending' or grant.claimed_at or grant.revoked_at or utc(grant.expires_at) <= datetime.now(timezone.utc):
            return 'unavailable'
        intent = consent_of(grant)
        owner = db.get(User, row.user_id)
        if (not owner or not intent or intent.get('credential') != credential_stamp(owner.hashed_password)
            or db.query(AuditLog).filter_by(actor_id=row.user_id, action='SESSION_REVOKED',
                target_resource=intent.get('session_jti')).first()):
            return 'unavailable'
    return 'retained'


def out(db, row):
    state = available(db, row)
    return {'schema_version': 1, 'attempt_id': row.id, 'actor_id': row.user_id,
        'owner_id': row.user_id, 'access_id': row.access_id, 'operation': row.operation,
        'status': 'expired' if state == 'expired' else 'committed',
        'result_availability': state, 'result': row.result_snapshot if state == 'retained' else None,
        'snapshot_basis': 'original_committed_not_current'}


def begin(db, owner, operation, key, payload, response):
    # Same lock order as claim/clinician authorization/account deletion.
    db.query(User).filter_by(id=owner).with_for_update().first()
    key = parse_key(key)
    if key is None:
        return None, None
    identifier = identity(owner, operation, key)
    fingerprint = hashlib.sha256(json.dumps(payload, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()
    row = db.get(GrantAttempt, identifier)
    if row:
        if row.payload_hash != fingerprint:
            raise HTTPException(409, 'Attempt belongs to different consent intent')
        if available(db, row) != 'retained':
            raise HTTPException(410, 'Original consent result unavailable; reconcile access list')
        headers(response, identifier, True)
        return None, row.result_snapshot
    return GrantAttempt(id=identifier, user_id=owner, operation=operation,
        payload_hash=fingerprint, recorded_at=datetime.now(timezone.utc).replace(tzinfo=None)), None


def stage(db, attempt, grant_id, snapshot, response):
    if attempt is not None:
        attempt.access_id = grant_id
        attempt.result_snapshot = snapshot
        db.add(attempt)
        headers(response, attempt.id, False)
