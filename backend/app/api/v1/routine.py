from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User, Product, RoutineEntry, RoutineAdherence
from app.services.routine import today, lock_owner, owned_entry, slot_keys, commit, deactivate
from app.schemas.routine import RoutineCreate, RoutineUpdate, RoutineOut, AdherenceCreate, AdherenceOut

router = APIRouter(prefix="/routine", tags=["Routine"])

@router.get("/entries", response_model=list[RoutineOut])
def entries(active: bool | None = None, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(RoutineEntry).filter_by(user_id=user.id)
    if active is not None:
        query = query.filter_by(active=active)
    return query.order_by(RoutineEntry.am_order, RoutineEntry.pm_order, RoutineEntry.created_at, RoutineEntry.id).all()

@router.post("/entries", response_model=RoutineOut, status_code=201)
def create(payload: RoutineCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
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
    commit(db)
    db.refresh(entry)
    return entry

@router.get("/entries/{entry_id}", response_model=RoutineOut)
def read(entry_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return owned_entry(db, user, entry_id)

@router.patch("/entries/{entry_id}", response_model=RoutineOut)
def update(entry_id: str, payload: RoutineUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    entry = owned_entry(db, user, entry_id)
    data = payload.model_dump(exclude_unset=True)
    if any(value is None for key, value in data.items() if key != "instructions"):
        raise HTTPException(422, "Required configuration fields cannot be null")
    if not entry.active:
        raise HTTPException(409, "Stopped entries are immutable; create a new entry to resume")
    for key, value in data.items():
        setattr(entry, key, value)
    if not entry.active:
        deactivate(entry)
    slot_keys(entry)
    commit(db)
    db.refresh(entry)
    return entry

@router.delete("/entries/{entry_id}", status_code=204)
def remove(entry_id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    entry = owned_entry(db, user, entry_id)
    if entry.active:
        deactivate(entry)
        commit(db)

@router.get("/adherence", response_model=list[AdherenceOut])
def logs(routine_entry_id: str | None = None, limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    query = db.query(RoutineAdherence).filter_by(user_id=user.id)
    if routine_entry_id is not None:
        owned_entry(db, user, routine_entry_id)
        query = query.filter_by(routine_entry_id=routine_entry_id)
    return query.order_by(RoutineAdherence.date.desc(), RoutineAdherence.created_at.desc(), RoutineAdherence.id).offset(offset).limit(limit).all()

@router.post("/adherence", response_model=AdherenceOut, status_code=201)
def log(payload: AdherenceCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    entry = owned_entry(db, user, payload.routine_entry_id)
    if not entry.active:
        raise HTTPException(409, "Cannot report new adherence for a stopped entry")
    if payload.slot not in (("AM", "PM") if entry.schedule == "BOTH" else (entry.schedule,)):
        raise HTTPException(422, "Slot is not configured for this entry")
    # Configuration is not versioned by day: do not project current settings into earlier days.
    earliest = max(entry.start_date, entry.updated_at.date())
    if not earliest <= payload.date <= today():
        raise HTTPException(422, "Report date must be between latest configuration day/start date and today (UTC)")
    snapshot = RoutineOut.model_validate(entry).model_dump(mode="json")
    product = db.query(Product).filter_by(id=entry.product_id, user_id=user.id).one()
    if product.status != "active":
        raise HTTPException(409, "Product is no longer active")
    snapshot["product_name"] = product.name
    row = RoutineAdherence(user_id=user.id, configuration_snapshot=snapshot, **payload.model_dump())
    db.add(row)
    commit(db)
    db.refresh(row)
    return row
