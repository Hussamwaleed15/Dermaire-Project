from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.schemas.contextual_ai import AssistanceRequest, AssistanceResponse
from app.services.contextual_ai import assist

router=APIRouter(prefix='/assistance',tags=['Contextual AI v1'])

@router.post('',response_model=AssistanceResponse)
def contextual_assistance(payload: AssistanceRequest, user: User=Depends(get_current_user),
                          db: Session=Depends(get_db)):
    try:
        return assist(db,user,payload)
    except Exception:
        raise HTTPException(503,'Authoritative context unavailable; retry or seek medical guidance.') from None
