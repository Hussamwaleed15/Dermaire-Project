"""Accepted MVP release targets and offline retention review safeguards.

These helpers never delete journal data or keys and are not a lifecycle worker.
"""
from datetime import datetime, timedelta
from dataclasses import dataclass

STARTUP_READINESS_BUDGET_SECONDS = 180
DB_RPO_SECONDS = 300
RECOVERY_RTO_SECONDS = 1800
JOURNAL_RETENTION_DAYS = 42
MAX_BACKUP_HORIZON_DAYS = 35
MAX_RECOVERY_QUARANTINE_DAYS = 7
# Current policy: no journal/key expiry. Re-enablement needs an explicit review.
JOURNAL_EXPIRATION_ENABLED = False


@dataclass(frozen=True)
class RecoverableSource:
    """Authoritative source evidence; missing/unknown fields deny expiry."""
    provenance: str = "unknown"
    retention_days: int | None = None
    quarantine_days: int | None = None
    legal_hold: bool | None = None


def source_allows_expiration(source: RecoverableSource) -> bool:
    if (not isinstance(source, RecoverableSource)
            or source.provenance not in {"synthetic-only", "production-derived"}
            or source.legal_hold is not False):
        return False
    try:
        validate_recovery_horizon(source.retention_days, source.quarantine_days)
    except ValueError:
        return False
    return True


def validate_recovery_horizon(backup_days: int, quarantine_days: int) -> None:
    """Reject a retention inventory that invalidates the accepted 42-day target."""
    if (type(backup_days) is not int or type(quarantine_days) is not int
            or not 0 <= backup_days <= MAX_BACKUP_HORIZON_DAYS
            or not 0 <= quarantine_days <= MAX_RECOVERY_QUARANTINE_DAYS
            or backup_days + quarantine_days > JOURNAL_RETENTION_DAYS):
        raise ValueError("Recovery horizon exceeds accepted journal retention policy")


def journal_expiration_eligible(*, last_modified: datetime, now: datetime,
                                recoverable_until: list[datetime],
                                inventory_complete: bool, legal_hold: bool = False,
                                sources: list[RecoverableSource] | None = None,
                                expiration_enabled: bool = JOURNAL_EXPIRATION_ENABLED) -> bool:
    """Review one intent against ALL recoverable copies, including restored exports.

    Caller must supply an authoritative complete inventory; [] means verified none.
    Unknown inventory, legal hold or invalid timestamps deny expiration. Keys need
    a separate review and must survive every retained intent and recoverable copy.
    """
    # Explicit opt-in is an offline future-policy review, never a lifecycle action.
    if (expiration_enabled is not True or sources is None
            or any(not source_allows_expiration(source) for source in sources)):
        return False
    if inventory_complete is not True or legal_hold is not False:
        return False
    dates = [last_modified, now, *recoverable_until]
    if any(not isinstance(d, datetime) or d.tzinfo is None or d.utcoffset() is None
           for d in dates):
        return False
    return (now >= last_modified + timedelta(days=JOURNAL_RETENTION_DAYS)
            and all(expiry <= now for expiry in recoverable_until))


def journal_key_expiration_eligible(*, retained_signed_intents: bool | None, **review) -> bool:
    """Keys additionally outlive all retained signed intents; unknown denies expiry."""
    return (retained_signed_intents is False
            and journal_expiration_eligible(**review))
