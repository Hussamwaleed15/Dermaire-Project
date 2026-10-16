"""Account/filter bound, expiring cursor over immutable adherence records.

Timestamp cutoff excludes later writes, not transactions already in flight.
It is not an MVCC snapshot and must not be used as clinical snapshot evidence.
"""
from datetime import datetime, timedelta, timezone
import jwt
from fastapi import HTTPException
from sqlalchemy import and_, or_, func
from app.core.config import settings
from app.models.routine_history import RoutineConfigurationEvent
from app.schemas.history import ConfigurationHistoryPage
from app.services.temporal import utc

TYPE = 'routine_configuration_history_1'


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
            cutoff_value = datetime.fromisoformat(state['as_of'])
            before_value = datetime.fromisoformat(state['before_at'])
            if cutoff_value.tzinfo is None or before_value.tzinfo is None:
                raise ValueError('Cursor timestamps require an offset')
            if type(state['exp']) is not int or state['exp'] != int(cutoff_value.timestamp()) + 3600:
                raise ValueError('Cursor lifetime invalid')
            if utc(before_value) > utc(cutoff_value):
                raise ValueError('Position exceeds cutoff')
            if utc(cutoff_value) > now:
                raise ValueError('Future cutoff invalid')
            before = utc(datetime.fromisoformat(state['before_at'])).replace(tzinfo=None)
        except jwt.ExpiredSignatureError:
            raise HTTPException(410, 'History cursor expired; restart the history read')
        except (jwt.PyJWTError, ValueError, TypeError, KeyError):
            raise HTTPException(422, 'Invalid history cursor for this account and filter')
    cutoff = utc(datetime.fromisoformat(state['as_of']))
    query = db.query(RoutineConfigurationEvent).filter(RoutineConfigurationEvent.user_id == user.id,
        RoutineConfigurationEvent.created_at <= cutoff.replace(tzinfo=None))
    if routine_entry_id is not None:
        query = query.filter(RoutineConfigurationEvent.routine_entry_id == routine_entry_id)
    coverage_since, last_evidence_at = query.with_entities(
        func.min(RoutineConfigurationEvent.created_at), func.max(RoutineConfigurationEvent.created_at)).one()
    if cursor is not None:
        query = query.filter(or_(RoutineConfigurationEvent.created_at < before,
            and_(RoutineConfigurationEvent.created_at == before, RoutineConfigurationEvent.id < state['before_id'])))
    rows = query.order_by(RoutineConfigurationEvent.created_at.desc(), RoutineConfigurationEvent.id.desc()).limit(limit + 1).all()
    selected = rows[:limit]
    next_cursor = None
    if len(rows) > limit:
        state['before_at'] = utc(selected[-1].created_at).isoformat()
        state['before_id'] = selected[-1].id
        next_cursor = jwt.encode(state, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    return ConfigurationHistoryPage(as_of=cutoff, items=selected, next_cursor=next_cursor,
        coverage_since=utc(coverage_since) if coverage_since else None,
        last_evidence_at=utc(last_evidence_at) if last_evidence_at else None)
