from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.deps import get_current_user, get_token_subject, record_audit
from app.core.exceptions import DermaireException
from app.services.account_deletion import delete_account
from app.models import User
from app.schemas import UserOut, SkinProfileUpdate

router = APIRouter(prefix="/users", tags=["User Profile & Skin Setup"])

@router.get("/me", response_model=UserOut)
def get_current_user_profile(current_user: User = Depends(get_current_user)):
    return current_user

@router.patch("/skin-profile", response_model=UserOut)
def update_skin_profile(
    payload: SkinProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    if payload.skin_type is not None:
        current_user.skin_type = payload.skin_type
    if payload.selected_goal is not None:
        current_user.selected_goal = payload.selected_goal
    if payload.skin_concerns is not None:
        current_user.skin_concerns = payload.skin_concerns

    db.commit()
    db.refresh(current_user)

    record_audit(db, current_user.id, "SKIN_PROFILE_UPDATED", "users", {
        "skin_type": current_user.skin_type,
        "selected_goal": current_user.selected_goal,
        "concerns": current_user.skin_concerns
    })
    return current_user


@router.delete("/me", status_code=204)
def delete_current_account(user_id: str = Depends(get_token_subject), db: Session = Depends(get_db)):
    try:
        delete_account(db, user_id)
    except Exception:
        db.rollback()
        raise DermaireException(
            "Account deletion could not be completed. Please retry.",
            error_code="ACCOUNT_DELETION_FAILED", status_code=503,
        )
    return Response(status_code=204)
