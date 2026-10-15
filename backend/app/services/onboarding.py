"""Explicit review is independent of optional clinical disclosure."""
from datetime import datetime, timezone
from fastapi import HTTPException
from app.models import User, AuditLog


def review_snapshot(user):
    stamp = user.profile_reviewed_at
    context = user.profile_context or {}
    present = bool(user.skin_type or user.selected_goal or user.skin_concerns or
                   any(value is not None and value != [] for value in context.values()))
    return {"schema_version": 1,
            "review_state": "not_applicable" if user.role != "patient" else "reviewed" if stamp else "never_reviewed",
            "reviewed_at": stamp.replace(tzinfo=timezone.utc) if stamp else None,
            "optional_data_present": present}


def complete_review(db, user):
    if user.role != "patient":
        raise HTTPException(403, "Profile review completion applies to patient accounts")
    if user.safety_consent["acceptance_required"]:
        raise HTTPException(403, "Current safety policy acceptance required; read /users/me")
    changed = db.query(User).filter(User.id == user.id, User.profile_reviewed_at.is_(None)).update(
        {"profile_reviewed_at": datetime.now(timezone.utc)}, synchronize_session=False)
    if changed:
        db.add(AuditLog(actor_id=user.id, action="PROFILE_REVIEW_COMPLETED", target_resource="users", details={"schema_version": 1}))
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Profile review could not be confirmed; read /users/me")
    db.refresh(user)
