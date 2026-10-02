from datetime import datetime, timezone
from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from app.models import User, RoutineEntry

def today():
    return datetime.now(timezone.utc).date()

def lock_owner(db, user):
    # Serialize configuration/adherence/product lifecycle writes for this owner.
    db.query(User).filter(User.id == user.id).with_for_update().one()

def owned_entry(db, user, entry_id):
    entry = db.query(RoutineEntry).filter_by(id=entry_id, user_id=user.id).first()
    if entry is None:
        raise HTTPException(404, "Routine entry not found")
    return entry

def slot_keys(entry):
    entry.active_am_product = entry.product_id if entry.active and entry.schedule in ("AM", "BOTH") else None
    entry.active_pm_product = entry.product_id if entry.active and entry.schedule in ("PM", "BOTH") else None

def commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Conflicting routine slot or adherence already reported")
    except Exception:
        db.rollback()
        raise HTTPException(503, "Routine write unavailable; refresh before retrying")

def deactivate(entry):
    entry.active = False
    entry.end_date = today()
    slot_keys(entry)
