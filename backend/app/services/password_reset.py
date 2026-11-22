"""Shared-database password reset controls; never log reset codes or raw email."""

from datetime import datetime, timedelta, timezone
import hashlib
import hmac

from sqlalchemy import text

from app.core.config import settings
from app.models import AuditLog


_DIGEST_PREFIX = "hmac-sha256$"


def token_digest(token: str) -> str:
    digest = hmac.new(
        settings.SECRET_KEY.encode("utf-8"), token.encode("utf-8"), hashlib.sha256
    ).hexdigest()
    return _DIGEST_PREFIX + digest


def token_matches(token: str, stored_digest: str) -> bool:
    candidate = token_digest(token)
    if stored_digest.startswith(_DIGEST_PREFIX):
        return hmac.compare_digest(candidate, stored_digest)
    # Compatibility for reset codes issued before B4/B5. They expire in 30 minutes.
    legacy = hashlib.sha256(token.encode("utf-8")).hexdigest()
    return hmac.compare_digest(legacy, stored_digest)


def _subject_key(normalized_email: str) -> tuple[str, int]:
    digest = hmac.new(
        settings.SECRET_KEY.encode("utf-8"),
        normalized_email.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    actor_id = "pwd-" + digest[:32]
    lock_key = int.from_bytes(bytes.fromhex(digest[:16]), "big", signed=True)
    return actor_id, lock_key


def claim_request_slot(db, email: str) -> bool:
    """Atomically claim a per-identifier slot across application replicas."""
    normalized = email.strip().casefold()
    actor_id, lock_key = _subject_key(normalized)
    if db.bind.dialect.name == "postgresql":
        db.execute(text("SELECT pg_advisory_xact_lock(:key)"), {"key": lock_key})
    cutoff = datetime.now(timezone.utc) - timedelta(
        minutes=settings.PASSWORD_RESET_RATE_WINDOW_MINUTES
    )
    count = db.query(AuditLog).filter(
        AuditLog.actor_id == actor_id,
        AuditLog.action == "PASSWORD_RESET_RATE_SLOT",
        AuditLog.created_at >= cutoff,
    ).count()
    if count >= settings.PASSWORD_RESET_RATE_LIMIT:
        return False
    db.add(AuditLog(
        actor_id=actor_id,
        action="PASSWORD_RESET_RATE_SLOT",
        target_resource="password-reset",
        details={},
    ))
    return True
