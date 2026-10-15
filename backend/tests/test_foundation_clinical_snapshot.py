from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import jwt
import pytest
from fastapi.testclient import TestClient
from fastapi import HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import text
from app.main import app
from app.models import User, CheckIn, DoctorPatientAccess, DoctorReviewAction, AuditLog
from app.core.config import settings
from app.core.security import create_access_token
from app.services.safety import evaluate_safety
from app.services.clinical_snapshot import build_snapshot
from app.api.v1 import clinical_snapshot as api
from app.services import clinical_snapshot as service
from tests.test_postgres_gate import pg_engine, seed
from tests.test_account_deletion import deletion_context

PATH='/api/v1/clinical-snapshot'


def auth(owner='owner',password='test-only'):
    return {'Authorization':'Bearer '+create_access_token(owner,'patient' if owner=='owner' else 'doctor',hashed_password=password)}


def clinical_seed(engine):
    factory=seed(engine)
    with factory() as db:
        user=db.get(User,'owner')
        safety=evaluate_safety(db,user).model_dump(mode='json')
        at=datetime.now(timezone.utc)-timedelta(days=1)
        db.add(DoctorPatientAccess(id='grant',patient_id='owner',doctor_id='doctor0',access_token='synthetic-unused',
            status='active',created_at=at,expires_at=at+timedelta(days=2)))
        db.commit()
        db.add(DoctorReviewAction(id='public-review',patient_id='owner',doctor_id='doctor0',access_id='grant',sequence=1,
            state='reviewed',recommendation='track',patient_visible=True,rationale='Synthetic public history',
            safety_snapshot=safety,created_at=at))
        db.commit()
    return factory


def private_review(db):
    safety=evaluate_safety(db,db.get(User,'owner')).model_dump(mode='json')
    db.add(DoctorReviewAction(id='private-review',patient_id='owner',doctor_id='doctor0',access_id='grant',sequence=2,
        state='follow_up_needed',recommendation='track',patient_visible=False,rationale='synthetic-private-current',
        safety_snapshot=safety,created_at=datetime.now(timezone.utc)-timedelta(seconds=1)))


def test_sqlite_refuses_atomic_claim(deletion_context):
    client,_,auth_headers=deletion_context
    result=client.get(PATH,headers=auth_headers)
    assert result.status_code == 503
    assert 'PostgreSQL' in result.text


def test_pg_bundle_shared_safety_clock_scope_and_private_current(pg_engine,monkeypatch):
    factory=clinical_seed(pg_engine)
    with factory() as db:
        private_review(db);db.commit()
    monkeypatch.setattr(api,'engine',pg_engine)
    with TestClient(app) as client:
        response=client.get(PATH,headers=auth())
        assert response.status_code == 200,response.text
        data=response.json()
        assert response.headers['cache-control'] == 'no-store'
        assert data['safety'] == data['review']['safety'] == data['home']['safety'] == data['personal_skin_model']['safety']
        assert data['personal_skin_model']['sources']['safety']['provenance'] == data['safety']['provenance']
        assert data['evaluated_at'] == data['review']['as_of'] == data['personal_skin_model']['generated_at'] == data['home']['as_of']
        assert data['consistency'] == data['safety']['provenance']['consistency'] == 'postgresql_repeatable_read_transaction'
        assert data['review']['current_decision_visibility'] == 'not_available_to_patient'
        assert data['review']['latest_sequence'] == 2 and data['review']['current_decision'] is None
        assert data['personal_skin_model']['sources']['doctor']['current_decision'] is None
        assert 'synthetic-private-current' not in response.text
        assert data['review']['history'][0]['is_current'] is False
        assert data['clinical_clearance'] is False and data['replayable'] is False
        assert client.get(PATH,headers=auth('doctor0')).status_code == 403
        assert client.get(PATH,headers=auth(password='wrong')).status_code == 401
        assert client.get(PATH,headers=auth('absent')).status_code == 401
        assert client.get(PATH).status_code == 401
        with factory() as db:
            db.get(DoctorPatientAccess,'grant').status='revoked';db.commit()
        after=client.get(PATH,headers=auth())
        assert after.status_code == 200
        assert after.json()['review']['access'][0]['status'] == 'revoked'
        assert client.get(PATH,headers=auth('doctor0')).status_code == 403


def test_pg_concurrent_review_and_urgent_source_do_not_mix_snapshots(pg_engine,monkeypatch):
    factory=clinical_seed(pg_engine)
    original=service.personal_skin_model
    def interleaved(db,user,now):
        model=original(db,user,now)
        def commit_new():
            with factory() as writer:
                private_review(writer)
                writer.add(CheckIn(user_id='owner',created_at=now-timedelta(seconds=1),date_str=now.date().isoformat(),
                    ai_vision_analysis={'measurement_source':'none'},observation={'schema_version':1,
                    'provenance':{'report':'user_reported','created_at':'server_recorded'},
                    'user_reported':{'overall_change':'worse','symptoms':['burning'],
                        'safety':{'breathing_difficulty':True}}}))
                writer.commit()
        with ThreadPoolExecutor(1) as pool: pool.submit(commit_new).result(timeout=8)
        return model
    monkeypatch.setattr(service,'personal_skin_model',interleaved)
    with pg_engine.connect().execution_options(isolation_level='REPEATABLE READ') as c:
        with Session(c) as db:
            first=build_snapshot(db,db.get(User,'owner'))
            assert first.review.latest_sequence == 1
            assert first.safety.status != 'urgent'
            assert first.home['safety']['status'] != 'urgent'
    monkeypatch.setattr(service,'personal_skin_model',original)
    with pg_engine.connect().execution_options(isolation_level='REPEATABLE READ') as c:
        with Session(c) as db:
            second=build_snapshot(db,db.get(User,'owner'))
            assert second.review.latest_sequence == 2 and second.review.current_decision is None
            assert second.safety.status == second.home['safety']['status'] == second.personal_skin_model.safety.status == 'urgent'
            assert second.safety.provenance.source_revision != first.safety.provenance.source_revision
            assert second.snapshot_id != first.snapshot_id


def test_pg_current_session_revocation_after_snapshot_is_rechecked(pg_engine,monkeypatch):
    factory=clinical_seed(pg_engine);headers=auth()
    payload=jwt.decode(headers['Authorization'][7:],settings.SECRET_KEY,algorithms=[settings.ALGORITHM])
    original=api.build_snapshot
    def revoke_after_build(db,user):
        result=original(db,user)
        with factory() as other:
            other.add(AuditLog(actor_id='owner',action='SESSION_REVOKED',target_resource=payload['jti'],details={}))
            other.commit()
        return result
    monkeypatch.setattr(api,'engine',pg_engine)
    monkeypatch.setattr(api,'build_snapshot',revoke_after_build)
    with TestClient(app) as client:
        response=client.get(PATH,headers=headers)
        assert response.status_code == 401
        assert 'safety' not in response.json()


def test_pg_snapshot_requires_actual_repeatable_read(pg_engine):
    factory=clinical_seed(pg_engine)
    with factory() as db:
        with pytest.raises(HTTPException) as failure:
            build_snapshot(db,db.get(User,'owner'))
        assert failure.value.status_code == 503


def test_pg_snapshot_serialization_failure_returns_no_payload(pg_engine,monkeypatch):
    from sqlalchemy.exc import OperationalError
    clinical_seed(pg_engine)
    monkeypatch.setattr(api,'engine',pg_engine)
    def unavailable(*args):
        raise OperationalError('synthetic',{},Exception('serialization failure'))
    monkeypatch.setattr(api,'build_snapshot',unavailable)
    with TestClient(app) as client:
        response=client.get(PATH,headers=auth())
        assert response.status_code == 503 and 'personal_skin_model' not in response.json()


def test_shared_clock_controls_home_experiment_and_psm_baseline_day(deletion_context, monkeypatch):
    from app.models import Experiment
    from app.api.v1.home import home_projection
    from app.services.baseline import baseline_snapshot
    from app.services import experiments
    from app.services.personal_skin_model import personal_skin_model
    _,db,_=deletion_context
    clock=datetime(2030,1,2,0,1,tzinfo=timezone.utc)
    row=db.get(Experiment,'owned-experiment')
    row.activated_at=datetime(2030,1,1)
    row.start_date=datetime(2030,1,1)
    row.target_days=14;row.status='active'
    db.add(CheckIn(user_id='delete-patient',created_at=clock-timedelta(seconds=30),date_str='2030-01-02',
        ai_vision_analysis={'measurement_source':'manual'},hydration_score=50,redness_score=50,texture_score=50))
    db.commit()
    monkeypatch.setattr(experiments,'today',Mock(side_effect=AssertionError('Implicit clock used')))
    home=home_projection(db,db.get(User,'delete-patient'),now=clock)
    assert home['experiment']['current_day'] == 2
    assert home['today_checked_in'] is True
    model=personal_skin_model(db,db.get(User,'delete-patient'),now=clock)
    assert model.sources.baseline['snapshot']['today_checked_in'] is True
    assert baseline_snapshot(db,'delete-patient',before=clock,now=clock)['today_checked_in'] is True
