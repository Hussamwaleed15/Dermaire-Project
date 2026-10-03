from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.schemas.safety import SafetyEvaluation
from app.services.safety import evaluate_safety
router = APIRouter(prefix="/safety", tags=["Safety"])
@router.get("", response_model=SafetyEvaluation)
def current_safety(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return evaluate_safety(db, user)
