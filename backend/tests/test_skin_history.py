import json
from datetime import datetime, timezone
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from app.main import app
from tests.test_account_deletion import deletion_context
from app.models import CheckIn, DailyContext, User
from app.core.security import create_access_token
from app.services.azure_blob import azure_blob_service
from app.services.azure_vision import azure_vision_service


def submit(client, auth, **fields):
    return client.post('/api/v1/checkins', headers=auth, data={
        'report': json.dumps({'overall_change': 'same', 'symptoms': ['dryness'],
                              'routine_status': 'partial'}), **fields})


def test_report_without_measurements_and_context(deletion_context):
    client, db, auth = deletion_context
    response = submit(client, auth, notes='بشرتي اليوم')
    assert response.status_code == 201
    row = response.json()
    assert row['notes'] == 'بشرتي اليوم'
    assert row['hydration_score'] is None and row['image_sas_url'] is None
    evidence = row['observation']
    assert evidence['schema_version'] == 1
    assert evidence['daily_context_id'] is None
    assert evidence['daily_context_date'] == datetime.now(timezone.utc).date().isoformat()
    assert evidence['provenance']['measurements'] == 'not_recorded'
    assert evidence['provenance']['report'] == 'user_reported'
    db.expire_all()
    assert client.get('/api/v1/checkins', headers=auth).json() == [row]
    assert client.get('/api/v1/baseline', headers=auth).json()['completed_days'] == 0


def test_context_owner_ordering_and_legacy_quarantine(deletion_context):
    client, db, auth = deletion_context
    today = datetime.now(timezone.utc).date()
    db.add(DailyContext(id='foreign-context', user_id='delete-doctor', date=today))
    db.commit()
    first = submit(client, auth).json()
    assert first['observation']['daily_context_id'] is None
    db.add(DailyContext(id='own-context', user_id='delete-patient', date=today, unusual_conditions=True))
    db.commit()
    second = submit(client, auth).json()
    assert second['observation']['daily_context_id'] == 'own-context'
    # Stable tie break, independent of UUID generation and insertion order.
    for ident, row in [('a', first), ('z', second)]:
        saved = db.get(CheckIn, row['id'])
        saved.id = ident
        saved.created_at = datetime(2026, 1, 1)
    db.commit()
    assert [r['id'] for r in client.get('/api/v1/checkins', headers=auth).json()] == ['z', 'a']
    other = {'Authorization': 'Bearer ' + create_access_token('delete-doctor', 'doctor', hashed_password='unused')}
    assert client.get('/api/v1/checkins', headers=other).json() == []
    assert client.get('/api/v1/checkins').status_code == 401
    assert client.post('/api/v1/checkins', headers=other, data={'report': json.dumps({'overall_change': 'better'}),
        'experiment_id': 'owned-experiment'}).status_code == 404


@pytest.mark.parametrize('report', ['{}', '{', '{"overall_change":"great"}',
    '{"overall_change":"same","user_id":"other"}', '{"overall_change":"same","symptoms":["unknown"]}'])
def test_invalid_reports_do_not_save(deletion_context, report):
    client, db, auth = deletion_context
    before = db.query(CheckIn).count()
    assert submit(client, auth, report=report).status_code == 422
    assert db.query(CheckIn).count() == before


def test_manual_provenance_and_invalid_partial_scores(deletion_context):
    client, db, auth = deletion_context
    assert submit(client, auth, hydration_score=50).status_code == 422
    row = submit(client, auth, hydration_score=50, texture_score=60, redness_score=20).json()
    assert row['observation']['provenance']['measurements'] == 'user_reported'
    assert row['observation']['user_reported']['overall_change'] == 'same'


def test_failure_and_deletion_cleanup(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    commit = db.commit
    monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('Unavailable')))
    before = db.query(CheckIn).count()
    with pytest.raises(RuntimeError):
        submit(client, auth)
    db.rollback()
    assert db.query(CheckIn).count() == before
    monkeypatch.setattr(db, 'commit', commit)
    assert submit(client, auth).status_code == 201
    db.add(DailyContext(user_id='delete-patient', date=datetime.now(timezone.utc).date()))
    db.commit()
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock())
    assert client.delete('/api/v1/users/me', headers=auth).status_code == 204
    assert db.query(CheckIn).count() == 0
    assert db.query(DailyContext).count() == 0
    assert db.get(User, 'delete-doctor') is not None


def test_history_read_failure_is_not_empty_success(deletion_context, monkeypatch):
    _, db, auth = deletion_context
    query = db.query
    def unavailable(model):
        if model is CheckIn:
            raise RuntimeError('Unavailable')
        return query(model)
    monkeypatch.setattr(db, 'query', unavailable)
    with TestClient(app, raise_server_exceptions=False) as client:
        assert client.get('/api/v1/checkins', headers=auth).status_code == 500


def test_photo_report_keeps_derived_provenance_and_link(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    monkeypatch.setattr(azure_vision_service, 'analyze_skin_image', Mock(return_value={
        'azure_vision_status': 'ANALYSIS_COMPLETE', 'estimated_hydration_score': 80,
        'surface_texture_score': 60, 'erythema_redness_score': 20}))
    monkeypatch.setattr(azure_blob_service, 'upload_image', Mock(return_value=('owned-photo', 'photo-url')))
    monkeypatch.setattr(azure_blob_service, 'generate_sas_url', Mock(return_value='photo-url'))
    response = client.post('/api/v1/checkins', headers=auth,
        data={'report': json.dumps({'overall_change': 'worse', 'symptoms': ['redness']})},
        files={'photo': ('skin.jpg', b'image', 'image/jpeg')})
    assert response.status_code == 201
    row = response.json()
    assert row['observation']['provenance']['measurements'] == 'system_derived'
    assert row['observation']['provenance']['photo'] == 'user_uploaded'
    assert row['image_sas_url'] == 'photo-url'
    assert db.get(CheckIn, row['id']).image_blob_name == 'owned-photo'
    assert client.get('/api/v1/checkins', headers=auth).json()[0] == row
