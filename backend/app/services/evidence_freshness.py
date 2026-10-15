from datetime import timedelta
from app.schemas.freshness import EvidenceFreshness
from app.services.temporal import utc


def freshness(when, now):
    now = utc(now)
    when = utc(when) if when else None
    state = ('missing' if when is None else 'unknown' if when > now else
             'stale' if now - when > timedelta(days=14) else 'fresh')
    return EvidenceFreshness(as_of=now, latest_at=when,
        age_days=(now.date()-when.date()).days if when and when <= now else None,
        state=state).model_dump()
