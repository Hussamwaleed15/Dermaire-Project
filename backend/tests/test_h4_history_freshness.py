from datetime import datetime, timedelta, timezone
import jwt
import pytest
from app.core.config import settings
from app.models import RoutineAdherence
from app.services.evidence_freshness import freshness
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create
from tests.test_postgres_gate import pg_engine, seed


@pytest.mark.parametrize('age,state', [(None,'missing'),(-1,'unknown'),(0,'fresh'),(14,'fresh'),(15,'stale')])
def test_freshness_boundaries_and_future_unknown(age, state):
    now = datetime(2026, 10, 15, 12, tzinfo=timezone.utc)
    value = freshness(now-timedelta(days=age) if age is not None else None, now)
    assert value['state'] == state
    assert value['as_of'] == now and value['threshold_days'] == 14
    if state in ('missing', 'unknown'):
        assert value['age_days'] is None


def history_rows(db, entry_id, owner='delete-patient'):
    at = datetime.now(timezone.utc).replace(tzinfo=None)-timedelta(days=1)
    for i in range(4):
        db.add(RoutineAdherence(id='history-'+str(i), user_id=owner, routine_entry_id=entry_id,
            date=at.date()-timedelta(days=i), slot='AM', status='completed',
            created_at=at, configuration_snapshot={}))
    db.commit()


def test_cursor_account_filter_ties_tamper_and_later_insert(deletion_context):
    client, db, auth = deletion_context
    entry = create(client, auth).json()
    history_rows(db, entry['id'])
    path = '/api/v1/routine/adherence/history'
    first = client.get(path, params={'limit': 2}, headers=auth)
    assert first.status_code == 200, first.text
    data = first.json(); token = data['next_cursor']
    assert [i['id'] for i in data['items']] == ['history-3', 'history-2']
    db.add(RoutineAdherence(id='later', user_id='delete-patient', routine_entry_id=entry['id'],
        date=datetime.now(timezone.utc).date(), slot='PM', status='skipped', configuration_snapshot={}))
    db.commit()
    second = client.get(path, params={'cursor': token, 'limit': 2}, headers=auth).json()
    assert second['as_of'] == data['as_of']
    assert [i['id'] for i in second['items']] == ['history-1', 'history-0']
    assert second['next_cursor'] is None
    assert client.get(path, params={'cursor': token, 'routine_entry_id':entry['id']}, headers=auth).status_code == 422
    assert client.get(path, params={'cursor': token+'invalid'}, headers=auth).status_code == 422
    from app.core.security import create_access_token
    other = {'Authorization':'Bearer '+create_access_token('delete-doctor', 'doctor', hashed_password='unused')}
    assert client.get(path, params={'cursor': token}, headers=other).status_code == 422
    assert client.get(path).status_code == 401
    state = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    state['exp'] = 1
    expired = jwt.encode(state, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    assert client.get(path, params={'cursor': expired}, headers=auth).status_code == 410


def test_pg_cursor_tie_order_and_cutoff(pg_engine):
    from app.models import Product, RoutineEntry, User
    from app.services.adherence_history import page
    factory = seed(pg_engine)
    with factory() as db:
        db.add(Product(id='p', user_id='owner', name='Synthetic')); db.commit()
        db.add(RoutineEntry(id='entry', user_id='owner', product_id='p', schedule='AM', frequency='daily', start_date=datetime.now().date()))
        db.commit(); history_rows(db, 'entry', 'owner')
        first = page(db, db.get(User,'owner'), 2)
        second = page(db, db.get(User,'owner'), 2, first.next_cursor)
        assert [i.id for i in first.items+second.items] == ['history-3','history-2','history-1','history-0']
        assert first.as_of == second.as_of and second.next_cursor is None


def test_psm_future_profile_is_unknown_not_fresh(deletion_context):
    from app.models import User
    client, db, auth = deletion_context
    db.get(User, 'delete-patient').updated_at = datetime.now(timezone.utc) + timedelta(days=1)
    db.commit()
    response = client.get('/api/v1/personal-skin-model', headers=auth)
    assert response.status_code == 200, response.text
    data = response.json()
    assert data['sources']['profile']['freshness']['state'] == 'unknown'
    assert data['sources']['profile']['freshness']['age_days'] is None
    assert any('future source timestamp' in reason for reason in data['unknowns'])
