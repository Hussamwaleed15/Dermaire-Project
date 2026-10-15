from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
import pytest
from fastapi import HTTPException
from app.core.config import settings
from app.models import User, DoctorPatientAccess
from tests.test_account_deletion import deletion_context
from tests.test_h4_capture_observations import records, PATH
from tests.test_postgres_gate import pg_engine, seed, observe_lock_wait


def test_current_policy_required_for_association_when_enforced(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    records(db)
    monkeypatch.setattr(settings, 'SAFETY_POLICY_ENFORCE', True)
    assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 403
    assert client.get(PATH.rsplit('/',1)[0], headers=auth).status_code == 200
    accepted = client.post('/api/v1/auth/accept-safety', headers=auth,
                           json={'accepted': True, 'policy_version': settings.SAFETY_POLICY_REQUIRED_VERSION})
    assert accepted.status_code == 200, accepted.text
    assert client.put(PATH, headers=auth, json={'associated': True}).status_code == 200
    assert client.get('/api/v1/routine/adherence/history', headers=auth).json()['items'] == []


def test_pg_association_read_waits_for_current_revoke(pg_engine):
    from app.api.v1.capture_observations import select, associations
    from app.schemas.capture_observations import CaptureObservationSelect
    from app.services.routine import lock_owner
    factory = seed(pg_engine)
    with factory() as db:
        records(db, 'owner')
        select('capture','observation',CaptureObservationSelect(associated=True),db.get(User,'owner'),db)
        db.add(DoctorPatientAccess(id='grant', patient_id='owner', doctor_id='doctor0', status='active',
            access_token='synthetic-legacy-view-only', expires_at=datetime.now(timezone.utc)+timedelta(hours=1)))
        db.commit()
    def read():
        with factory() as reader:
            try:
                associations('capture', reader.get(User,'doctor0'), reader)
            except HTTPException as exc:
                return exc.status_code
            return 200
    with factory() as writer:
        lock_owner(writer, writer.get(User,'owner'))
        writer.get(DoctorPatientAccess,'grant').status = 'revoked'
        writer.flush()
        with ThreadPoolExecutor(1) as pool:
            future = pool.submit(read)
            try:
                observe_lock_wait(pg_engine)
            finally:
                writer.commit()
            assert future.result(timeout=5) == 403
