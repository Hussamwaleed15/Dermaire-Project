from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock
import pytest
from app.models import Capture, CheckIn, CaptureObservation, User, AuditLog, DoctorPatientAccess
from app.core.security import create_access_token
from app.services.azure_blob import azure_blob_service
from tests.test_account_deletion import deletion_context
from tests.test_postgres_gate import pg_engine, seed


def records(db, owner='delete-patient'):
    db.add(Capture(id='capture', user_id=owner, state='accepted', source='upload', view='front',
                   quality={}, storage='not_persisted', server_version='test'))
    db.add(CheckIn(id='observation', user_id=owner, date_str='2026-10-15', observation={
        'schema_version': 1, 'user_reported': {'overall_change': 'same'},
        'provenance': {'report': 'user_reported', 'created_at': 'server_recorded'}}))
    db.commit()


PATH = '/api/v1/captures/capture/observations/observation'


def test_explicit_selection_replay_retraction_and_doctor_grant(deletion_context):
    client, db, auth = deletion_context
    records(db)
    doctor = {'Authorization': 'Bearer '+create_access_token('delete-doctor', 'doctor', hashed_password='unused')}
    assert client.put(PATH, headers=auth, json={}).status_code == 422
    assert client.put(PATH, headers=auth, json={'associated': False}).status_code == 422
    assert client.put(PATH, headers=auth, json={'associated': 1}).status_code == 422
    first = client.put(PATH, headers=auth, json={'associated': True})
    assert first.status_code == 200, first.text
    assert first.json()['source'] == 'patient_selected' and first.json()['clinical_inference'] is False
    assert client.put(PATH, headers=auth, json={'associated': True}).json() == first.json()
    assert db.query(AuditLog).filter_by(action='CAPTURE_OBSERVATION_SELECTED').count() == 1
    assert client.get(PATH.rsplit('/', 1)[0], headers=doctor).status_code == 403
    grant = db.query(DoctorPatientAccess).one(); grant.status = 'active'; db.commit()
    assert client.get(PATH.rsplit('/', 1)[0], headers=doctor).json() == [first.json()]
    assert client.put(PATH, headers=doctor, json={'associated': True}).status_code == 403
    grant.status = 'revoked'; db.commit()
    assert client.get(PATH.rsplit('/', 1)[0], headers=doctor).status_code == 403
    assert client.delete(PATH, headers=auth).status_code == 204
    assert client.delete(PATH, headers=auth).status_code == 204
    assert client.get(PATH.rsplit('/', 1)[0], headers=auth).json() == []
    assert db.get(CheckIn, 'observation').observation['user_reported']['overall_change'] == 'same'


def test_owner_isolation_rejected_and_legacy_observation(deletion_context):
    client, db, auth = deletion_context
    records(db)
    assert client.put(PATH, json={'associated': True}).status_code == 401
    db.get(Capture, 'capture').user_id = 'delete-doctor'; db.commit()
    assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 404
    assert client.get(PATH.rsplit('/', 1)[0], headers=auth).status_code == 404
    db.get(Capture, 'capture').user_id = 'delete-patient'
    db.get(Capture, 'capture').state = 'rejected'; db.commit()
    assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 422
    db.get(Capture, 'capture').state = 'accepted'
    db.get(CheckIn, 'observation').observation = None; db.commit()
    assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 422
    assert db.query(CaptureObservation).count() == 0


def test_atomic_rollback_and_account_erasure(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    records(db)
    with monkeypatch.context() as patch:
        patch.setattr(db, 'commit', Mock(side_effect=RuntimeError('synthetic failure')))
        assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 503
    assert db.query(CaptureObservation).count() == 0
    assert db.query(AuditLog).filter_by(action='CAPTURE_OBSERVATION_SELECTED').count() == 0
    assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 200
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock())
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    assert client.delete('/api/v1/users/me', headers=auth).status_code == 204
    assert db.query(CaptureObservation).count() == 0
    assert client.get(PATH.rsplit('/', 1)[0], headers=auth).status_code == 401


def test_pg_parallel_selection_has_one_record_and_audit(pg_engine):
    from app.api.v1.capture_observations import select
    from app.schemas.capture_observations import CaptureObservationSelect
    factory = seed(pg_engine)
    with factory() as db:
        records(db, 'owner')
    def write(_):
        with factory() as db:
            return select('capture', 'observation', CaptureObservationSelect(associated=True), db.get(User, 'owner'), db).model_dump()
    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(write, range(2)))
    assert results[0] == results[1]
    with factory() as db:
        assert db.query(CaptureObservation).count() == 1
        assert db.query(AuditLog).filter_by(action='CAPTURE_OBSERVATION_SELECTED').count() == 1


def migration_rehearsal(engine, monkeypatch):
    from pathlib import Path
    from sqlalchemy.orm import Session
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    monkeypatch.setattr(settings, 'DATABASE_URL', engine.url.render_as_string(hide_password=False))
    cfg = Config(str(Path(__file__).parents[1] / 'alembic.ini'))
    command.upgrade(cfg, '20261015_01')
    with Session(engine) as db:
        db.add(User(id='owner', email='owner@synthetic.test', full_name='Synthetic', hashed_password='test-only'))
        db.commit(); records(db, 'owner')
    command.upgrade(cfg, 'head')
    command.check(cfg)
    with Session(engine) as db:
        assert db.get(CheckIn, 'observation').observation['user_reported']['overall_change'] == 'same'
        assert db.get(Capture, 'capture').state == 'accepted'
        db.add(CaptureObservation(id='link', user_id='owner', capture_id='capture', checkin_id='observation'))
        db.commit()
    with pytest.raises(RuntimeError, match='Cannot discard recorded'):
        command.downgrade(cfg, '20261015_01')
    with Session(engine) as db:
        assert db.get(CaptureObservation, 'link') is not None
        db.query(CaptureObservation).delete(); db.commit()
    command.downgrade(cfg, '20261015_01')
    command.upgrade(cfg, 'head')
    command.check(cfg)


def test_seeded_sqlite_association_migration(tmp_path, monkeypatch):
    from sqlalchemy import create_engine
    engine = create_engine('sqlite:///' + (tmp_path / 'association.db').as_posix())
    try:
        migration_rehearsal(engine, monkeypatch)
    finally:
        engine.dispose()


def test_pg_seeded_association_migration(pg_engine, monkeypatch):
    migration_rehearsal(pg_engine, monkeypatch)
