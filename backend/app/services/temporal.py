"""Existing UTC calendar contract; naive persisted instants mean UTC."""
from datetime import datetime, timezone


def utc(value: datetime) -> datetime:
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def utc_day(value: datetime):
    return utc(value).date()
