"""Bounded committed PATCH/DELETE receipts; independent deletion intent is not a DB commit."""
import hashlib
import json
from datetime import datetime,timezone,timedelta
from uuid import uuid5,NAMESPACE_URL
from fastapi import HTTPException
from sqlalchemy.orm.exc import StaleDataError
from app.models.product_mutations import ProductMutationAttempt
from app.services.product_attempts import identity as validate_key,headers
from app.services.temporal import utc


def identity(owner,resource,operation,key):
    validate_key(owner,key)
    if operation not in ("patch","delete"):raise HTTPException(422,"Unknown product operation")
    return str(uuid5(NAMESPACE_URL,json.dumps(["product-mutation-1",owner,owner,resource,operation,key])))


def fingerprint(resource,operation,payload,if_match):
    value=payload.model_dump(mode="json",exclude_unset=True) if payload else None
    return hashlib.sha256(json.dumps(["product-mutation-1",resource,operation,value,if_match],sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()


def output(row):
    expired=utc(row.recorded_at)+timedelta(days=30)<=datetime.now(timezone.utc)
    return {"schema_version":1,"attempt_id":row.id,"owner_id":row.user_id,"actor_id":row.user_id,
        "operation":"product_"+row.operation,"status":"expired" if expired else "committed",
        "resource_id":row.resource_id,"resource_revision":row.resource_revision,"recorded_at":utc(row.recorded_at),
        "expires_at":utc(row.recorded_at)+timedelta(days=30),
        "result_availability":"expired" if expired else "erased" if row.result_snapshot is None else "retained",
        "result":None if expired else row.result_snapshot}


def lookup(db,owner,resource,operation,key):
    identifier=identity(owner,resource,operation,key)
    row=db.query(ProductMutationAttempt).filter_by(id=identifier,user_id=owner).first()
    return output(row) if row else {"schema_version":1,"attempt_id":identifier,"owner_id":owner,"actor_id":owner,
        "operation":"product_"+operation,"status":"unknown","result_availability":"unknown","result":None}


def replay(db,owner,identifier,digest,response=None):
    row=db.query(ProductMutationAttempt).filter_by(id=identifier,user_id=owner).first()
    if row is None:return None
    result=output(row)
    if result["status"]=="expired":raise HTTPException(410,"Product mutation replay expired; reconcile history")
    if row.payload_hash!=digest:raise HTTPException(409,"Attempt key is bound to different content or precondition")
    if result["result_availability"]=="erased":raise HTTPException(410,"Original product mutation content erased")
    headers(response,row.id,row.resource_revision)
    return row.result_snapshot


def stage(db,owner,resource,operation,identifier,digest,revision,result):
    db.add(ProductMutationAttempt(id=identifier,user_id=owner,resource_id=resource,operation=operation,
        payload_hash=digest,resource_revision=revision,result_snapshot=result,recorded_at=datetime.now(timezone.utc).replace(tzinfo=None)))


def flush(db):
    try:db.flush()
    except StaleDataError:
        db.rollback();raise HTTPException(412,"Product revision changed; reconcile before retry") from None
    except Exception:
        db.rollback();raise HTTPException(503,"Product mutation unconfirmed; reconcile the same attempt") from None
