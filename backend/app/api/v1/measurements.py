from fastapi import APIRouter, Body, Depends, HTTPException
from pydantic import BaseModel, ConfigDict
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import Capture, Measurement, User
from app.services import measurement

class GenerationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")


router = APIRouter(prefix="/measurements", tags=["Image measurement proxies"])


@router.get("")
def history(limit: int = 50, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not 1 <= limit <= 100:
        raise HTTPException(422, "Limit must be between 1 and 100.")
    rows = (db.query(Measurement).join(Capture, Measurement.capture_id == Capture.id)
            .filter(Measurement.user_id == current_user.id, Capture.user_id == current_user.id)
            .order_by(Capture.received_at.desc(), Capture.id.desc(), Measurement.algorithm_version.desc()).limit(limit))
    return [measurement.response(row) for row in rows]


@router.get("/{capture_id}")
def read(capture_id: str, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    capture = db.query(Capture).filter_by(id=capture_id, user_id=current_user.id).first()
    if not capture:
        raise HTTPException(404, "Capture not found.")
    if capture.state != "accepted":
        raise HTTPException(409, "Rejected captures cannot be measured.")
    row = db.query(Measurement).filter_by(capture_id=capture.id, user_id=current_user.id, algorithm_version=measurement.VERSION).first()
    if not row:
        raise HTTPException(404, "Measurement not generated. Historical image bytes may be unavailable.")
    return measurement.response(row)


@router.post("/{capture_id}")
def generate(capture_id: str, payload: GenerationRequest | None = Body(None), current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Serializes generation against account deletion on PostgreSQL.
    db.query(User).filter_by(id=current_user.id).with_for_update().first()
    capture = db.query(Capture).filter_by(id=capture_id, user_id=current_user.id).first()
    if not capture:
        raise HTTPException(404, "Capture not found.")
    if capture.state != "accepted":
        raise HTTPException(409, "Rejected captures cannot be measured.")
    # Never accept replacement pixels or client metrics for an existing capture.
    # v1 does not retrieve stored blobs; new uploads generate inline.
    try:
        row = measurement.build(db, capture)
        result = measurement.response(row)
        db.commit()
        return result
    except IntegrityError:
        db.rollback()
        row = db.query(Measurement).filter_by(capture_id=capture.id, user_id=current_user.id, algorithm_version=measurement.VERSION).first()
        if row:
            return measurement.response(row)
        raise HTTPException(503, "Measurement could not be saved.")
    except Exception:
        db.rollback()
        raise HTTPException(503, "Measurement could not be saved.")
