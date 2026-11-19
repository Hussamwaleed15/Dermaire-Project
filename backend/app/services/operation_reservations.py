"""B6-A reservation state machine; intentionally not wired to API endpoints.

All state changes require the caller's transaction. For an atomic database
operation, lock/finish the reservation and perform the domain write before the
same commit. Never commit the domain write before the fenced finish.
"""
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import hmac
import json
import re
import secrets
import uuid

from sqlalchemy.orm import Session

from app.models import OperationReservation, User


_NAME = re.compile(r"^[a-z][a-z0-9_.-]{0,63}$")
_KEY = re.compile(r"^[A-Za-z0-9_-]{16,128}$")
_HASH = re.compile(r"^[0-9a-f]{64}$")
DEFAULT_LEASE = timedelta(seconds=30)
DEFAULT_RETENTION = timedelta(days=30)


class ReservationError(RuntimeError):
    pass


class ReservationConflict(ReservationError):
    pass


class ReservationExpired(ReservationError):
    pass


class ReservationFenceLost(ReservationError):
    pass


@dataclass(frozen=True)
class ReservationClaim:
    reservation_id: str
    status: str
    generation: int
    lease_token: str | None = None
    result_snapshot: object | None = None
    failure_code: str | None = None


def payload_digest(value) -> str:
    """Hash an already privacy-reviewed canonical payload."""
    encoded = json.dumps(value, sort_keys=True, separators=(",", ":"),
                         ensure_ascii=False, allow_nan=False).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _now(value=None):
    value = datetime.now(timezone.utc) if value is None else value
    if value.tzinfo is not None:
        value = value.astimezone(timezone.utc).replace(tzinfo=None)
    return value


def _clock(value=None):
    """Return a clock without reading it before a potentially blocking lock."""
    if callable(value):
        return value
    if value is not None:
        return lambda: value
    return lambda: datetime.now(timezone.utc)


def _validate(domain, operation, key, digest, lease, retention):
    if not _NAME.fullmatch(domain or "") or not _NAME.fullmatch(operation or ""):
        raise ValueError("domain and operation must be stable lowercase identifiers")
    if not _KEY.fullmatch(key or ""):
        raise ValueError("operation key must contain 16-128 ASCII letters, digits, underscores or hyphens")
    if not _HASH.fullmatch(digest or ""):
        raise ValueError("payload_hash must be a lowercase SHA-256 digest")
    if lease <= timedelta(0) or retention <= lease:
        raise ValueError("retention must be longer than the positive lease")


def _key_hash(owner_id, domain, operation, key):
    # Domain separation and owner binding prevent cross-scope correlation.
    value = json.dumps(["dermaire-operation-reservation-v1", owner_id, domain, operation, key],
                       separators=(",", ":")).encode()
    return hashlib.sha256(value).hexdigest()


def _token_hash(token):
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def _lock_owner(db: Session, owner_id: str):
    owner = db.query(User).filter_by(id=owner_id).with_for_update().one_or_none()
    if owner is None:
        raise ReservationError("reservation owner does not exist")


def _claim_row(row, now, lease):
    token = secrets.token_urlsafe(32)
    row.status = "reserved"
    row.generation += 1
    row.lease_token_hash = _token_hash(token)
    row.lease_expires_at = min(now + lease, row.retain_until)
    row.result_snapshot = None
    row.failure_code = None
    row.updated_at = now
    return ReservationClaim(row.id, row.status, row.generation, token)


def reserve(db: Session, *, owner_id: str, domain: str, operation: str, key: str,
            payload_hash: str, now=None, lease=DEFAULT_LEASE,
            retention=DEFAULT_RETENTION) -> ReservationClaim:
    """Claim new/failed/abandoned work. Caller commits the claim before doing work."""
    _validate(domain, operation, key, payload_hash, lease, retention)
    clock = _clock(now)
    _lock_owner(db, owner_id)  # Global order: owner, then reservation.
    key_hash = _key_hash(owner_id, domain, operation, key)
    row = (db.query(OperationReservation)
           .filter_by(owner_id=owner_id, domain=domain, operation=operation, key_hash=key_hash)
           .populate_existing().with_for_update().one_or_none())
    now = _now(clock())
    if row is None:
        token = secrets.token_urlsafe(32)
        row = OperationReservation(
            id=str(uuid.uuid4()), owner_id=owner_id, domain=domain, operation=operation,
            key_hash=key_hash, payload_hash=payload_hash, status="reserved", generation=1,
            lease_token_hash=_token_hash(token), lease_expires_at=now + lease,
            created_at=now, updated_at=now, retain_until=now + retention,
        )
        db.add(row)
        db.flush()
        return ReservationClaim(row.id, row.status, row.generation, token)
    if not hmac.compare_digest(row.payload_hash, payload_hash):
        raise ReservationConflict("operation key is already bound to a different payload")
    if now >= row.retain_until:
        raise ReservationExpired("operation identity retention expired; reconcile before retrying")
    if row.status == "committed":
        return ReservationClaim(row.id, row.status, row.generation,
                                result_snapshot=row.result_snapshot)
    if row.status == "reserved" and now < row.lease_expires_at:
        return ReservationClaim(row.id, "in_flight", row.generation)
    return _claim_row(row, now, lease)


def _lock_fenced(db, *, owner_id, reservation_id, generation, lease_token, clock):
    _lock_owner(db, owner_id)
    row = (db.query(OperationReservation)
           .filter_by(id=reservation_id, owner_id=owner_id)
           .populate_existing().with_for_update().one_or_none())
    now = _now(clock())
    valid = (row is not None and row.status == "reserved" and row.generation == generation
             and now < row.retain_until and now < row.lease_expires_at and lease_token
             and hmac.compare_digest(row.lease_token_hash, _token_hash(lease_token)))
    if not valid:
        raise ReservationFenceLost("reservation lease is missing, expired, or superseded")
    return row, now


def renew(db: Session, *, owner_id: str, reservation_id: str, generation: int,
          lease_token: str, now=None, lease=DEFAULT_LEASE):
    if lease <= timedelta(0):
        raise ValueError("lease must be positive")
    clock = _clock(now)
    row, now = _lock_fenced(db, owner_id=owner_id, reservation_id=reservation_id,
                            generation=generation, lease_token=lease_token, clock=clock)
    row.lease_expires_at = min(now + lease, row.retain_until)
    row.updated_at = now
    return row.lease_expires_at


def commit(db: Session, *, owner_id: str, reservation_id: str, generation: int,
           lease_token: str, result_snapshot=None, now=None) -> ReservationClaim:
    """Fence and mark committed; commit this and the domain mutation together."""
    clock = _clock(now)
    row, now = _lock_fenced(db, owner_id=owner_id, reservation_id=reservation_id,
                            generation=generation, lease_token=lease_token, clock=clock)
    row.status = "committed"
    row.lease_token_hash = None
    row.lease_expires_at = None
    row.result_snapshot = result_snapshot
    row.updated_at = now
    db.flush()
    return ReservationClaim(row.id, row.status, row.generation,
                            result_snapshot=row.result_snapshot)


def fail(db: Session, *, owner_id: str, reservation_id: str, generation: int,
         lease_token: str, failure_code: str, now=None) -> ReservationClaim:
    if not _NAME.fullmatch(failure_code or ""):
        raise ValueError("failure_code must be a non-sensitive stable identifier")
    clock = _clock(now)
    row, now = _lock_fenced(db, owner_id=owner_id, reservation_id=reservation_id,
                            generation=generation, lease_token=lease_token, clock=clock)
    row.status = "failed"
    row.lease_token_hash = None
    row.lease_expires_at = None
    row.failure_code = failure_code
    row.updated_at = now
    db.flush()
    return ReservationClaim(row.id, row.status, row.generation,
                            failure_code=row.failure_code)


def purge_expired(db: Session, *, owner_id: str, now=None) -> int:
    """Owner-scoped cleanup preserves the owner->reservation lock order."""
    now = _now(now)
    _lock_owner(db, owner_id)
    rows = (db.query(OperationReservation)
            .filter(OperationReservation.owner_id == owner_id,
                    OperationReservation.retain_until <= now)
            .with_for_update().all())
    for row in rows:
        db.delete(row)
    db.flush()
    return len(rows)
