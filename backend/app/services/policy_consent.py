"""Version equality is consent currency, never a clinical clearance."""
import re
from datetime import datetime, timezone
from fastapi import HTTPException
from app.core.config import settings
from app.models import AuditLog, User


def consent_snapshot(user):
    version = user.safety_policy_version
    timestamp = user.safety_accepted_at
    valid = isinstance(version, str) and len(version) <= 20 and bool(re.fullmatch(r"[0-9]+\.[0-9]+", version))
    accepted_at = (timestamp.replace(tzinfo=timezone.utc) if timestamp.tzinfo is None
                   else timestamp.astimezone(timezone.utc)) if timestamp else None
    if not user.safety_accepted:
        state = "missing"
    elif not valid or accepted_at is None or accepted_at > datetime.now(timezone.utc):
        state = "unknown"
    else:
        state = "current" if version == settings.SAFETY_POLICY_REQUIRED_VERSION else "outdated"
    return {"schema_version": 1, "state": state,
            "required_version": settings.SAFETY_POLICY_REQUIRED_VERSION,
            "accepted_version": version if user.safety_accepted and valid else None,
            "accepted_at": accepted_at,
            "acceptance_required": state != "current",
            "enforcement_enabled": settings.SAFETY_POLICY_ENFORCE}


def accept_policy(db, user, payload):
    if payload.policy_version != settings.SAFETY_POLICY_REQUIRED_VERSION:
        raise HTTPException(409, "Policy changed; read /users/me and review the required version")
    # Conditional SQL makes duplicate/concurrent acceptance preserve the first receipt,
    # including on SQLite where SELECT FOR UPDATE is not implemented.
    now = datetime.now(timezone.utc)
    changed = db.query(User).filter(User.id == user.id).filter(
        (User.safety_accepted.is_not(True)) |
        (User.safety_policy_version.is_(None)) |
        (User.safety_policy_version != payload.policy_version) |
        (User.safety_accepted_at.is_(None)) |
        (User.safety_accepted_at > now)
    ).update({"safety_accepted": True, "safety_policy_version": payload.policy_version,
              "safety_accepted_at": now}, synchronize_session=False)
    if changed:
        db.add(AuditLog(actor_id=user.id, action="SAFETY_TERMS_ACCEPTED", target_resource="users",
                        details={"version": payload.policy_version}))
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Acceptance could not be confirmed; read /users/me")
    db.refresh(user)
    return user
