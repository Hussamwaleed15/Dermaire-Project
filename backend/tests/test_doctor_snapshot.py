from concurrent.futures import ThreadPoolExecutor
from datetime import datetime,timedelta,timezone
import jwt
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from sqlalchemy.orm import Session
from app.main import app
from app.models import User,CheckIn,DoctorPatientAccess,AuditLog
from app.core.config import settings
from app.api.v1 import clinical_snapshot as patient_api
from app.api.v1 import doctor_snapshot as api
from app.services import clinical_snapshot as patient_service
from app.services.doctor_snapshot import build_doctor_snapshot
from tests.test_postgres_gate import pg_engine
from tests.test_foundation_clinical_snapshot import clinical_seed,private_review,auth,PATH
from tests.test_account_deletion import deletion_context


def test_doctor_sqlite_refuses_atomic_claim(deletion_context):
    client,_,headers=deletion_context
    assert client.get(PATH+"/patients/delete-patient",headers=headers).status_code==503


def test_pg_doctor_snapshot_private_current_role_and_grant_scope(pg_engine,monkeypatch):
    factory=clinical_seed(pg_engine)
    with factory() as db:private_review(db);db.commit()
    monkeypatch.setattr(patient_api,"engine",pg_engine)
    with TestClient(app) as client:
        response=client.get(PATH+"/patients/owner",headers=auth("doctor0"))
        assert response.status_code==200,response.text
        data=response.json()
        assert response.headers["cache-control"]=="no-store" and data["reader_id"]=="doctor0"
        assert data["review"]["current_decision"]["id"]=="private-review"
        assert "synthetic-private-current" in response.text
        assert data["personal_skin_model"]["sources"]["doctor"]["current_decision"] is None
        assert data["projection_visibility"]=="doctor_review_with_patient_home_and_psm"
        assert data["safety"]==data["review"]["safety"]==data["home"]["safety"]==data["personal_skin_model"]["safety"]
        assert data["evaluated_at"]==data["review"]["as_of"]==data["home"]["as_of"]
        assert not data["clinical_clearance"] and not data["replayable"]
        for user in ("owner","doctor1"):
            assert client.get(PATH+"/patients/owner",headers=auth(user)).status_code==403
        assert client.get(PATH+"/patients/absent",headers=auth("doctor0")).status_code==403
        assert client.get(PATH+"/patients/owner",headers=auth("doctor0",password="wrong")).status_code==401
        assert client.get(PATH+"/patients/owner").status_code==401
    with factory() as db:db.get(DoctorPatientAccess,"grant").status="revoked";db.commit()
    with TestClient(app) as client:
        revoked=client.get(PATH+"/patients/owner",headers=auth("doctor0"))
        assert revoked.status_code==403 and "synthetic-private-current" not in revoked.text


def test_pg_doctor_logout_after_build_is_rechecked(pg_engine,monkeypatch):
    factory=clinical_seed(pg_engine);headers=auth("doctor0")
    claims=jwt.decode(headers["Authorization"][7:],settings.SECRET_KEY,algorithms=[settings.ALGORITHM])
    original=api.build_doctor_snapshot
    def revoke(db,patient,doctor,grant):
        result=original(db,patient,doctor,grant)
        with factory() as other:
            other.add(AuditLog(actor_id=doctor.id,action="SESSION_REVOKED",target_resource=claims["jti"],details={}));other.commit()
        return result
    monkeypatch.setattr(patient_api,"engine",pg_engine);monkeypatch.setattr(api,"build_doctor_snapshot",revoke)
    with TestClient(app) as client:
        response=client.get(PATH+"/patients/owner",headers=headers)
        assert response.status_code==401 and "safety" not in response.json()


def test_pg_doctor_snapshot_keeps_one_source_version(pg_engine,monkeypatch):
    factory=clinical_seed(pg_engine)
    original=patient_service.personal_skin_model
    def interleave(db,user,at):
        model=original(db,user,at)
        def write():
            with factory() as other:
                private_review(other)
                other.add(CheckIn(user_id="owner",date_str=at.date().isoformat(),created_at=at-timedelta(seconds=1),observation={"schema_version":1,"user_reported":{"overall_change":"worse","safety":{"breathing_difficulty":True}},"provenance":{"report":"user_reported","created_at":"server_recorded"}}));other.commit()
        with ThreadPoolExecutor(1) as pool:pool.submit(write).result(timeout=8)
        return model
    monkeypatch.setattr(patient_service,"personal_skin_model",interleave)
    with pg_engine.connect().execution_options(isolation_level="REPEATABLE READ") as connection:
        with Session(connection) as db:
            first=build_doctor_snapshot(db,db.get(User,"owner"),db.get(User,"doctor0"),db.get(DoctorPatientAccess,"grant"))
            assert first.review.latest_sequence==1 and first.safety.status!="urgent"
    monkeypatch.setattr(patient_service,"personal_skin_model",original)
    with pg_engine.connect().execution_options(isolation_level="REPEATABLE READ") as connection:
        with Session(connection) as db:
            second=build_doctor_snapshot(db,db.get(User,"owner"),db.get(User,"doctor0"),db.get(DoctorPatientAccess,"grant"))
            assert second.review.latest_sequence==2 and second.review.current_decision.id=="private-review"
            assert second.safety.status==second.review.safety.status=="urgent"
