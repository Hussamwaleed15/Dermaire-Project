"""Product-create receipts only; not a universal mutation receipt registry."""
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone
from uuid import uuid5, NAMESPACE_URL
from fastapi import HTTPException
from app.models import ProductCreateAttempt
from app.schemas import ProductOut
from app.schemas.product_attempts import ProductCreateAttemptOut
from app.services.temporal import utc

WINDOW = timedelta(days=30)


def identity(owner, key):
    if not isinstance(key, str) or not re.fullmatch(r"[A-Za-z0-9_-]{16,128}", key):
        raise HTTPException(422, "Idempotency-Key must contain 16-128 ASCII letters, digits, underscores or hyphens")
    return str(uuid5(NAMESPACE_URL, json.dumps(['product-create-1', owner, owner, key])))


def fingerprint(payload):
    data = payload.model_dump(mode='json')
    # Preserve list order and exact text: no unproven semantic equivalence.
    if payload.start_date is not None:
        data['start_date'] = utc(payload.start_date).isoformat()
    return hashlib.sha256(json.dumps(['product-create-1', data], sort_keys=True,
        separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def output(row):
    expired = datetime.now(timezone.utc) >= utc(row.recorded_at) + WINDOW
    return ProductCreateAttemptOut(attempt_id=row.id, owner_id=row.user_id, actor_id=row.user_id,
        status='expired' if expired else 'committed', resource_id=row.resource_id,
        result_availability='expired' if expired else 'erased' if row.result_snapshot is None else 'retained',
        resource_revision=row.resource_revision, recorded_at=utc(row.recorded_at),
        expires_at=utc(row.recorded_at)+WINDOW,
        result=None if expired or row.result_snapshot is None else ProductOut.model_validate(row.result_snapshot))


def lookup(db, owner, key):
    identifier = identity(owner, key)
    row = db.query(ProductCreateAttempt).filter_by(id=identifier, user_id=owner).first()
    return output(row) if row else ProductCreateAttemptOut(attempt_id=identifier,
        owner_id=owner, actor_id=owner, status='unknown')


def replay(db, owner, identifier, digest, response=None):
    row = db.query(ProductCreateAttempt).filter_by(id=identifier, user_id=owner).first()
    if row is None:
        return None
    value = output(row)
    if value.status == 'expired':
        raise HTTPException(410, 'Product create replay expired; reconcile the original resource')
    if row.payload_hash != digest:
        raise HTTPException(409, 'Idempotency key belongs to a different product creation')
    if value.result_availability == 'erased':
        raise HTTPException(410, 'Original product result erased; creation receipt remains available')
    headers(response, row.id, row.resource_revision)
    return value.result


def headers(response, identifier, revision):
    if response is not None:
        response.headers['ETag'] = f'"{revision}"'
        response.headers['Cache-Control'] = 'no-store'
        if identifier is not None:
            response.headers['Operation-Attempt-Id'] = identifier


def erase_results(db, owner, resource):
    from app.models.configuration_attempts import ConfigurationAttempt
    db.query(ConfigurationAttempt).filter_by(user_id=owner, source_product_id=resource).update(
        {'result_snapshot': None}, synchronize_session='fetch')
    from app.models.product_mutations import ProductMutationAttempt
    db.query(ProductMutationAttempt).filter_by(user_id=owner, resource_id=resource, operation="patch").update(
        {'result_snapshot': None}, synchronize_session='fetch')
    db.query(ProductCreateAttempt).filter_by(user_id=owner, resource_id=resource).update(
        {'result_snapshot': None}, synchronize_session='fetch')
