"""Account/filter bound, expiring cursor over immutable adherence records.

Timestamp cutoff excludes later writes, not transactions already in flight.
It is not an MVCC snapshot and must not be used as clinical snapshot evidence.
"""
from datetime import datetime, timedelta, timezone
import jwt
from fastapi import HTTPException
from sqlalchemy import and_, or_
from app.core.config import settings
from app.models import RoutineAdherence
from app.schemas.history import AdherenceHistoryPage
from app.services.temporal import utc

TYPE = 'routine_adherence_history_1'


def page(db, user, limit, cursor=None, routine_entry_id=None):
    now = datetime.now(timezone.utc)
    if cursor is None:
        state = {'type': TYPE, 'sub': user.id, 'entry_id': routine_entry_id,
                 'as_of': now.isoformat(), 'exp': int((now + timedelta(hours=1)).timestamp())}
    else:
        try:
            state = jwt.decode(cursor, settings.SECRET_KEY, algorithms=[settings.ALGORITHM],
                               options={'require': ['exp', 'sub', 'type', 'as_of', 'before_at', 'before_id']})
            if state['type'] != TYPE or state['sub'] != user.id or state.get('entry_id') != routine_entry_id:
                raise ValueError('Cursor scope mismatch')
            if not isinstance(state['before_id'], str) or not 1 <= len(state['before_id']) <= 36:
                raise ValueError('Cursor position invalid')
            if utc(datetime.fromisoformat(state['as_of'])) > now:
                raise ValueError('Future cutoff invalid')
            before = utc(datetime.fromisoformat(state['before_at'])).replace(tzinfo=None)
        except jwt.ExpiredSignatureError:
            raise HTTPException(410, 'History cursor expired; restart the history read')
        except (jwt.PyJWTError, ValueError, TypeError, KeyError):
            raise HTTPException(422, 'Invalid history cursor for this account and filter')
    cutoff = utc(datetime.fromisoformat(state['as_of']))
    query = db.query(RoutineAdherence).filter(RoutineAdherence.user_id == user.id,
        RoutineAdherence.created_at <= cutoff.replace(tzinfo=None))
    if routine_entry_id is not None:
        query = query.filter(RoutineAdherence.routine_entry_id == routine_entry_id)
    if cursor is not None:
        query = query.filter(or_(RoutineAdherence.created_at < before,
            and_(RoutineAdherence.created_at == before, RoutineAdherence.id < state['before_id'])))
    rows = query.order_by(RoutineAdherence.created_at.desc(), RoutineAdherence.id.desc()).limit(limit + 1).all()
    selected = rows[:limit]
    next_cursor = None
    if len(rows) > limit:
        state['before_at'] = utc(selected[-1].created_at).isoformat()
        state['before_id'] = selected[-1].id
        next_cursor = jwt.encode(state, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return AdherenceHistoryPage(as_of=cutoff, items=selected, next_cursor=next_cursor)
