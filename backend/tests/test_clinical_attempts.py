from datetime import datetime, timedelta, timezone
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import Mock
import pytest
from fastapi import Response, HTTPException
from app.models import ClinicalAttempt, ClinicalNote, DoctorReviewAction, User, DoctorPatientAccess
from app.api.v1.doctor import add_clinical_note, add_review
from app.schemas import ClinicalNoteCreate
from app.schemas.doctor_loop import ReviewActionCreate
from tests.test_doctor_loop import loop, grant, auth, ROOT
from tests.test_postgres_gate import pg_engine, seed

KEY = 'synthetic-clinical-key-0001'

@pytest.mark.parametrize('operation', ['note', 'review'])
def test_original_receipt_replay_binding_expiry_and_revocation(loop, operation):
    client, db, patient, _, doctors = loop
    g = grant(loop)
    path = ROOT + '/patients/patient/' + ('notes' if operation == 'note' else 'reviews')
    payload = {'content': 'Synthetic clinical note'} if operation == 'note' else {'state': 'reviewed', 'expected_sequence': 0}
    headers = {**auth(doctors[0]), 'Idempotency-Key': KEY}
    first = client.post(path, headers=headers, json=payload)
    assert first.status_code == 201, first.text
    again = client.post(path, headers=headers, json=payload)
    assert again.json() == first.json() and again.headers['operation-replay'] == 'true'
    assert db.query(ClinicalAttempt).count() == 1
    read = ROOT + '/patients/patient/attempts/' + operation + '/' + KEY
    assert client.get(read, headers=headers).json()['result'] == first.json()
    changed = {**payload, **({'content': 'Different synthetic note'} if operation == 'note' else {'expected_sequence': 1})}
    assert client.post(path, headers=headers, json=changed).status_code == 409
    row = db.query(ClinicalAttempt).one()
    row.recorded_at = datetime.now(timezone.utc) - timedelta(days=31); db.commit()
    assert client.get(read, headers=headers).json()['status'] == 'expired'
    assert client.post(path, headers=headers, json=payload).status_code == 410
    g.status = 'revoked'; db.commit()
    assert client.get(read, headers=headers).status_code == 403
    assert client.post(path, headers=headers, json=payload).status_code == 403

@pytest.mark.parametrize('operation', ['note', 'review'])
def test_pg_duplicate_receipt_serializes_and_rollback_atomic(pg_engine, operation, monkeypatch):
    factory = seed(pg_engine)
    with factory() as db:
        db.add(DoctorPatientAccess(id='grant', patient_id='owner', doctor_id='doctor0', access_token='synthetic', status='active', granted_by='owner', expires_at=datetime.now(timezone.utc)+timedelta(hours=1)))
        db.commit()
    def write():
        with factory() as db:
            actor = db.get(User, 'doctor0')
            response = Response()
            if operation == 'note':
                result = add_clinical_note('owner', ClinicalNoteCreate(content='Synthetic note'), actor, db, response, KEY)
            else:
                result = add_review('owner', ReviewActionCreate(state='reviewed', expected_sequence=0), actor, db, response, KEY)
            return response.headers['operation-attempt-id']
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert len(set(pool.map(lambda _: write(), range(2)))) == 1
    model = ClinicalNote if operation == 'note' else DoctorReviewAction
    with factory() as db:
        assert db.query(model).count() == db.query(ClinicalAttempt).count() == 1
        # A failed SQL commit must roll back both record and receipt.
        original = db.commit
        monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('synthetic failure')))
        with pytest.raises(HTTPException) as failed:
            if operation == 'note':
                add_clinical_note('owner', ClinicalNoteCreate(content='Another synthetic note'), db.get(User, 'doctor0'), db, Response(), KEY+'2')
            else:
                add_review('owner', ReviewActionCreate(state='reviewed', expected_sequence=1), db.get(User, 'doctor0'), db, Response(), KEY+'2')
        assert failed.value.status_code == 503
        monkeypatch.setattr(db, 'commit', original)
        assert db.query(model).count() == db.query(ClinicalAttempt).count() == 1

@pytest.mark.parametrize('owner', ['patient', 'doctor'])
def test_receipts_erased_bilaterally(loop, monkeypatch, owner):
    from app.models import GrantAttempt
    from app.services.azure_blob import azure_blob_service
    client, db, patient, _, doctors = loop
    headers = {**auth(patient), 'Idempotency-Key': KEY}
    qr = client.post(ROOT+'/generate-qr', headers=headers, json={'view_consent': True, 'doctor_id': doctors[0].id})
    assert qr.status_code == 200, qr.text
    assert client.post(ROOT+'/claim', headers=auth(doctors[0]), json={'access_token': qr.json()['access_token']}).status_code == 200
    assert client.post(ROOT+'/patients/patient/notes', headers={**auth(doctors[0]), 'Idempotency-Key': KEY}, json={'content': 'Synthetic note'}).status_code == 201
    assert db.query(GrantAttempt).count() == db.query(ClinicalAttempt).count() == 1
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', lambda _: None)
    assert client.delete('/api/v1/users/me', headers=auth(patient if owner == 'patient' else doctors[0])).status_code == 204
    assert db.query(GrantAttempt).count() == db.query(ClinicalAttempt).count() == 0


def test_consent_receipt_issue_revoke_no_resurrection(loop):
    from app.models import GrantAttempt
    client, db, patient, foreign, doctors = loop
    headers = {**auth(patient), 'Idempotency-Key': KEY}
    path = ROOT+'/generate-qr'
    body = {'view_consent': True, 'doctor_id': doctors[0].id, 'export_consent': True}
    first = client.post(path, headers=headers, json=body)
    assert first.status_code == 200, first.text
    assert first.json()['access']['consent_source'] == 'explicit_patient_intent'
    assert first.json()['access']['export_consent'] is True
    assert client.post(path, headers=headers, json=body).json() == first.json()
    assert client.post(path, headers=headers, json={**body, 'export_consent': False}).status_code == 409
    read = ROOT+'/consent-attempts/issue/'+KEY
    assert client.get(read, headers=auth(foreign)).json()['status'] == 'unknown'
    assert client.get(read, headers=headers).json()['result'] == first.json()
    access_id = first.json()['access']['id']
    revoke = ROOT+'/access/'+access_id
    result = client.delete(revoke, headers=headers)
    assert result.status_code == 200
    assert client.delete(revoke, headers=headers).json() == result.json()
    assert client.post(path, headers=headers, json=body).status_code == 410
    assert client.get(read, headers=headers).json()['result'] is None
    assert db.query(GrantAttempt).count() == 2

@pytest.mark.parametrize('operation', ['issue', 'revoke'])
def test_pg_patient_consent_receipts_concurrent_atomic(pg_engine, operation, monkeypatch):
    from app.models import GrantAttempt
    from app.schemas import GenerateQrRequest
    from app.api.v1.doctor import generate_doctor_qr_access, revoke_one
    factory = seed(pg_engine)
    with factory() as db:
        db.add(DoctorPatientAccess(id='grant', patient_id='owner', doctor_id='doctor0', access_token='synthetic', status='active', granted_by='owner', expires_at=datetime.now(timezone.utc)+timedelta(hours=1)))
        db.commit()
    def write(db, key):
        response = Response()
        if operation == 'issue':
            generate_doctor_qr_access(GenerateQrRequest(view_consent=True, doctor_id='doctor0'), 60,
                db.get(User, 'owner'), {'jti': 'synthetic-session'}, db, response, key)
        else:
            revoke_one('grant', db.get(User, 'owner'), db, response, key)
        return response.headers['operation-attempt-id']
    def concurrent(_):
        with factory() as db:
            return write(db, KEY)
    with ThreadPoolExecutor(max_workers=2) as pool:
        assert len(set(pool.map(concurrent, range(2)))) == 1
    with factory() as db:
        assert db.query(GrantAttempt).count() == 1
        before = db.query(DoctorPatientAccess).count()
        monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('synthetic failure')))
        with pytest.raises(HTTPException) as failed:
            write(db, KEY+'2')
        assert failed.value.status_code == 503
        assert db.query(GrantAttempt).count() == 1
        assert db.query(DoctorPatientAccess).count() == before

def test_claim_and_bulk_revoke_receipts_preserve_one_use(loop):
    client, db, patient, _, doctors = loop
    qr = client.post(ROOT+'/generate-qr', headers=auth(patient)).json()
    headers = {**auth(doctors[0]), 'Idempotency-Key': KEY}
    payload = {'access_token': qr['access_token']}
    first = client.post(ROOT+'/claim', headers=headers, json=payload)
    assert first.status_code == 200, first.text
    assert client.post(ROOT+'/claim', headers=headers, json=payload).json() == first.json()
    assert client.post(ROOT+'/claim', headers=auth(doctors[0]), json=payload).status_code == 409
    patient_headers = {**auth(patient), 'Idempotency-Key': KEY}
    path = ROOT+'/revoke/patient'
    result = client.delete(path, headers=patient_headers)
    assert result.status_code == 200
    assert client.delete(path, headers=patient_headers).json() == result.json()
    assert client.get(ROOT+'/consent-attempts/revoke_all/'+KEY, headers=patient_headers).json()['status'] == 'committed'
    assert client.post(ROOT+'/claim', headers=headers, json=payload).status_code != 200


def test_completion_readback_uses_atomic_audits_and_version(loop):
    from app.core.config import settings
    client, db, patient, foreign, _ = loop
    headers = auth(patient)
    safety = '/api/v1/users/completion-receipts/safety/'+settings.SAFETY_POLICY_REQUIRED_VERSION
    profile = '/api/v1/users/completion-receipts/profile-review/1'
    assert client.get(safety, headers=headers).json()['status'] == 'unknown'
    assert client.post('/api/v1/auth/accept-safety', headers=headers, json={'policy_version': settings.SAFETY_POLICY_REQUIRED_VERSION}).status_code == 200
    original = client.get(safety, headers=headers).json()
    assert original['status'] == 'committed'
    assert client.post('/api/v1/auth/accept-safety', headers=headers, json={'policy_version': settings.SAFETY_POLICY_REQUIRED_VERSION}).status_code == 200
    assert client.get(safety, headers=headers).json() == original
    assert client.get(safety, headers=auth(foreign)).json()['status'] == 'unknown'
    assert client.post('/api/v1/users/profile-review', headers=headers, json={'reviewed': True}).status_code == 200
    assert client.get(profile, headers=headers).json()['status'] == 'committed'
    assert client.get('/api/v1/users/completion-receipts/profile-review/2', headers=headers).status_code == 422

def test_duplicate_receipt_headers_rejected(loop):
    client, db, patient, _, doctors = loop
    grant(loop)
    headers = list(auth(doctors[0]).items()) + [('Idempotency-Key', KEY), ('Idempotency-Key', KEY+'2')]
    response = client.post(ROOT+'/patients/patient/notes', headers=headers, json={'content': 'Synthetic note'})
    assert response.status_code == 422
    assert db.query(ClinicalAttempt).count() == db.query(ClinicalNote).count() == 0


def test_repeated_revocation_new_keys_record_receipts_without_duplicate_transition(loop):
    from app.models import GrantAttempt, AuditLog
    client, db, patient, _, _ = loop
    access = grant(loop)
    path = ROOT+'/access/'+access.id
    original = client.delete(path, headers=auth(patient))
    assert original.status_code == 200
    assert client.delete(path, headers=auth(patient)).json() == original.json()
    for key in (KEY, KEY+'2'):
        headers = {**auth(patient), 'Idempotency-Key': key}
        first = client.delete(path, headers=headers)
        assert first.status_code == 200 and first.json() == original.json()
        replay = client.delete(path, headers=headers)
        assert replay.json() == first.json() and replay.headers['operation-replay'] == 'true'
    assert db.query(AuditLog).filter_by(action='PATIENT_ACCESS_REVOKED').count() == 1
    assert db.query(AuditLog).filter_by(action='CONSENT_REVOCATION_RECONCILED').count() == 2
    assert db.query(GrantAttempt).count() == 2
