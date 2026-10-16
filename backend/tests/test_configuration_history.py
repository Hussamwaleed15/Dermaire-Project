from datetime import timedelta
import pytest
from app.models.routine_history import RoutineConfigurationEvent
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create
from app.services import configuration_history
from fastapi import HTTPException


def test_configuration_writers_and_rollback(deletion_context):
    client, db, auth = deletion_context
    row = create(client, auth).json()
    path = '/api/v1/routine/entries/' + row['id']
    assert client.patch(path, headers=auth, json={'instructions': 'new evidence'}).status_code == 200
    assert client.patch('/api/v1/products/owned-product', headers=auth,
                        json={'name': 'updated evidence'}).status_code == 200
    assert client.delete(path, headers=auth).status_code == 204
    events = db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).all()
    assert [e.kind for e in events] == ['created', 'changed', 'product_evidence_changed', 'stopped']
    assert events[0].snapshot['product_evidence']['name'] != 'updated evidence'
    assert events[-1].snapshot['active'] is False
    assert events[-1].snapshot['provenance']['historical_backfill'] is False
    from app.models import RoutineEntry
    entry = db.get(RoutineEntry, row['id'])
    entry.instructions = 'rolled back'
    db.flush()
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 5
    db.rollback()
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 4
    events[0].kind = 'tampered'
    with pytest.raises(ValueError):
        db.flush()
    db.rollback()


def test_configuration_cursor_scope_and_append(deletion_context):
    client, db, auth = deletion_context
    row = create(client, auth).json()
    path = '/api/v1/routine/entries/' + row['id']
    client.patch(path, headers=auth, json={'instructions': 'second'})
    result = client.get('/api/v1/routine/configuration-history?limit=1', headers=auth)
    assert result.status_code == 200
    assert result.headers['cache-control'] == 'no-store'
    page = result.json()
    assert page['coverage'] == 'prospective_orm_writes_no_backfill'
    cursor = page['next_cursor']
    client.patch(path, headers=auth, json={'instructions': 'later'})
    older = client.get('/api/v1/routine/configuration-history', headers=auth,
                       params={'cursor': cursor, 'limit': 1}).json()
    assert older['items'][0]['kind'] == 'created'
    assert older['next_cursor'] is None
    assert client.get('/api/v1/routine/configuration-history', headers=auth,
        params={'cursor': cursor, 'routine_entry_id': row['id']}).status_code == 422
    from app.models import User
    other = db.get(User, 'delete-doctor')
    with pytest.raises(HTTPException) as error:
        configuration_history.page(db, other, 1, cursor)
    assert error.value.status_code == 422
    assert client.get('/api/v1/routine/configuration-history').status_code == 401


def test_configuration_deleted_with_account(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    row = create(client, auth).json()
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 1
    from app.services.account_deletion import delete_account
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(azure_blob_service, 'delete_image', lambda *args: None)
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', lambda *args: None)
    delete_account(db, 'delete-patient')
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 0


from tests.test_postgres_gate import pg_engine


@pytest.mark.parametrize('kind', ['same_field', 'different_fields', 'delete_update'])
def test_pg_configuration_event_cas_rollback(pg_engine, kind):
    from tests.test_routine_revisions import race
    from sqlalchemy.orm import Session
    race(pg_engine, kind)
    with Session(pg_engine) as db:
        events = db.query(RoutineConfigurationEvent).order_by(RoutineConfigurationEvent.created_at).all()
        # The losing ORM CAS transaction must not leak a historical event.
        assert len(events) == 2
        assert events[0].kind == 'created'
        assert events[1].kind == ('stopped' if not events[1].snapshot['active'] else 'changed')
        from app.models import RoutineEntry
        db.get(RoutineEntry, 'entry').instructions = 'rollback evidence'
        db.flush()
        assert db.query(RoutineConfigurationEvent).count() == 3
        db.rollback()
        assert db.query(RoutineConfigurationEvent).count() == 2

@pytest.mark.parametrize('rollback', [False, True])
def test_pg_routine_edit_transactionally_cancels_reminders(pg_engine, rollback):
    from tests.test_postgres_gate import seed
    from app.models import RoutineEntry, Product
    from app.models.notifications import Notification, NotificationJob, NotificationDevice
    from datetime import datetime, timezone, timedelta
    from app.services.routine import today
    factory = seed(pg_engine)
    at = datetime.now(timezone.utc)
    with factory() as db:
        db.add(Product(id='product', user_id='owner', name='Synthetic'))
        db.commit()
        db.add(RoutineEntry(id='entry', user_id='owner', product_id='product',
            schedule='AM', frequency='daily', start_date=today()))
        db.commit()
        db.add(NotificationDevice(id='device', user_id='owner', session_id='s', credential='c',
            session_expires_at=at+timedelta(days=1), token_hash='h', token_encrypted='encrypted', platform='ios'))
        db.add(Notification(id='notice', user_id='owner', kind='routine', source_id='entry', source_revision=1, due_at=at))
        db.commit()
        db.add(NotificationJob(id='job', notification_id='notice', device_id='device',
            state='leased', available_at=at, lease_token='fenced', lease_until=at+timedelta(minutes=1)))
        db.commit()
        db.get(RoutineEntry, 'entry').instructions = 'configuration change'
        db.flush()
        if rollback:
            db.rollback()
        else:
            db.commit()
        db.expire_all()
        assert (db.get(Notification, 'notice').cancelled_at is None) == rollback
        assert db.get(NotificationJob, 'job').state == ('leased' if rollback else 'cancelled')
        assert db.get(NotificationJob, 'job').lease_token == ('fenced' if rollback else None)

from tests.test_experiment_engine_v2 import context, draft


def test_configuration_experiment_intervention_attribution(context):
    client, db, auth, payload = context
    experiment = draft(context, intervention={'type': 'change_schedule', 'schedule': 'PM'}).json()
    assert client.post('/api/v1/experiments/' + experiment['id'] + '/activate', headers=auth).status_code == 200
    events = db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=payload['routine_entry_id']).all()
    event = next(e for e in events if e.snapshot['provenance'].get('writer_operation') == 'experiment.activate_intervention')
    assert event.snapshot['provenance']['experiment_id'] == experiment['id']
    assert event.snapshot['provenance']['intervention_type'] == 'change_schedule'
    assert event.snapshot['provenance']['actor_id'] == event.user_id
    assert event.snapshot['schedule'] == 'PM'


def test_configuration_product_archive_attribution_and_empty_freshness(deletion_context):
    client, db, auth = deletion_context
    route = '/api/v1/routine/configuration-history'
    empty = client.get(route, headers=auth).json()
    assert empty['coverage_since'] is None and empty['last_evidence_at'] is None
    row = create(client, auth).json()
    assert client.patch('/api/v1/products/owned-product', headers=auth, json={'status': 'archived'}).status_code == 200
    page = client.get(route, headers=auth).json()
    assert page['coverage_since'] and page['last_evidence_at']
    events = [e for e in page['items'] if e['routine_entry_id'] == row['id']]
    stop = next(e for e in events if e['kind'] == 'stopped')
    assert stop['snapshot']['provenance']['writer_operation'] == 'product.deactivate_routine'
    assert stop['snapshot']['provenance']['product_id'] == 'owned-product'
    assert stop['snapshot']['provenance']['actor_id'] == 'delete-patient'
    created = next(e for e in events if e['kind'] == 'created')
    assert created['snapshot']['provenance']['writer_operation'] == 'routine.create'


def test_configuration_source_harddelete_cascades_private_events(deletion_context):
    client, db, auth = deletion_context
    from app.models import RoutineEntry
    row = create(client, auth).json()
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 1
    db.delete(db.get(RoutineEntry, row['id']))
    db.commit()
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 0


def test_signed_product_replay_erases_orphan_history_owner_scoped(deletion_context):
    client, db, auth = deletion_context
    from app.models import Product, RoutineEntry
    from app.services.deletion_journal import DeletionJournal
    from tests.test_deletion_journal import Container
    from unittest.mock import Mock
    row = create(client, auth).json()
    db.add(Product(id='other-product', user_id='delete-doctor', name='Other owner'))
    db.commit()
    db.add(RoutineEntry(id='other-entry', user_id='delete-doctor', product_id='other-product',
        schedule='AM', frequency='daily', start_date=__import__('datetime').date.today()))
    db.commit()
    # Simulate restored historical evidence of a removed product while current
    # routines refer to surviving products; the erased product row is absent.
    db.add_all([RoutineConfigurationEvent(id='orphan-history', user_id='delete-patient',
        routine_entry_id=row['id'], source_product_id='removed-product', kind='changed',
        snapshot={'product_evidence': {'name': 'Private restored evidence'}}),
        RoutineConfigurationEvent(id='other-owner-history', user_id='delete-doctor',
        routine_entry_id='other-entry', source_product_id='removed-product', kind='changed',
        snapshot={'product_evidence': {'name': 'Preserve unrelated owner'}})])
    db.commit()
    journal = DeletionJournal(Container(), 'j'*32, True)
    journal.record_product('delete-patient', 'removed-product')
    storage = Mock(is_live=True)
    storage.container_client.list_blobs.return_value = []
    journal.replay(db, storage, Mock())
    assert db.query(RoutineConfigurationEvent).filter_by(id='orphan-history').count() == 0
    assert db.query(RoutineConfigurationEvent).filter_by(id='other-owner-history').count() == 1
    assert db.query(RoutineConfigurationEvent).filter_by(routine_entry_id=row['id']).count() == 1
    # Normal product erasure uses the same exact typed owner/product scope.
    from app.services.product_attempts import erase_results
    erase_results(db, 'delete-doctor', 'removed-product')
    db.commit()
    assert db.query(RoutineConfigurationEvent).filter_by(id='other-owner-history').count() == 0
