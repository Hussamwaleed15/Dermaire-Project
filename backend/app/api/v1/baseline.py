from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.services.baseline import baseline_snapshot

router = APIRouter(prefix="/baseline", tags=["Baseline"])


@router.get("")
def get_baseline(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return baseline_snapshot(db, current_user.id)
