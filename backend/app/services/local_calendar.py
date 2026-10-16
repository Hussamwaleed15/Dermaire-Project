"""Forward-only calendar labels. Legacy adherence uniqueness remains UTC."""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from fastapi import HTTPException
from app.models import User
from app.models.routine_history import UserCalendarPolicy


def valid_zone(value):
    try:
        return ZoneInfo(value)
    except (ZoneInfoNotFoundError, ValueError, TypeError):
        raise HTTPException(422, 'A supported IANA timezone is required')


def current(db, user_id):
    return db.query(UserCalendarPolicy).filter_by(user_id=user_id).order_by(
        UserCalendarPolicy.revision.desc()).first()


def view(row, now=None):
    now = now or datetime.now(timezone.utc)
    zone = row.timezone_name if row else 'UTC'
    return {'schema_version': 1, 'revision': row.revision if row else 0,
        'timezone': zone, 'effective_at': row.effective_at if row else None,
        'local_today': now.astimezone(valid_zone(zone)).date(),
        'adherence_day_basis': 'UTC', 'historical_reinterpretation': False,
        'policy': 'forward_only_labels_at_committed_instant',
        'reminder_policy': 'explicit_per_reminder_timezone_fold_and_gap'}


def change(db, user, zone, expected_revision):
    valid_zone(zone)
    # Same account lock as routine, experiment and adherence writes.
    db.query(User).filter_by(id=user.id).with_for_update().one()
    previous = current(db, user.id)
    revision = previous.revision if previous else 0
    if revision != expected_revision:
        raise HTTPException(412, 'Calendar policy changed; reload current policy')
    if previous and previous.timezone_name == zone:
        return previous
    row = UserCalendarPolicy(user_id=user.id, revision=revision + 1,
        timezone_name=zone, effective_at=datetime.now(timezone.utc))
    db.add(row)
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, 'Calendar update outcome unknown; reload policy before retrying')
    db.refresh(row)
    return row
