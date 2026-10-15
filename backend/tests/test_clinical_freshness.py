from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import pytest
from tests.test_doctor_loop import loop, grant, review, urgent, auth, ROOT
from tests.test_account_deletion import deletion_context
from app.models import User, CheckIn
from app.services.safety import evaluate_safety
from app.services.personal_skin_model import personal_skin_model


def test_safety_identity_revision_and_missing_evidence(deletion_context):
    client,db,headers=deletion_context
    user=db.get(User,"delete-patient")
    now=datetime.now(timezone.utc)
    a=evaluate_safety(db,user,now);b=evaluate_safety(db,user,now)
    assert a.provenance.evaluation_id!=b.provenance.evaluation_id
    assert a.provenance.source_revision==b.provenance.source_revision
    assert a.provenance.clinical_clearance is False
    assert a.provenance.evidence_completeness=="partial"
    user.profile_context={"sensitivities_allergies":["fragrance"]};db.commit()
    c=evaluate_safety(db,user,now)
    assert c.provenance.source_revision!=a.provenance.source_revision
    other=db.get(User,"delete-doctor")
    assert evaluate_safety(db,other,now).provenance.source_revision!=c.provenance.source_revision
    assert client.get("/api/v1/home",headers=headers).json()["safety"]["provenance"]["clinical_clearance"] is False


def test_current_historical_private_latest_and_urgent_across_projections(loop):
    client,db,patient,foreign,doctors=loop
    grant(loop)
    urgent(db,patient)
    first=review(loop,recommendation="track",rationale="Synthetic clinician rationale",patient_visible=True).json()
    assert first["is_current"] and first["safety_at_review_kind"]=="historical_saved"
    assert first["safety_at_review"]["status"]=="urgent"
    second=review(loop,state="in_review",expected_sequence=1,patient_visible=False).json()
    assert second["sequence"]==2
    state=client.get(ROOT+"/review-status",headers=auth(patient)).json()
    assert state["current_decision"] is None
    assert state["current_decision_visibility"]=="not_available_to_patient"
    assert len(state["history"])==1 and state["history"][0]["is_current"] is False
    assert state["history"][0]["safety_at_review"]==first["safety_at_review"]
    assert state["safety"]["provenance"]["evaluation_id"]!=first["safety_at_review"]["provenance"]["evaluation_id"]
    assert state["safety"]["status"]=="urgent"
    home=client.get("/api/v1/home",headers=auth(patient)).json()
    psm=client.get("/api/v1/personal-skin-model",headers=auth(patient)).json()
    assert home["safety"]["status"]==psm["safety"]["status"]=="urgent"
    assert psm["sources"]["doctor"]["current_decision"] is None
    assert psm["sources"]["doctor"]["history"][0]["is_current"] is False
    assert state["consistency"]==home["consistency"]=="multiple_reads_not_atomic_snapshot"
    other=client.get(ROOT+"/review-status",headers=auth(foreign)).json()
    assert other["history"]==[] and other["current_decision"] is None
    access=client.get(ROOT+"/access",headers=auth(patient)).json()[0]
    assert client.delete(ROOT+"/access/"+access["id"],headers=auth(patient)).status_code==200
    assert client.get(ROOT+"/patients/"+patient.id+"/reviews",headers=auth(doctors[0])).status_code==403


def test_stale_report_is_not_clearance(loop):
    _,db,patient,_,_=loop
    row=urgent(db,patient)
    row.created_at=datetime.now(timezone.utc)-timedelta(days=5);db.commit()
    result=evaluate_safety(db,patient)
    assert result.status=="doctor_review"
    assert result.provenance.report_freshness=="stale"
    assert result.provenance.clinical_clearance is False
    assert result.provenance.latest_report_at.tzinfo is not None


@pytest.mark.parametrize("module,path",[("app.api.v1.home","/api/v1/home"),("app.api.v1.safety","/api/v1/safety"),("app.services.doctor_loop","/api/v1/doctor/review-status"),("app.services.personal_skin_model_v2","/api/v1/personal-skin-model")])
def test_failed_safety_never_returns_clearance(loop,monkeypatch,module,path):
    client,db,patient,_,_=loop
    import importlib
    from sqlalchemy.exc import OperationalError
    monkeypatch.setattr(importlib.import_module(module),"evaluate_safety",Mock(side_effect=OperationalError("",{},Exception("synthetic unavailable"))))
    response=client.get(path,headers=auth(patient))
    assert response.status_code==503
    assert "safety" not in response.json()
