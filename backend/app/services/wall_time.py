"""Explicit wall-time resolution shared by clinician plans and reminders.

Stored UTC instants are never reinterpreted after travel or tzdata changes.
"""
from datetime import datetime, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


def resolve_due(local: datetime, zone: str, fold: int | None = None) -> dict:
    if local.tzinfo is not None:
        raise ValueError("Submit a local wall time without an offset")
    if fold is not None and (type(fold) is not int or fold not in (0, 1)):
        raise ValueError("fold must be 0 or 1")
    try:
        tz = ZoneInfo(zone)
    except (ZoneInfoNotFoundError, ValueError, TypeError):
        raise ValueError("Unknown IANA timezone") from None
    candidates = {}
    for choice in (0, 1):
        instant = local.replace(tzinfo=tz, fold=choice).astimezone(timezone.utc)
        back = instant.astimezone(tz)
        if back.replace(tzinfo=None) == local and back.fold == choice:
            candidates[choice] = instant
    if not candidates:
        raise ValueError("Nonexistent local time; choose another time")
    if len(candidates) > 1 and fold is None:
        raise ValueError("Ambiguous local time; explicit fold required")
    choice = fold if fold is not None else next(iter(candidates))
    if choice not in candidates:
        raise ValueError("fold does not identify this local time")
    return {"due_at_utc": candidates[choice].isoformat(), "timezone": zone,
            "local_time": local.isoformat(), "fold": choice,
            "policy": "fixed_utc_explicit_reschedule_v1"}


def quiet_at(instant: datetime, zone: str, start_minute: int, end_minute: int) -> bool:
    """Half-open wall-clock interval; equal endpoints mean disabled, not all day."""
    if instant.tzinfo is None or instant.utcoffset() is None:
        raise ValueError("Aware instant required")
    if any(type(v) is not int or not 0 <= v < 1440 for v in (start_minute, end_minute)):
        raise ValueError("Quiet hours require minutes in 0..1439")
    local = instant.astimezone(ZoneInfo(zone))
    minute = local.hour * 60 + local.minute
    if start_minute == end_minute:
        return False
    if start_minute < end_minute:
        return start_minute <= minute < end_minute
    return minute >= start_minute or minute < end_minute
