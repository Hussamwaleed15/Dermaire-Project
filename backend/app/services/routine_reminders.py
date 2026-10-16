"""Prospective routine reminders. UTC adherence dates are never relabeled."""
from datetime import datetime, timezone, timedelta, time
from uuid import uuid5, NAMESPACE_URL
from zoneinfo import ZoneInfo
from fastapi import HTTPException
from app.models import User, RoutineEntry
from app.models.notifications import RoutineReminderSetting, Notification, NotificationJob
from app.services import notifications
from app.services.temporal import utc
from app.services.wall_time import resolve_due


def output(row):
    if row is None:
        return {"revision": 0, "enabled": False, "configured": False}
    return {"revision": row.revision, "enabled": row.enabled, "configured": True,
            "timezone": row.timezone, "am_minute": row.am_minute, "pm_minute": row.pm_minute,
            "fold": row.fold, "gap_policy": "skip", "effective_at": utc(row.effective_at),
            "calendar_policy": "prospective_fixed_occurrences_v1", "live_delivery": "unavailable"}


def owned_entry(db, owner, entry_id):
    row = db.query(RoutineEntry).filter_by(id=entry_id, user_id=owner).populate_existing().first()
    if row is None:
        raise HTTPException(404, "Routine entry not found")
    return row


def configure(db, actor, entry_id, payload):
    db.query(User).filter_by(id=actor.id).with_for_update().one()
    entry = owned_entry(db, actor.id, entry_id)
    row = db.query(RoutineReminderSetting).filter_by(routine_entry_id=entry.id).populate_existing().first()
    if payload.expected_revision != (row.revision if row else 0):
        raise HTTPException(409, "Reminder settings changed; refresh revision")
    pref = notifications.preferences(db, actor.id)
    if payload.enabled and (not entry.active or not pref or "routine" not in pref.enabled_kinds):
        raise HTTPException(409, "Active routine and explicit routine notification consent required")
    now = datetime.now(timezone.utc)
    for notice in db.query(Notification).filter_by(user_id=actor.id, kind="routine", source_id=entry.id, cancelled_at=None):
        notifications.cancel(db, notice)
    if row is None:
        row = RoutineReminderSetting(user_id=actor.id, routine_entry_id=entry.id, revision=0)
        db.add(row)
    for key, value in payload.model_dump(exclude={"expected_revision", "gap_policy"}).items():
        setattr(row, key, value)
    row.revision += 1
    row.effective_at = now
    row.generated_at = None
    db.commit()
    return output(row)


def generate(db, *, now=None, days=2, batch=100):
    """Bounded, transactional generation. Per-owner lock serializes settings/domain edits.

    Unavailable workers never backfill missed instants. Occurrences freeze zone,
    setting revision, entry revision, local date, slot and fold through identity.
    Gap days are skipped; overlap chooses the explicitly approved fold once.
    """
    if type(days) is not int or not 1 <= days <= 7 or type(batch) is not int or not 1 <= batch <= 500:
        raise ValueError("Generation bounded to 1..7 days and 1..500 settings")
    now = utc(now or datetime.now(timezone.utc))
    horizon = now + timedelta(days=days)
    ids = [r.id for r in db.query(RoutineReminderSetting).filter_by(enabled=True)
           .order_by(RoutineReminderSetting.generated_at.asc().nullsfirst(), RoutineReminderSetting.id).limit(batch)]
    generated = 0
    for identifier in ids:
        setting = db.get(RoutineReminderSetting, identifier)
        if setting is None:
            continue
        owner = db.query(User).filter_by(id=setting.user_id).with_for_update().first()
        if owner is None:
            continue
        setting = db.query(RoutineReminderSetting).filter_by(id=identifier).populate_existing().first()
        if setting is None or not setting.enabled:
            continue
        entry = db.get(RoutineEntry, setting.routine_entry_id)
        pref = notifications.preferences(db, setting.user_id)
        if not entry or not entry.active or not pref or "routine" not in pref.enabled_kinds:
            setting.generated_at = now
            continue
        zone = ZoneInfo(setting.timezone)
        local_day = now.astimezone(zone).date()
        slots = ["AM", "PM"] if entry.schedule == "BOTH" else [entry.schedule]
        for offset in range(days + 2):
            day = local_day + timedelta(days=offset)
            for slot in slots:
                minute = setting.am_minute if slot == "AM" else setting.pm_minute
                local = datetime.combine(day, time(minute // 60, minute % 60))
                try:
                    # fold=1 is meaningful only for overlaps; ordinary wall times use fold=0.
                    try:
                        resolved = resolve_due(local, setting.timezone)
                    except ValueError as exc:
                        if "Ambiguous" not in str(exc):
                            raise
                        resolved = resolve_due(local, setting.timezone, setting.fold)
                except ValueError:
                    continue  # approved gap policy: skip; never silently shift a clinical instant
                due = datetime.fromisoformat(resolved["due_at_utc"])
                if not max(now, utc(setting.effective_at)) <= due < horizon:
                    continue
                # Routine configuration start_date remains UTC under legacy contracts.
                if due.date() < entry.start_date:
                    continue
                identity = str(uuid5(NAMESPACE_URL, ":".join(["routine-occurrence-v1", setting.id,
                    str(setting.revision), entry.id, str(entry.revision), day.isoformat(), slot, str(resolved["fold"])])))
                if db.get(Notification, identity):
                    continue
                notice = Notification(id=identity, user_id=owner.id, kind="routine", source_id=entry.id,
                    source_revision=entry.revision, due_at=due, reminder_id=setting.id, reminder_revision=setting.revision)
                db.add(notice); db.flush()
                if pref.push_enabled:
                    for device in db.query(notifications.NotificationDevice).filter_by(user_id=owner.id, revoked_at=None):
                        if notifications.device_active(db, device, now):
                            db.add(NotificationJob(notification_id=identity, device_id=device.id, available_at=due))
                generated += 1
        setting.generated_at = now
    db.commit()
    return {"settings_processed": len(ids), "occurrences_created": generated, "horizon": horizon,
            "missed_occurrences": "not_backfilled", "live_delivery": "unavailable"}
