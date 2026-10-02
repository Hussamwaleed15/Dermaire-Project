from fastapi import APIRouter, Depends, Response, HTTPException
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.api.deps import get_current_user, get_token_subject, record_audit
from app.core.exceptions import DermaireException
from app.services.account_deletion import delete_account
from app.models import User
from app.schemas import UserOut, SkinProfileUpdate

router = APIRouter(prefix="/users", tags=["User Profile & Skin Setup"])

@router.get("/me", response_model=UserOut)
def get_current_user_profile(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    from app.services.baseline import baseline_snapshot
    result = UserOut.model_validate(current_user).model_dump()
    result["baseline_checkins_count"] = baseline_snapshot(db, current_user.id)["completed_days"]
    return result

@router.patch("/skin-profile", response_model=UserOut)
def update_skin_profile(
    payload: SkinProfileUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    changes = payload.model_dump(exclude_unset=True)
    if 'profile_context' in changes:
        context = changes.pop('profile_context')
        merged = {**(current_user.profile_context or {}), **(context or {})} if context is not None else None
        if merged:
            disclosure = merged.get('hormonal_disclosure')
            if disclosure in ('prefer_not_to_say', 'none_reported'):
                if context and context.get('hormonal_context'):
                    raise HTTPException(422, 'Hormonal details require disclosed status')
                merged['hormonal_context'] = None
            elif merged.get('hormonal_context') and disclosure != 'disclosed':
                raise HTTPException(422, 'Choose disclosed status for hormonal details')
        current_user.profile_context = merged
    for field, value in changes.items():
        setattr(current_user, field, [] if field == 'skin_concerns' and value is None else value)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise DermaireException('Profile update could not be confirmed. Please retry.',
                               error_code='PROFILE_UPDATE_FAILED', status_code=503)
    db.refresh(current_user)

    record_audit(db, current_user.id, "SKIN_PROFILE_UPDATED", "users", {
        "fields": sorted(payload.model_fields_set)
    })
    return get_current_user_profile(current_user, db)


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
