"""Compatibility adapter for existing Flutter chat; conclusions stay on server."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models import User
from app.schemas import ChatMessageResponse
from app.schemas.contextual_ai import AssistanceRequest
from app.services.contextual_ai import assist

router = APIRouter(prefix='/chat', tags=['Contextual AI compatibility'])

@router.post('', response_model=ChatMessageResponse)
def chat_with_assistant(payload: AssistanceRequest, current_user: User=Depends(get_current_user),
                        db: Session=Depends(get_db)):
    try:
        result = assist(db, current_user, payload)
    except Exception:
        raise HTTPException(503, 'Authoritative context unavailable; retry or seek medical guidance.') from None
    guarded = result.metadata.mode == 'safety_guard'
    precaution = result.metadata.reason == 'question_safety_caution'
    return ChatMessageResponse(reply=result.message, kind='escalation' if guarded or precaution else 'education',
        escalation_triggered=guarded or precaution,
        safety_details={'authoritative_safety': result.authoritative_safety.model_dump(mode='json'),
                        'contextual_assistance': result.model_dump(mode='json')},
        azure_model_used='Safety Engine v1' if guarded else
            result.metadata.model if result.metadata.mode == 'grounded_ai' else
            'Deterministic Contextual AI v1 (AI unavailable or narrowed)')
