from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import pytest
from app.core.security import create_access_token, create_refresh_token
from app.models import RoutineEntry, RoutineAdherence
from app.services.azure_blob import azure_blob_service
from tests.test_account_deletion import deletion_context

ROOT = '/api/v1/routine'
def day():
    return datetime.now(timezone.utc).date().isoformat()
def create(client, auth, **changes):
    data = dict(product_id='owned-product', schedule='AM', frequency='daily', start_date=day(), instructions='User note')
    data.update(changes)
    return client.post(ROOT+'/entries', headers=auth, json=data)
def report(client, auth, entry, **changes):
    data = dict(routine_entry_id=entry['id'], date=day(), slot='AM', status='completed', note='Reported')
    data.update(changes)
    return client.post(ROOT+'/adherence', headers=auth, json=data)

def test_lifecycle_and_snapshot(deletion_context):
    client, db, auth = deletion_context
    assert client.get(ROOT+'/entries', headers=auth).json() == []
    response = create(client, auth)
    assert response.status_code == 201
    entry = response.json()
    assert entry['source'] == 'user_configured' and entry['active'] and entry['created_at']
    path = ROOT+'/entries/'+entry['id']
    assert client.get(path, headers=auth).json() == entry
    response = report(client, auth, entry)
    assert response.status_code == 201
    evidence = response.json()
    assert evidence['source'] == 'user_reported' and evidence['configuration_snapshot']['instructions'] == 'User note'
    assert client.patch(path, headers=auth, json={'instructions':'Edited', 'schedule':'BOTH', 'am_order':2, 'pm_order':3}).status_code == 200
    assert report(client, auth, entry, slot='PM', status='skipped').status_code == 201
    assert evidence in client.get(ROOT+'/adherence', headers=auth).json()
    assert client.patch(path, headers=auth, json={'active':False}).status_code == 200
    stopped = client.get(path, headers=auth).json()
    assert not stopped['active'] and stopped['end_date'] == day()
    assert len(client.get(ROOT+'/entries?active=false', headers=auth).json()) == 1
    assert client.get(ROOT+'/entries?active=true', headers=auth).json() == []
    assert report(client, auth, entry).status_code == 409
    assert client.patch(path, headers=auth, json={'instructions':'Rewrite'}).status_code == 409
    assert client.delete(path, headers=auth).status_code == 204
    assert client.delete(path, headers=auth).status_code == 204
    assert db.query(RoutineAdherence).count() == 2
    assert create(client, auth).status_code == 201

@pytest.mark.parametrize('change', [
    {'schedule':'morning'}, {'schedule':None}, {'frequency':'weekly'}, {'frequency':None},
    {'start_date':'invalid'}, {'start_date':'2099-01-01'}, {'am_order':-1}, {'pm_order':101},
    {'instructions':'x'*2001}, {'active':True}, {'source':'verified'}, {'product_id':''},
])
def test_invalid_configuration(deletion_context, change):
    client, db, auth = deletion_context
    assert create(client, auth, **change).status_code == 422
    assert db.query(RoutineEntry).count() == 0

@pytest.mark.parametrize('patch', [{'active':True}, {'active':None}, {'schedule':None}, {'schedule':'x'}, {'frequency':'weekly'}, {'start_date':'2020-01-01'}, {'product_id':'other'}, {'am_order':None}])
def test_invalid_edits(deletion_context, patch):
    client, db, auth = deletion_context
    entry = create(client, auth).json()
    assert client.patch(ROOT+'/entries/'+entry['id'], json=patch, headers=auth).status_code == 422
    assert client.get(ROOT+'/entries/'+entry['id'], headers=auth).json() == entry

@pytest.mark.parametrize('change', [{'date':'2099-01-01'}, {'date':'2020-01-01'}, {'date':'invalid'}, {'slot':'BOTH'}, {'slot':'PM'}, {'status':'partial'}, {'source':'automatic'}, {'note':'x'*2001}])
def test_invalid_adherence(deletion_context, change):
    client, db, auth = deletion_context
    entry = create(client, auth).json()
    assert report(client, auth, entry, **change).status_code == 422
    assert db.query(RoutineAdherence).count() == 0

def test_conflicts_and_distinct_slots(deletion_context):
    client, db, auth = deletion_context
    am = create(client, auth).json()
    assert create(client, auth).status_code == 409
    assert create(client, auth, schedule='BOTH').status_code == 409
    assert create(client, auth, schedule='PM').status_code == 201
    assert client.patch(ROOT+'/entries/'+am['id'], headers=auth, json={'schedule':'BOTH'}).status_code == 409
    assert client.get(ROOT+'/entries/'+am['id'], headers=auth).json()['schedule'] == 'AM'
    assert report(client, auth, am).status_code == 201
    assert report(client, auth, am, status='skipped').status_code == 409
    assert client.get(ROOT+'/adherence?limit=1&offset=0', headers=auth).json()[0]['status'] == 'completed'
    assert client.get(ROOT+'/adherence?limit=0', headers=auth).status_code == 422

def test_isolation_and_product_ownership(deletion_context):
    client, db, auth = deletion_context
    other = {'Authorization':'Bearer '+create_access_token('delete-doctor', 'doctor', hashed_password='unused')}
    assert create(client, other).status_code == 404
    assert create(client, auth, product_id='missing').status_code == 404
    entry = create(client, auth).json()
    assert report(client, auth, entry).status_code == 201
    assert client.get(ROOT+'/entries', headers=other).json() == []
    assert client.get(ROOT+'/adherence', headers=other).json() == []
    path = ROOT+'/entries/'+entry['id']
    assert client.get(path, headers=other).status_code == 404
    assert client.patch(path, headers=other, json={'active':False}).status_code == 404
    assert client.delete(path, headers=other).status_code == 404
    assert report(client, other, entry).status_code == 404
    assert client.get(ROOT+'/adherence?routine_entry_id='+entry['id'], headers=other).status_code == 404

@pytest.mark.parametrize('authorization', [None, 'Bearer invalid', 'refresh'])
def test_auth(deletion_context, authorization):
    client, db, auth = deletion_context
    if authorization == 'refresh':
        authorization = 'Bearer '+create_refresh_token('delete-patient')
    headers = {'Authorization':authorization} if authorization else {}
    assert client.get(ROOT+'/entries', headers=headers).status_code == 401
    assert client.get(ROOT+'/adherence', headers=headers).status_code == 401
    assert create(client, headers).status_code == 401
    assert report(client, headers, {'id':'missing'}).status_code == 401

def test_product_archive_preserves_history_and_blocks_delete(deletion_context):
    client, db, auth = deletion_context
    entry = create(client, auth).json()
    evidence = report(client, auth, entry).json()
    path = '/api/v1/products/owned-product'
    assert client.delete(path, headers=auth).status_code == 409
    assert client.patch(path, headers=auth, json={'status':'inactive'}).status_code == 200
    assert not client.get(ROOT+'/entries/'+entry['id'], headers=auth).json()['active']
    assert client.get(ROOT+'/adherence', headers=auth).json() == [evidence]
    assert create(client, auth).status_code == 409
    assert client.patch(path, headers=auth, json={'status':'active'}).status_code == 200
    assert not client.get(ROOT+'/entries/'+entry['id'], headers=auth).json()['active']
    assert create(client, auth).status_code == 201

def test_no_implicit_adherence_or_backdated_configuration(deletion_context):
    client, db, auth = deletion_context
    earlier = (datetime.now(timezone.utc).date()-timedelta(days=1)).isoformat()
    entry = create(client, auth, start_date=earlier).json()
    assert report(client, auth, entry, date=earlier).status_code == 422
    assert client.get(ROOT+'/adherence', headers=auth).json() == []
    assert client.delete(ROOT+'/entries/'+entry['id'], headers=auth).status_code == 204
    assert client.get(ROOT+'/entries/'+entry['id'], headers=auth).json()['end_date'] == day()

def test_account_cleanup_and_session(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    entry = create(client, auth).json()
    assert report(client, auth, entry).status_code == 201
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock())
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    assert client.delete('/api/v1/users/me', headers=auth).status_code == 204
    assert db.query(RoutineEntry).count() == db.query(RoutineAdherence).count() == 0
    assert client.get(ROOT+'/entries', headers=auth).status_code == 401
    assert client.get(ROOT+'/adherence', headers=auth).status_code == 401

def test_failed_commit_cannot_return_success(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('unavailable')))
    assert create(client, auth).status_code == 503
    db.rollback()
    assert db.query(RoutineEntry).count() == 0


def test_manual_sqlite_upgrade_preserves_inventory(tmp_path):
    from pathlib import Path
    from sqlalchemy import create_engine, inspect
    from sqlalchemy.orm import Session
    from app.core.database import Base
    from app.models import User, Product
    engine = create_engine('sqlite:///'+str(tmp_path/'upgrade.db'))
    old_tables = [table for table in Base.metadata.sorted_tables if table.name not in ('routine_entries', 'routine_adherence')]
    Base.metadata.create_all(engine, tables=old_tables)
    with Session(engine) as db:
        db.add(User(id='upgrade', email='upgrade@example.com', full_name='Owner', hashed_password='unused'))
        db.commit()
        db.add(Product(id='existing', user_id='upgrade', name='Inventory'))
        db.commit()
    sql = (Path(__file__).resolve().parents[2]/'docs/migrations/routine-model-v1-sqlite.sql').read_text()
    raw = engine.raw_connection()
    try:
        raw.driver_connection.executescript(sql)
    finally:
        raw.close()
    with Session(engine) as db:
        assert db.query(Product).one().name == 'Inventory'
        assert db.query(RoutineEntry).count() == db.query(RoutineAdherence).count() == 0
        db.add(RoutineEntry(user_id='upgrade', product_id='existing', schedule='BOTH', frequency='daily', start_date=datetime.now(timezone.utc).date(), active_am_product='existing', active_pm_product='existing'))
        db.commit()
        assert db.query(RoutineEntry).one().product_name == 'Inventory'
    assert {c['name'] for c in inspect(engine).get_columns('routine_entries')} == set(RoutineEntry.__table__.columns.keys())
    engine.dispose()
