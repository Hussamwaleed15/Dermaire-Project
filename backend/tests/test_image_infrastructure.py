from datetime import datetime, timedelta, timezone
from io import BytesIO
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4
import pytest
from PIL import Image
from azure.core.exceptions import ResourceNotFoundError
from azure.storage.blob import RetentionPolicy
from app.models import Capture, CheckIn, User, DoctorPatientAccess, Measurement, AuditLog
from app.core.security import create_access_token
from app.core.config import settings
from app.services.azure_blob import AzureBlobService, azure_blob_service
from app.services.image_reconciliation import reconcile
from test_capture_quality import context, photograph, encoded, upload


@pytest.fixture
def storage(monkeypatch):
    blobs = {}
    def write(key, data):
        blobs[key] = data
    def read(key):
        if key not in blobs:
            raise ResourceNotFoundError('missing')
        return blobs[key]
    store = Mock(side_effect=write)
    monkeypatch.setattr(azure_blob_service, 'is_live', True)
    monkeypatch.setattr(azure_blob_service, 'upload_capture', store)
    monkeypatch.setattr(azure_blob_service, 'read_capture', Mock(side_effect=read))
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock(side_effect=lambda key: blobs.pop(key, None)))
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    return blobs, store


def checkin(client, headers, data, fields=None):
    return client.post('/api/v1/checkins', headers=headers, files={'photo': ('private.png', data, 'image/png')}, data=fields or {})


@pytest.mark.parametrize('kind', ['captures', 'checkins'])
@pytest.mark.parametrize('cleanup_pending', [False, True])
def test_retry_after_journaled_cleanup_survives_replay(
        context, photograph, storage, monkeypatch, kind, cleanup_pending):
    from app.services import image_reconciliation
    from app.services.deletion_journal import DeletionJournal
    from test_deletion_journal import Container
    client, db, headers = context
    journal = DeletionJournal(Container(), 'synthetic-test-key-' * 3, True)
    monkeypatch.setattr(image_reconciliation, 'deletion_journal', journal)
    blobs, store = storage
    remove = azure_blob_service.delete_image
    if cleanup_pending:
        monkeypatch.setattr(azure_blob_service, 'delete_image',
                            Mock(side_effect=RuntimeError('synthetic storage denial')))
    original_commit = db.commit
    monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('synthetic DB failure')))
    auth = {**headers[0], 'Idempotency-Key': 'retry-after-cleanup'}
    data = encoded(photograph)
    submit = lambda: upload(client, auth, data) if kind == 'captures' else checkin(client, auth, data)
    assert submit().status_code == 503
    retired_key = store.call_args.args[0]
    assert len(journal.inventory()) == 1
    monkeypatch.setattr(db, 'commit', original_commit)
    monkeypatch.setattr(azure_blob_service, 'delete_image', remove)
    result = submit()
    assert result.status_code == 201
    active_key = result.json()['image_reference']
    assert active_key != retired_key
    assert submit().json()['id'] == result.json()['id']
    assert store.call_count == 2  # Successful request retries use the committed row.
    replay_storage = Mock(is_live=True)
    replay_storage.container_client.list_blobs.side_effect = lambda **_: [
        SimpleNamespace(name=name) for name in blobs]
    replay_storage.delete_image.side_effect = lambda name: blobs.pop(name)
    delete_account = Mock()
    snapshot = dict(journal.container.data)
    replay_db = Mock()
    replay_db.query.return_value = [SimpleNamespace(id='capture-user-0')]
    journal.replay(replay_db, replay_storage, delete_account)
    delete_account.assert_not_called()
    assert active_key in blobs and retired_key not in blobs
    assert client.get(f"/api/v1/{kind}/{result.json()['id']}/image", headers=auth).status_code == 200
    assert db.query(Capture if kind == 'captures' else CheckIn).count() == 1
    assert journal.container.data == snapshot


def test_capture_persist_read_retry_measurement(context, photograph, storage):
    client, db, headers = context
    blobs, store = storage
    first = upload(client, headers[0], encoded(photograph))
    assert first.status_code == 201, first.text
    row = first.json()
    assert row['storage'] == 'azure_blob' and row['image_reference'] in blobs
    assert row['measurement']['status'] == 'measured'
    azure_blob_service.read_capture.assert_not_called()
    assert upload(client, headers[0], encoded(photograph)).json() == row
    assert db.query(Capture).count() == db.query(Measurement).count() == 1
    assert store.call_count == 1
    path = f"/api/v1/captures/{row['id']}/image"
    assert client.get(path, headers=headers[0]).content == blobs[row['image_reference']]
    assert client.get(path, headers=headers[1]).status_code == 404
    assert client.get(path).status_code == 401
    assert 'https://' not in first.text and 'sig=' not in first.text


def test_capture_key_conflict_and_new_operation(context, photograph, storage):
    client, db, headers = context
    auth = {**headers[0], 'Idempotency-Key': 'operation-one'}
    first = upload(client, auth, encoded(photograph)).json()
    assert upload(client, auth, encoded(photograph)).json()['id'] == first['id']
    assert upload(client, auth, encoded(photograph), fields={'source': 'camera'}).status_code == 409
    second = upload(client, {**headers[0], 'Idempotency-Key': 'operation-two'}, encoded(photograph)).json()
    assert second['id'] != first['id']
    assert len(storage[0]) == 2


def test_offline_capture_can_persist_on_resubmission(context, photograph, monkeypatch):
    client, db, headers = context
    data = encoded(photograph)
    before = upload(client, headers[0], data).json()
    assert before['storage'] == 'not_persisted'
    monkeypatch.setattr(azure_blob_service, 'is_live', True)
    monkeypatch.setattr(azure_blob_service, 'upload_capture', Mock())
    after = upload(client, headers[0], data).json()
    assert after['id'] == before['id'] and after['storage'] == 'azure_blob'
    assert after['measurement'] == before['measurement']


@pytest.mark.parametrize('kind', ['captures', 'checkins'])
def test_rejected_never_uploads(context, storage, kind):
    client, db, headers = context
    data = encoded(Image.new('RGB', (100, 100)))
    response = upload(client, headers[0], data) if kind == 'captures' else checkin(client, headers[0], data)
    assert response.status_code == (201 if kind == 'captures' else 422)
    if kind == 'captures':
        assert response.json()['storage'] == 'not_persisted'
    else:
        assert db.query(CheckIn).count() == 0
    storage[1].assert_not_called()


@pytest.mark.parametrize('kind', ['captures', 'checkins'])
@pytest.mark.parametrize('failure', ['upload', 'commit', 'flush'])
def test_failure_rollback_and_cleanup(context, photograph, storage, monkeypatch, kind, failure):
    client, db, headers = context
    if failure == 'upload':
        # Azure may have accepted bytes before a transport timeout.
        def failed_write(key, data):
            storage[0][key] = data
            raise RuntimeError('timeout')
        storage[1].side_effect = failed_write
    elif failure == "flush":
        original = db.flush
        def failed_flush(*args, **kwargs):
            if db.new:
                raise RuntimeError("database offline")
            return original(*args, **kwargs)
        monkeypatch.setattr(db, "flush", failed_flush)
    else:
        monkeypatch.setattr(db, failure, Mock(side_effect=RuntimeError('database offline')))
    response = upload(client, headers[0], encoded(photograph)) if kind == 'captures' else checkin(client, headers[0], encoded(photograph))
    assert response.status_code == 503
    assert not storage[0]
    assert db.query(Capture).count() == db.query(CheckIn).count() == db.query(Measurement).count() == 0
    if failure == 'flush':
        storage[1].assert_not_called()


def test_checkin_private_persistence_and_retry(context, photograph, storage):
    client, db, headers = context
    data = encoded(photograph)
    first = checkin(client, headers[0], data)
    assert first.status_code == 201, first.text
    row = first.json()
    assert row['storage'] == 'azure_blob' and row['image_sas_url'] is None
    assert row['image_reference'] in storage[0]
    assert checkin(client, headers[0], data).json() == row
    assert storage[1].call_count == db.query(CheckIn).count() == 1
    assert db.query(AuditLog).filter_by(action='CHECKIN_COMPLETED').count() == 1
    assert client.get('/api/v1/checkins', headers=headers[0]).json() == [row]
    assert client.get(row['image_endpoint'], headers=headers[0]).content == storage[0][row['image_reference']]
    assert client.get(row['image_endpoint'], headers=headers[1]).status_code == 404
    assert 'https://' not in first.text and 'sig=' not in first.text


@pytest.mark.parametrize('kind', ['captures', 'checkins'])
@pytest.mark.parametrize('grant_state', ['active', 'revoked', 'expired', 'pending'])
def test_doctor_image_current_grant(context, photograph, storage, kind, grant_state):
    client, db, headers = context
    owner = db.get(User, 'capture-user-0')
    doctor = User(id='image-doctor', email='image-doctor@example.com', full_name='Doctor', role='doctor', hashed_password='unused')
    db.add(doctor); db.commit()
    auth = {'Authorization': 'Bearer ' + create_access_token(doctor.id, 'doctor', hashed_password=doctor.hashed_password)}
    create = upload(client, headers[0], encoded(photograph)) if kind == 'captures' else checkin(client, headers[0], encoded(photograph))
    row = create.json()
    path = f"/api/v1/{kind}/{row['id']}/image"
    assert client.get(path, headers=auth).status_code == 403
    grant = DoctorPatientAccess(doctor_id=doctor.id, patient_id=owner.id, access_token=str(uuid4()),
        status='active' if grant_state == 'expired' else grant_state,
        expires_at=datetime.now(timezone.utc)+timedelta(hours=-1 if grant_state == 'expired' else 1))
    db.add(grant); db.commit()
    result = client.get(path, headers=auth)
    assert result.status_code == (200 if grant_state == 'active' else 403)
    if grant_state == 'active':
        assert client.delete(f'/api/v1/doctor/access/{grant.id}', headers=headers[0]).status_code == 200
        assert client.get(path, headers=auth).status_code == 403


@pytest.mark.parametrize('kind', ['captures', 'checkins'])
def test_account_deletes_absent_or_present_images(context, photograph, storage, kind):
    client, db, headers = context
    response = upload(client, headers[0], encoded(photograph)) if kind == 'captures' else checkin(client, headers[0], encoded(photograph))
    key = response.json()['image_reference']
    assert key in storage[0]
    storage[0].pop(key)  # Already absent is a safe delete retry.
    assert client.delete('/api/v1/users/me', headers=headers[0]).status_code == 204
    azure_blob_service.delete_image.assert_called_once_with(key)
    azure_blob_service.delete_owned_images.assert_called_once_with('capture-user-0')


def service():
    obj = object.__new__(AzureBlobService)
    obj.is_live = True
    obj.client = Mock()
    obj.client.get_service_properties.return_value = {'delete_retention_policy': {'enabled': False}}
    obj.container_client = Mock()
    obj.container_client.get_container_properties.return_value = {'public_access': None}
    obj.container_client.list_blobs.return_value = []
    return obj


def test_sdk_upload_read_and_missing_delete():
    obj = service()
    obj.upload_capture('skin_photos/owner/owner_file.png', b'png')
    blob = obj.container_client.get_blob_client.return_value
    assert blob.upload_blob.call_args.kwargs['overwrite'] is False
    assert blob.upload_blob.call_args.kwargs['content_settings'].content_type == 'image/png'
    blob.download_blob.return_value.readall.return_value = b'png'
    assert obj.read_capture('skin_photos/owner/owner_file.png') == b'png'
    obj.container_client.delete_blob.side_effect = ResourceNotFoundError('absent')
    obj.delete_image('skin_photos/owner/owner_file.png')


@pytest.mark.parametrize('failure', ['public', 'offline', 'soft_delete'])
def test_sdk_health_and_write_fail_closed(failure):
    obj = service()
    if failure == 'public':
        obj.container_client.get_container_properties.return_value = {'public_access': 'blob'}
    elif failure == 'offline':
        obj.container_client.get_container_properties.side_effect = RuntimeError('secret that must not leak')
    else:
        obj.client.get_service_properties.return_value = {'delete_retention_policy': {'enabled': True}}
    assert obj.health() == {'provider': 'azure_blob', 'state': 'degraded', 'durable_images': False}
    with pytest.raises(RuntimeError):
        obj.upload_capture('key', b'png')
    obj.container_client.get_blob_client.assert_not_called()


def test_health_unconfigured_available_and_no_resource_creation(monkeypatch):
    monkeypatch.setattr(settings, 'AZURE_STORAGE_CONNECTION_STRING', '')
    obj = AzureBlobService()
    assert obj.health()['state'] == 'unconfigured'
    assert not obj.health()['durable_images']
    obj = service()
    assert obj.health()['state'] == 'available'
    assert obj.health()['end_to_end_verified'] is False
    obj.container_client.create_container.assert_not_called()


def test_malformed_configuration_is_degraded(monkeypatch):
    monkeypatch.setattr(settings, 'AZURE_STORAGE_CONNECTION_STRING', 'bad config')
    obj = AzureBlobService()
    assert obj.health()['state'] == 'degraded'


def test_missing_azure_config_does_not_confirm_deletion(tmp_path):
    obj = object.__new__(AzureBlobService)
    obj.is_live = False
    obj.local_upload_dir = str(tmp_path)
    with pytest.raises(RuntimeError):
        obj.delete_image('skin_photos/owner/owner_file.png')


def test_post_delete_retained_copy_blocks_success():
    obj = service()
    retained = SimpleNamespace(name='owned', deleted=True, version_id=None)
    obj.container_client.list_blobs.side_effect = [[], [retained]]
    with pytest.raises(RuntimeError, match='remain'):
        obj.delete_image('owned')


def test_static_uploads_no_longer_anonymous(context):
    client, _, _ = context
    assert client.get('/api/v1/static/uploads/private.png').status_code == 404


def test_missing_blob_image_returns_404(context, photograph, storage):
    client, _, headers = context
    row = upload(client, headers[0], encoded(photograph)).json()
    storage[0].clear()
    assert client.get(f"/api/v1/captures/{row['id']}/image", headers=headers[0]).status_code == 404


def test_orphan_reconciliation_respects_references_age_namespace(context, photograph, storage):
    client, db, headers = context
    key = upload(client, headers[0], encoded(photograph)).json()['image_reference']
    old = datetime.now(timezone.utc)-timedelta(days=2)
    orphan = f'skin_photos/capture-user-0/capture-user-0_{uuid4()}.png'
    recent = f'skin_photos/capture-user-0/capture-user-0_{uuid4()}.png'
    obj = service()
    obj.container_client.list_blobs.return_value = [
        SimpleNamespace(name=key, last_modified=old), SimpleNamespace(name=orphan, last_modified=old),
        SimpleNamespace(name=recent, last_modified=datetime.now(timezone.utc)),
        SimpleNamespace(name='unrelated/blob.png', last_modified=old)]
    obj.delete_image = Mock()
    assert reconcile(db, obj) == {'candidates': 1, 'deleted': 0}
    obj.delete_image.assert_not_called()
    assert reconcile(db, obj, apply=True) == {'candidates': 1, 'deleted': 1}
    obj.delete_image.assert_called_once_with(orphan)
    with pytest.raises(ValueError):
        reconcile(db, obj, minimum_age_hours=1)


def test_cleanup_double_failure_then_reconcile(context, photograph, storage, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('db down')))
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock(side_effect=RuntimeError('storage down')))
    assert upload(client, headers[0], encoded(photograph)).status_code == 503
    assert db.query(Capture).count() == 0 and len(storage[0]) == 1
    key = next(iter(storage[0]))
    obj = service()
    obj.container_client.list_blobs.return_value = [SimpleNamespace(name=key, last_modified=datetime.now(timezone.utc)-timedelta(days=2))]
    obj.delete_image = Mock(side_effect=lambda key: storage[0].pop(key))
    assert reconcile(db, obj, apply=True)['deleted'] == 1
    assert not storage[0]


def test_exif_not_retained(context, photograph, storage):
    client, _, headers = context
    exif = Image.Exif(); exif[270] = 'private-location'; exif[274] = 1
    buffer = BytesIO(); photograph.save(buffer, format='JPEG', exif=exif)
    response = upload(client, headers[0], buffer.getvalue(), 'image/jpeg')
    assert response.status_code == 201 and response.json()['state'] == 'accepted'
    stored = Image.open(BytesIO(storage[0][response.json()['image_reference']]))
    assert not stored.getexif() and 'private-location' not in str(stored.info)



def test_cleanup_does_not_erase_committed_retry(context, photograph, storage):
    from app.services.image_reconciliation import cleanup_failed_upload
    client, db, headers = context
    row = upload(client, headers[0], encoded(photograph)).json()
    cleanup_failed_upload(db, azure_blob_service, 'capture-user-0', row['image_reference'])
    assert row['image_reference'] in storage[0]
    azure_blob_service.delete_image.assert_not_called()


def test_versioned_upload_never_confirms_success():
    obj = service()
    obj.container_client.get_blob_client.return_value.upload_blob.return_value = {'version_id': 'old-copy'}
    with pytest.raises(RuntimeError, match='Versioned'):
        obj.upload_capture('skin_photos/owner/owner_file.png', b'png')


def test_health_endpoint_reflects_service_probe(context, monkeypatch):
    client, _, _ = context
    for state in ('unconfigured', 'available', 'degraded'):
        expected = {'provider': 'none' if state == 'unconfigured' else 'azure_blob', 'state': state, 'durable_images': state == 'available'}
        monkeypatch.setattr(azure_blob_service, 'health', Mock(return_value=expected))
        row = client.get('/health').json()
        assert row['azure_services']['blob_storage'] == expected
        assert row['status'] == ('degraded' if state == 'degraded' else 'healthy')



def test_production_unconfigured_capture_fails_closed(context, photograph, monkeypatch):
    client, db, headers = context
    monkeypatch.setattr(settings, 'ENVIRONMENT', 'production')
    assert upload(client, headers[0], encoded(photograph)).status_code == 503
    assert db.query(Capture).count() == db.query(Measurement).count() == 0
    assert client.get('/health').json()['status'] == 'degraded'


def test_foreign_blob_reference_cannot_leak_or_delete(context, photograph, storage):
    client, db, headers = context
    row = upload(client, headers[0], encoded(photograph)).json()
    capture = db.get(Capture, row['id'])
    capture.image_blob_name = 'skin_photos/capture-user-1/capture-user-1_foreign.png'
    db.commit()
    assert client.get(f"/api/v1/captures/{row['id']}/image", headers=headers[0]).status_code == 404
    azure_blob_service.read_capture.assert_not_called()
    assert client.delete('/api/v1/users/me', headers=headers[0]).status_code == 503
    azure_blob_service.delete_image.assert_not_called()


def test_legacy_url_never_leaks_in_history_or_reads(context):
    client, db, headers = context
    db.add(CheckIn(user_id='capture-user-0', date_str='2026-10-03',
        image_blob_name='https://example.com/private?sig=secret', observation={'schema_version': 1, 'daily_context_date': '2026-10-03', 'provenance': {}}))
    db.commit()
    response = client.get('/api/v1/checkins', headers=headers[0])
    assert response.status_code == 200
    assert 'https://' not in response.text and 'sig=' not in response.text
    row = response.json()[0]
    assert row['image_sas_url'] is None and row['image_reference'] is None and row['image_endpoint'] is None
    assert client.get(f"/api/v1/checkins/{row['id']}/image", headers=headers[0]).status_code == 404


def test_private_sdk_reads_refuse_public_container():
    obj = service()
    obj.container_client.get_container_properties.return_value = {'public_access': 'container'}
    with pytest.raises(RuntimeError, match='private'):
        obj.read_capture('key')
    obj.container_client.get_blob_client.assert_not_called()



def test_checkin_idempotency_key_conflict(context, photograph, storage):
    client, db, headers = context
    auth = {**headers[0], 'Idempotency-Key': 'checkin-one'}
    data = encoded(photograph)
    first = checkin(client, auth, data).json()
    assert checkin(client, auth, data).json()['id'] == first['id']
    assert checkin(client, auth, data, {'notes': 'changed'}).status_code == 409
    assert db.query(CheckIn).count() == storage[1].call_count == 1


@pytest.mark.parametrize('policy', [{}, None, {'enabled': False}, RetentionPolicy(enabled=False)])
def test_sdk_disabled_or_absent_retention_allows_storage(policy):
    obj = service()
    obj.client.get_service_properties.return_value = {
        'delete_retention_policy': policy,
        'container_delete_retention_policy': policy,
        'is_versioning_enabled': False,
    }
    assert obj.health()['state'] == 'available'
    assert obj.health()['durable_images'] is True
    obj.upload_capture('owned', b'png')
    obj.delete_image('owned')
    obj.container_client.delete_blob.assert_called_once_with('owned', delete_snapshots='include')


@pytest.mark.parametrize('field', ['delete_retention_policy', 'container_delete_retention_policy'])
@pytest.mark.parametrize('policy', [{'enabled': True}, RetentionPolicy(enabled=True, days=7)])
def test_sdk_retention_blocks_health_upload_and_delete(field, policy):
    assert_storage_policy_blocks_operations({field: policy})


def test_sdk_versioning_blocks_health_upload_and_delete():
    assert_storage_policy_blocks_operations({'is_versioning_enabled': True})


def assert_storage_policy_blocks_operations(properties):
    obj = service()
    obj.client.get_service_properties.return_value = properties
    assert obj.health() == {'provider': 'azure_blob', 'state': 'degraded', 'durable_images': False}
    with pytest.raises(RuntimeError, match='retention'):
        obj.upload_capture('owned', b'png')
    with pytest.raises(RuntimeError, match='retention'):
        obj.delete_image('owned')
    obj.container_client.get_blob_client.assert_not_called()
    obj.container_client.list_blobs.assert_not_called()
    obj.container_client.delete_blob.assert_not_called()
