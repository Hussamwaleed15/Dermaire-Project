from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User, Product, RoutineEntry, RoutineAdherence, AuditLog
from app.services.routine import today, lock_owner, owned_entry, slot_keys, commit, deactivate
from app.services.experiments import guard_routine_write, stopped_experiment
from app.schemas.routine import RoutineCreate, RoutineUpdate, RoutineOut, AdherenceCreate, AdherenceOut, AdherenceAttemptLookup

from app.services import resource_revisions as revisions
from app.services import adherence_attempts as attempts
from sqlalchemy.exc import IntegrityError
from app.services.temporal import utc_day
from app.schemas.history import AdherenceHistoryPage
from app.services import adherence_history
from app.services import configuration_attempts as configuration

router = APIRouter(prefix="/routine", tags=["Routine"])

@router.get("/entries", response_model=list[RoutineOut])
def entries(active: bool | None = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(RoutineEntry).filter_by(user_id=user.id)
    if active is not None:
        query = query.filter_by(active=active)
    return query.order_by(RoutineEntry.am_order, RoutineEntry.pm_order, RoutineEntry.created_at, RoutineEntry.id).all()

@router.post("/entries", response_model=RoutineOut, status_code=201)
def create(payload: RoutineCreate, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db), request: Request = None):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"routine","create","",payload,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    guard_routine_write(db, user.id)
    product = db.query(Product).filter_by(id=payload.product_id, user_id=user.id).first()
    if product is None:
        raise HTTPException(404, "Product not found")
    if product.status != "active":
        raise HTTPException(409, "An active product is required")
    if payload.start_date > today():
        raise HTTPException(422, "Future start dates are not supported")
    entry = RoutineEntry(user_id=user.id, **payload.model_dump())
    entry.active = True
    slot_keys(entry)
    db.add(entry)
    if attempt:return configuration.commit(db,attempt,entry,lambda:RoutineOut.model_validate(entry),commit,response,"routine")
    commit(db)
    db.refresh(entry)
    revisions.etag(response, entry)
    return entry


@router.get("/configuration-attempts/{operation}/{key}")
def configuration_attempt(operation: str,key: str,response: Response,resource_id: str="",
                          user: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    return configuration.lookup(db,user.id,"routine",operation,resource_id,key)

@router.get("/entries/{entry_id}", response_model=RoutineOut)
def read(entry_id: str, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    entry = owned_entry(db, user, entry_id)
    revisions.etag(response, entry)
    return entry

@router.patch("/entries/{entry_id}", response_model=RoutineOut)
def update(entry_id: str, payload: RoutineUpdate, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"routine","update",entry_id,payload,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    entry = owned_entry(db, user, entry_id)
    revisions.enforce(entry, revisions.header(request))
    guard_routine_write(db, user.id)
    data = payload.model_dump(exclude_unset=True)
    if any(value is None for key, value in data.items() if key != "instructions"):
        raise HTTPException(422, "Required configuration fields cannot be null")
    if not entry.active:
        raise HTTPException(409, "Stopped entries are immutable; create a new entry to resume")
    revisions.reserve(db, entry, revisions.header(request))
    for key, value in data.items():
        setattr(entry, key, value)
    if not entry.active:
        deactivate(entry)
    slot_keys(entry)
    if attempt:return configuration.commit(db,attempt,entry,lambda:RoutineOut.model_validate(entry),commit,response,"routine")
    commit(db)
    db.refresh(entry)
    revisions.etag(response, entry)
    return entry

@router.delete("/entries/{entry_id}", status_code=204)
def remove(entry_id: str, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"routine","stop",entry_id,None,request,response)
    if attempt and attempt.previous is not None:return
    entry = owned_entry(db, user, entry_id)
    revisions.enforce(entry, revisions.header(request))
    guard_routine_write(db, user.id)
    if entry.active:
        revisions.reserve(db, entry, revisions.header(request))
        deactivate(entry)
        if attempt:
            configuration.commit(db,attempt,entry,lambda:RoutineOut.model_validate(entry),commit,response,"routine")
            return
        commit(db)
    elif attempt:
        configuration.commit(db,attempt,entry,lambda:RoutineOut.model_validate(entry),commit,response,"routine")
        return
    revisions.etag(response, entry)

@router.get("/adherence", response_model=list[AdherenceOut])
def logs(routine_entry_id: str | None = None, limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(RoutineAdherence).filter_by(user_id=user.id)
    if routine_entry_id is not None:
        owned_entry(db, user, routine_entry_id)
        query = query.filter_by(routine_entry_id=routine_entry_id)
    return query.order_by(RoutineAdherence.date.desc(), RoutineAdherence.created_at.desc(), RoutineAdherence.id).offset(offset).limit(limit).all()

@router.get("/adherence/attempts/{key}", response_model=AdherenceAttemptLookup)
def adherence_attempt(key: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return attempts.lookup(db, user.id, key)


@router.get('/adherence/history', response_model=AdherenceHistoryPage)
def history(response: Response, routine_entry_id: str | None = None,
            limit: int = Query(100, ge=1, le=500), cursor: str | None = Query(None, min_length=1, max_length=4096),
            user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if routine_entry_id is not None:
        owned_entry(db, user, routine_entry_id)
    response.headers['Cache-Control'] = 'no-store'
    return adherence_history.page(db, user, limit, cursor, routine_entry_id)

@router.post("/adherence", response_model=AdherenceOut, status_code=201)
def log(payload: AdherenceCreate, request: Request, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    key = revisions.header(request, "Idempotency-Key")
    identifier = attempts.identity(user.id, key) if key is not None else None
    digest = attempts.fingerprint(payload) if key is not None else None
    lock_owner(db, user)
    if identifier is not None:
        existing = attempts.replay(db, user.id, identifier, digest)
        if existing is not None:
            return existing
    entry = owned_entry(db, user, payload.routine_entry_id)
    stopping = stopped_experiment(db, user.id, entry.id)
    if not entry.active and (not stopping or payload.status != "skipped"):
        raise HTTPException(409, "Stopped entries only accept skipped-use reports for an active stop experiment")
    if payload.slot not in (("AM", "PM") if entry.schedule == "BOTH" else (entry.schedule,)):
        raise HTTPException(422, "Slot is not configured for this entry")
    # Configuration is not versioned by day: do not project current settings into earlier days.
    earliest = max(entry.start_date, utc_day(entry.updated_at))
    if not earliest <= payload.date <= today():
        raise HTTPException(422, "Report date must be between latest configuration day/start date and today (UTC)")
    snapshot = RoutineOut.model_validate(entry).model_dump(mode="json")
    product = db.query(Product).filter_by(id=entry.product_id, user_id=user.id).one()
    if product.status != "active":
        raise HTTPException(409, "Product is no longer active")
    snapshot["product_name"] = product.name
    row = RoutineAdherence(user_id=user.id, configuration_snapshot=snapshot, **payload.model_dump())
    if identifier is not None:
        row.id = identifier
        row.attempt_metadata = {"schema_version":1, "payload_hash":digest}
        db.add(AuditLog(actor_id=user.id, action="ROUTINE_ADHERENCE_REPORTED", target_resource="routine_adherence",
            details={"adherence_id":identifier,"configuration_revision":entry.revision}))
    db.add(row)
    if identifier is None:
        commit(db)
    else:
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            existing = attempts.replay(db, user.id, identifier, digest)
            if existing is not None:
                return existing
            raise HTTPException(409, "Adherence slot already reported; this attempt is not committed")
        except Exception:
            db.rollback()
            raise HTTPException(503, "Adherence outcome unavailable; reconcile the same attempt")
    db.refresh(row)
    return row
