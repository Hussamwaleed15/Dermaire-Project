"""User-reported UTC daily context. No weather inference or metric adjustment."""
from datetime import date, datetime, timezone
from typing import Optional
from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import DailyContext, User

router = APIRouter(prefix="/context", tags=["Daily context"])

class ContextInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    unusual_conditions: Optional[bool] = Field(None, strict=True)
    cycle_day: Optional[int] = Field(None, ge=1, le=60, strict=True)

class ContextResponse(ContextInput):
    date: date
    recorded: bool
    source: str = "user_reported"
    updated_at: Optional[datetime] = None

def snapshot(db, user_id, day):
    row = db.query(DailyContext).filter_by(user_id=user_id, date=day).first()
    return ContextResponse(date=day, recorded=row is not None,
        unusual_conditions=row.unusual_conditions if row else None,
        cycle_day=row.cycle_day if row else None,
        updated_at=row.updated_at if row else None)

@router.get("/{day}", response_model=ContextResponse)
def read_context(day: date, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return snapshot(db, user.id, day)

@router.put("/{day}", response_model=ContextResponse)
def save_context(day: date, payload: ContextInput, user: User = Depends(get_current_user),
                 db: Session = Depends(get_db)):
    # Serialize writes for one account, including the first insert.
    db.query(User).filter_by(id=user.id).with_for_update().first()
    row = db.query(DailyContext).filter_by(user_id=user.id, date=day).first()
    if row is None:
        row = DailyContext(user_id=user.id, date=day)
        db.add(row)
    row.unusual_conditions = payload.unusual_conditions
    row.cycle_day = payload.cycle_day
    row.updated_at = datetime.now(timezone.utc)
    db.commit()
    return snapshot(db, user.id, day)
