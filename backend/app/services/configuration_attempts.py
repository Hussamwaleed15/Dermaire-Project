"""Explicit routine/experiment receipts, not a universal mutation decorator.

Every caller stages its own domain mutation and explicitly supplies the original
typed projection before the same SQL transaction commits. No reservations,
external effects or clinician/grant semantics are inferred by this module.
"""
from dataclasses import dataclass
from datetime import datetime,timedelta,timezone
import hashlib
import json
from uuid import uuid5,NAMESPACE_URL
from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm.exc import StaleDataError
from app.models import AuditLog
from app.models.configuration_attempts import ConfigurationAttempt
from app.services.product_attempts import identity as validate_key
from app.services.resource_revisions import header
from app.services.temporal import utc

OPERATIONS={"routine":{"create","update","stop"},
    "experiment":{"create","edit","activate","finish","cancel","evaluate","legacy_pause"}}


def identity(owner,domain,operation,resource,key):
    validate_key(owner,key)
    if domain not in OPERATIONS or operation not in OPERATIONS[domain]:raise HTTPException(422,"Unknown configuration operation")
    if operation=="create" and resource or operation!="create" and not resource:
        raise HTTPException(422,"Configuration attempt resource scope is invalid")
    return str(uuid5(NAMESPACE_URL,json.dumps(["owner-configuration-attempt-1",owner,owner,domain,operation,resource,key])))


def out(row):
    expired=utc(row.recorded_at)+timedelta(days=30)<=datetime.now(timezone.utc)
    return {"schema_version":1,"attempt_id":row.id,"owner_id":row.user_id,"actor_id":row.user_id,
        "domain":row.domain,"operation":row.operation,"resource_id":row.resource_id,"resource_revision":row.resource_revision,
        "recorded_at":utc(row.recorded_at),"expires_at":utc(row.recorded_at)+timedelta(days=30),
        "status":"expired" if expired else "committed","result_kind":row.result_kind,
        "result_availability":"expired" if expired else "erased" if row.result_snapshot is None else "retained",
        "result":None if expired else row.result_snapshot,"snapshot_basis":"original_committed_not_current"}


def lookup(db,owner,domain,operation,resource,key):
    identifier=identity(owner,domain,operation,resource,key)
    row=db.query(ConfigurationAttempt).filter_by(id=identifier,user_id=owner).first()
    return out(row) if row else {"schema_version":1,"attempt_id":identifier,"owner_id":owner,"actor_id":owner,
        "domain":domain,"operation":operation,"status":"unknown","result":None}


def headers(response,row,etag_name="ETag",replayed=False):
    response.headers[etag_name]=f'"{row.resource_revision}"'
    response.headers["Operation-Attempt-Id"]=row.id
    response.headers["Cache-Control"]="no-store"
    response.headers["Result-Snapshot"]="original_committed"
    response.headers["Operation-Replay"]="true" if replayed else "false"


@dataclass
class Attempt:
    identifier: str
    owner: str
    domain: str
    operation: str
    payload_hash: str
    previous: dict | None=None


def begin(db,owner,domain,operation,resource,payload,request,response,etag_name="ETag"):
    if request is None:return None
    key=header(request,"Idempotency-Key")
    if key is None:return None
    identifier=identity(owner,domain,operation,resource,key)
    value=payload.model_dump(mode="json",exclude_unset=True) if payload is not None else None
    fingerprint=hashlib.sha256(json.dumps([domain,operation,resource,value,header(request),header(request,"Routine-If-Match")],
        sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()
    row=db.query(ConfigurationAttempt).filter_by(id=identifier,user_id=owner).first()
    if row:
        if out(row)["status"]=="expired":raise HTTPException(410,"Configuration attempt replay expired; reconcile resource/history")
        if row.payload_hash!=fingerprint:raise HTTPException(409,"Attempt key belongs to different configuration or preconditions")
        if row.result_snapshot is None:raise HTTPException(410,"Original configuration content erased")
        headers(response,row,etag_name,True)
    return Attempt(identifier,owner,domain,operation,fingerprint,row.result_snapshot if row else None)


def commit(db,attempt,row,projection,commit_domain,response,result_kind,etag_name="ETag"):
    try:db.flush()
    except StaleDataError:
        db.rollback();raise HTTPException(412,"Configuration revision changed; reconcile before retry") from None
    except IntegrityError:
        db.rollback();raise HTTPException(409,"Conflicting configuration") from None
    except Exception:
        db.rollback();raise HTTPException(503,"Configuration attempt unconfirmed; reconcile original key") from None
    try:result=projection().model_dump(mode="json")
    except Exception:
        db.rollback();raise HTTPException(503,"Configuration projection unconfirmed; reconcile original key") from None
    receipt=ConfigurationAttempt(id=attempt.identifier,user_id=attempt.owner,domain=attempt.domain,operation=attempt.operation,
        resource_id=row.id,source_product_id=getattr(row,"product_id",None),resource_revision=row.revision,payload_hash=attempt.payload_hash,result_kind=result_kind,
        result_snapshot=result,recorded_at=datetime.now(timezone.utc).replace(tzinfo=None))
    db.add(receipt)
    db.add(AuditLog(actor_id=attempt.owner,action="CONFIGURATION_OPERATION_COMMITTED",target_resource=attempt.domain,
        details={"resource_id":row.id,"attempt_id":receipt.id,"operation":attempt.operation,"revision":row.revision}))
    headers(response,receipt,etag_name)
    commit_domain(db)
    return result
