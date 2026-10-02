from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.schemas.personal_skin_model import PersonalSkinModel
from app.services.personal_skin_model import personal_skin_model

router = APIRouter(prefix='/personal-skin-model', tags=['Personal Skin Model'])

@router.get('', response_model=PersonalSkinModel)
def get_personal_skin_model(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return personal_skin_model(db, current_user)
