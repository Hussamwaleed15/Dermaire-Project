"""Accepted MVP release targets and offline retention review safeguards.

These helpers never delete journal data or keys and are not a lifecycle worker.
"""
from datetime import datetime, timedelta

STARTUP_READINESS_BUDGET_SECONDS = 180
DB_RPO_SECONDS = 300
RECOVERY_RTO_SECONDS = 1800
JOURNAL_RETENTION_DAYS = 42
MAX_BACKUP_HORIZON_DAYS = 35
MAX_RECOVERY_QUARANTINE_DAYS = 7


def validate_recovery_horizon(backup_days: int, quarantine_days: int) -> None:
    """Reject a retention inventory that invalidates the accepted 42-day target."""
    if (type(backup_days) is not int or type(quarantine_days) is not int
            or not 0 <= backup_days <= MAX_BACKUP_HORIZON_DAYS
            or not 0 <= quarantine_days <= MAX_RECOVERY_QUARANTINE_DAYS
            or backup_days + quarantine_days > JOURNAL_RETENTION_DAYS):
        raise ValueError("Recovery horizon exceeds accepted journal retention policy")


def journal_expiration_eligible(*, last_modified: datetime, now: datetime,
                                recoverable_until: list[datetime],
                                inventory_complete: bool, legal_hold: bool = False) -> bool:
    """Review one intent against ALL recoverable copies, including restored exports.

    Caller must supply an authoritative complete inventory; [] means verified none.
    Unknown inventory, legal hold or invalid timestamps deny expiration. Keys need
    a separate review and must survive every retained intent and recoverable copy.
    """
    if inventory_complete is not True or legal_hold is not False:
        return False
    dates = [last_modified, now, *recoverable_until]
    if any(not isinstance(d, datetime) or d.tzinfo is None or d.utcoffset() is None
           for d in dates):
        return False
    return (now >= last_modified + timedelta(days=JOURNAL_RETENTION_DAYS)
            and all(expiry <= now for expiry in recoverable_until))
