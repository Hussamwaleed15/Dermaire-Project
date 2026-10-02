from io import BytesIO
from pathlib import Path
from unittest.mock import Mock
import pytest
from PIL import Image, ImageFilter
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi.testclient import TestClient
from app.main import app
from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.models import User, Capture
from app.services import capture_quality as gate
from app.services.azure_blob import azure_blob_service, AzureBlobService


@pytest.fixture
def photograph():
    # Public-domain NASA image from scikit-image; no detector mocking in positive test.
    return Image.open(Path(__file__).parent / 'fixtures/astronaut.png').crop((80, 0, 340, 320)).resize((800, 1000))


def encoded(image):
    stream = BytesIO()
    image.save(stream, format='PNG')
    return stream.getvalue()


def test_real_detector_accepts(photograph):
    result = gate.assess(photograph, 1)
    assert result['decision'] == 'accepted', result['reasons']
    assert result['checks']['face']['metrics']['detected_count'] == 1
    for key in ('yaw', 'pitch', 'occlusion', 'uneven_lighting'):
        assert result['checks'][key]['status'] == 'unknown'
    assert result == gate.assess(photograph, 1)


def test_real_blur_rejected(photograph):
    result = gate.assess(photograph.filter(ImageFilter.GaussianBlur(12)), 1)
    assert result['decision'] == 'rejected'
    assert result['checks']['sharpness']['status'] == 'fail'
    assert any('Hold still' in reason for reason in result['reasons'])


@pytest.mark.parametrize('color', [0, 255])
def test_exposure_rejection(color):
    result = gate.assess(Image.new('RGB', (800, 1000), (color,)*3), 1)
    assert result['checks']['exposure']['status'] == 'fail'
    assert result['decision'] == 'rejected'


@pytest.mark.parametrize('size,orientation', [((300, 400), 1), ((1000, 800), 1), ((800, 1000), 6)])
def test_resolution_orientation(photograph, size, orientation):
    result = gate.assess(photograph.resize(size), orientation)
    assert result['decision'] == 'rejected'
    assert result['checks']['resolution' if min(size) < 640 else 'orientation']['status'] == 'fail'


@pytest.mark.parametrize('face,eyes,check', [
    ((5, 5, 220, 220), [(60, 60), (160, 60)], 'framing'),
    ((280, 310, 80, 80), [(300, 330), (335, 330)], 'scale'),
    ((80, 100, 500, 500), [(200, 200), (400, 200)], 'scale'),
    ((200, 220, 240, 240), [(260, 275), (370, 305)], 'roll'),
    ((200, 220, 240, 240), [], 'coarse_front_view'),
])
def test_geometry_rules(photograph, monkeypatch, face, eyes, check):
    # Isolate geometry boundaries; positive integration above uses real cascades.
    monkeypatch.setattr(gate, 'detect_geometry', lambda _: ([face], eyes))
    result = gate.assess(photograph, 1)
    assert result['decision'] == 'rejected'
    assert result['checks'][check]['status'] != 'pass'
    assert result['reasons']


@pytest.fixture
def context(monkeypatch):
    engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
    @event.listens_for(engine, 'connect')
    def fk(connection, _):
        connection.execute('PRAGMA foreign_keys=ON')
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    users = [User(id=f'capture-user-{i}', email=f'capture{i}@example.com', hashed_password='unused', full_name='Test') for i in range(2)]
    db.add_all(users); db.commit()
    headers = [{'Authorization': 'Bearer ' + create_access_token(u.id, 'patient', hashed_password=u.hashed_password)} for u in users]
    app.dependency_overrides[get_db] = lambda: db
    monkeypatch.setattr(azure_blob_service, 'is_live', False)
    with TestClient(app) as client:
        yield client, db, headers
    app.dependency_overrides.clear()
    db.close(); engine.dispose()


def upload(client, headers, data, content_type='image/png', fields=None):
    return client.post('/api/v1/captures', headers=headers, files={'photo': ('private.png', data, content_type)}, data=fields or {})


def test_capture_provenance_isolation_deletion(context, photograph, monkeypatch):
    client, db, headers = context
    no_upload = Mock(side_effect=AssertionError('Must not use mock storage'))
    monkeypatch.setattr(azure_blob_service, 'upload_capture', no_upload)
    res = upload(client, headers[0], encoded(photograph))
    assert res.status_code == 201, res.text
    row = res.json()
    assert row['state'] == 'accepted'
    assert row['storage'] == 'not_persisted' and row['image_reference'] is None
    assert row['provenance']['quality'] == 'server_computed'
    assert row['received_at'].endswith('+00:00')
    assert 'diagnosis' not in row and 'hydration_score' not in row
    assert client.get('/api/v1/captures/' + row['id'], headers=headers[1]).status_code == 404
    assert client.get('/api/v1/captures', headers=headers[1]).json() == []
    assert client.get('/api/v1/captures?state=accepted', headers=headers[0]).json()[0]['id'] == row['id']
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    assert client.delete('/api/v1/users/me', headers=headers[0]).status_code == 204
    assert db.query(Capture).count() == 0
    no_upload.assert_not_called()


@pytest.mark.parametrize('data,mime,status', [(b'corrupt', 'image/png', 422), (b'GIF89a', 'image/gif', 415), (b'x'*(8*1024*1024+1), 'image/png', 413)], ids=['corrupt','unsupported','oversized'])
def test_invalid_image_no_rows(context, data, mime, status):
    client, db, headers = context
    assert upload(client, headers[0], data, mime).status_code == status
    assert db.query(Capture).count() == 0


@pytest.mark.parametrize('fields', [{'view':'left'}, {'source':'unknown'}])
def test_invalid_fields_no_rows(context, photograph, fields):
    client, db, headers = context
    assert upload(client, headers[0], encoded(photograph), fields=fields).status_code == 422
    assert db.query(Capture).count() == 0


def test_unauthenticated(context, photograph):
    client, db, _ = context
    assert upload(client, {}, encoded(photograph)).status_code == 401
    assert db.query(Capture).count() == 0


def test_rejected_retains_metadata_only(context):
    client, db, headers = context
    row = upload(client, headers[0], encoded(Image.new('RGB', (100, 100)))).json()
    assert row['state'] == 'rejected' and row['quality']['reasons']
    assert row['image_reference'] is None
    assert db.query(Capture).count() == 1


def test_detector_failure_no_fallback(context, photograph, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(gate, 'detect_geometry', Mock(side_effect=RuntimeError('unavailable')))
    assert upload(client, headers[0], encoded(photograph)).status_code == 503
    assert db.query(Capture).count() == 0


def test_live_storage_and_deletion(context, photograph, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(azure_blob_service, 'is_live', True)
    store, delete = Mock(), Mock()
    monkeypatch.setattr(azure_blob_service, 'upload_capture', store)
    monkeypatch.setattr(azure_blob_service, 'delete_image', delete)
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    res = upload(client, headers[0], encoded(photograph)).json()
    assert res['storage'] == 'azure_blob'
    key, data = store.call_args.args
    assert key.startswith('skin_photos/capture-user-0/')
    assert Image.open(BytesIO(data)).getexif() == {}
    assert Image.open(BytesIO(data)).tobytes() == photograph.convert('RGB').tobytes()
    read = Mock(return_value=data)
    monkeypatch.setattr(azure_blob_service, 'read_capture', read)
    assert client.get('/api/v1/captures/' + res['id'] + '/image', headers=headers[1]).status_code == 404
    read.assert_not_called()
    image_response = client.get('/api/v1/captures/' + res['id'] + '/image', headers=headers[0])
    assert image_response.status_code == 200
    assert image_response.content == data
    assert image_response.headers['cache-control'] == 'no-store'
    assert client.delete('/api/v1/users/me', headers=headers[0]).status_code == 204
    delete.assert_called_once_with(key)
    assert db.query(Capture).count() == 0


def test_storage_failure_rolls_back(context, photograph, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(azure_blob_service, 'is_live', True)
    monkeypatch.setattr(azure_blob_service, 'upload_capture', Mock(side_effect=RuntimeError('offline')))
    cleanup = Mock()
    monkeypatch.setattr(azure_blob_service, 'delete_image', cleanup)
    assert upload(client, headers[0], encoded(photograph)).status_code == 503
    assert db.query(Capture).count() == 0
    cleanup.assert_called_once()


def test_public_container_refused():
    service = object.__new__(AzureBlobService)
    service.is_live = True
    service.container_client = Mock()
    service.container_client.get_container_properties.return_value = {'public_access':'blob'}
    with pytest.raises(RuntimeError, match='private'):
        service.upload_capture('skin_photos/user/file.png', b'bytes')
    service.container_client.get_blob_client.assert_not_called()


def test_commit_failure_cleans_upload(context, photograph, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(azure_blob_service, 'is_live', True)
    monkeypatch.setattr(azure_blob_service, 'upload_capture', Mock())
    delete = Mock()
    monkeypatch.setattr(azure_blob_service, 'delete_image', delete)
    monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('database offline')))
    assert upload(client, headers[0], encoded(photograph)).status_code == 503
    assert db.query(Capture).count() == 0
    delete.assert_called_once()


def test_deletion_failure_retains_metadata_for_retry(context, photograph, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(azure_blob_service, 'is_live', True)
    monkeypatch.setattr(azure_blob_service, 'upload_capture', Mock())
    assert upload(client, headers[0], encoded(photograph)).status_code == 201
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock(side_effect=RuntimeError('retention')))
    assert client.delete('/api/v1/users/me', headers=headers[0]).status_code == 503
    assert db.query(Capture).count() == 1
    assert db.query(User).filter_by(id='capture-user-0').count() == 1


@pytest.mark.parametrize('kind', ['mismatch', 'alpha', 'animated', 'pixels'])
def test_unsupported_image_variants(context, photograph, kind):
    client, db, headers = context
    mime = 'image/png'
    status = 415
    if kind == 'mismatch':
        data = encoded(photograph)
        mime = 'image/jpeg'
    elif kind == 'alpha':
        data = encoded(photograph.convert('RGBA'))
    elif kind == 'animated':
        stream = BytesIO()
        photograph.save(stream, format='PNG', save_all=True, append_images=[Image.new('RGB', photograph.size)])
        data = stream.getvalue()
    else:
        data = encoded(Image.new('RGB', (4001, 4000)))
        status = 413
    assert upload(client, headers[0], data, mime).status_code == status
    assert db.query(Capture).count() == 0


def test_multiple_faces_fail_closed(photograph, monkeypatch):
    monkeypatch.setattr(gate, 'detect_geometry', lambda _: ([(10, 10, 200, 200), (300, 200, 200, 200)], []))
    result = gate.assess(photograph, 1)
    assert result['decision'] == 'rejected'
    assert result['checks']['face']['status'] == 'fail'


def test_invalid_orientation_metadata_has_no_partial_row(context, photograph):
    client, db, headers = context
    exif = Image.Exif()
    exif[274] = 9
    stream = BytesIO()
    photograph.save(stream, format='JPEG', exif=exif)
    assert upload(client, headers[0], stream.getvalue(), 'image/jpeg').status_code == 422
    assert db.query(Capture).count() == 0


def test_sqlite_migration_constraints():
    import sqlite3
    db = sqlite3.connect(':memory:')
    db.execute('PRAGMA foreign_keys=ON')
    db.execute('CREATE TABLE users (id VARCHAR(36) PRIMARY KEY)')
    sql = (Path(__file__).parents[2] / 'docs/migrations/guided-capture-v1-sqlite.sql').read_text()
    db.executescript(sql)
    assert set(row[1] for row in db.execute('PRAGMA table_info(captures)')) == set(Capture.__table__.columns.keys())
    statement = "INSERT INTO captures VALUES ('id', ?, ?, 'upload', 'front', '2026-10-02', '{}', ?, ?, '1.0')"
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(statement, ('foreign', 'accepted', 'not_persisted', None))
    db.execute("INSERT INTO users VALUES ('owner')")
    for state, storage, key in [('pending', 'not_persisted', None), ('accepted', 'azure_blob', None), ('rejected', 'azure_blob', 'key')]:
        with pytest.raises(sqlite3.IntegrityError):
            db.execute(statement, ('owner', state, storage, key))
    db.execute(statement, ('owner', 'accepted', 'not_persisted', None))
    db.close()
