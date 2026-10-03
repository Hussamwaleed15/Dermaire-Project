from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.deps import get_current_user, record_audit
from app.models import User
from app.schemas import ChatMessageRequest, ChatMessageResponse
from app.services.azure_openai import azure_openai_service
from app.services.safety import evaluate_safety

router = APIRouter(prefix="/chat", tags=["AI Skin Assistant (Azure OpenAI & Safety)"])

@router.post("", response_model=ChatMessageResponse)
def chat_with_assistant(
    payload: ChatMessageRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    safety = evaluate_safety(db, current_user)
    if safety.status in ("urgent", "doctor_review"):
        reply, kind, escalation = safety.guidance, "escalation", True
        details = {"authoritative_safety": safety.model_dump(mode="json")}
    else:
        reply, kind, escalation, details = azure_openai_service.generate_chat_reply(payload.message)
        details = {**(details or {}), "authoritative_safety": safety.model_dump(mode="json")}

    record_audit(db, current_user.id, "AI_CHAT_QUERY", "chat", {
        "kind": kind,
        "escalation": escalation,
        "message_length": len(payload.message)
    })

    return ChatMessageResponse(
        reply=reply,
        kind=kind,
        escalation_triggered=escalation,
        safety_details=details,
        azure_model_used="Safety Engine v1" if safety.status in ("urgent", "doctor_review") else "Azure OpenAI GPT-4o + Azure AI Content Safety"
    )
