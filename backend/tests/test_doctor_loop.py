from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import json
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from app.main import app
from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.models import (User, DoctorPatientAccess, DoctorReviewAction, ClinicalNote, AuditLog,
    CheckIn, DailyContext, Product, RoutineEntry, RoutineAdherence, Experiment, ExperimentEvaluation,
    Capture, Measurement)
from app.tools.provision_user import ProvisionRequest, provision_user
from app.services.safety import FLAGS
from app.services.azure_blob import azure_blob_service

ROOT = "/api/v1/doctor"

def auth(user, role=None):
    return {"Authorization": "Bearer " + create_access_token(user.id, role or user.role, hashed_password=user.hashed_password)}

@pytest.fixture
def loop():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    @event.listens_for(engine, "connect")
    def fk(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    patient = User(id="patient", email="patient@test.com", full_name="Patient", hashed_password="unused")
    foreign = User(id="foreign", email="foreign@test.com", full_name="Foreign", hashed_password="unused")
    db.add_all([patient, foreign]); db.commit()
    doctors = [provision_user(db, ProvisionRequest(email=f"doctor{i}@test.com", full_name=f"Doctor {i}",
        role="doctor", password="Test-password-only-12!", verification_reference="TEST-APPROVAL"), operator="test") for i in range(2)]
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as client:
        yield client, db, patient, foreign, doctors
    app.dependency_overrides.clear(); db.close(); engine.dispose()


def grant(loop, doctor=0, patient=None):
    client, db, owner, _, doctors = loop
    owner = patient or owner
    qr = client.post(ROOT+"/generate-qr", headers=auth(owner))
    assert qr.status_code == 200
    token = qr.json()["access_token"]
    assert client.post(ROOT+"/claim", headers=auth(doctors[doctor]), json={"access_token": token}).status_code == 200
    return db.query(DoctorPatientAccess).filter_by(access_token=token).one()


def review(loop, **values):
    client, _, patient, _, doctors = loop
    return client.post(ROOT+f"/patients/{patient.id}/reviews", headers=auth(doctors[0]),
        json={"state": "reviewed", "expected_sequence": 0, **values})


def urgent(db, patient):
    row = CheckIn(user_id=patient.id, date_str="today", observation={"schema_version": 1,
        "user_reported": {"overall_change": "same", "symptoms": ["redness"], "safety": {
            "severity": "mild", "pain": "none", **dict.fromkeys(FLAGS, False), "breathing_difficulty": True}},
        "provenance": {"report": "user_reported", "created_at": "server_recorded"}})
    db.add(row); db.commit(); return row

@pytest.mark.parametrize("method,path,payload", [
    ("get", "/patients", None), ("get", "/patients/patient", None),
    ("get", "/patients/patient/timeline", None), ("get", "/patients/patient/notes", None),
    ("get", "/patients/patient/reviews", None),
    ("post", "/patients/patient/notes", {"content": "Clinical assessment note"}),
    ("post", "/patients/patient/reviews", {"state": "reviewed", "expected_sequence": 0}),
    ("post", "/claim", {"access_token": "invalid"})])
def test_patient_cannot_use_doctor_endpoints(loop, method, path, payload):
    client, db, patient, _, _ = loop
    kwargs = {"json": payload} if payload else {}
    assert getattr(client, method)(ROOT+path, headers=auth(patient, "doctor"), **kwargs).status_code == 403
    assert getattr(client, method)(ROOT+path, **kwargs).status_code == 401
    assert db.query(ClinicalNote).count() == db.query(DoctorReviewAction).count() == 0

@pytest.mark.parametrize("role", ["admin", "support"])
def test_non_clinician_privileged_roles_denied(loop, role):
    client, db, _, _, _ = loop
    user = provision_user(db, ProvisionRequest(email=f"{role}@test.com", full_name=role, role=role,
        password="Test-password-only-12!", verification_reference="TEST"), operator="test")
    assert client.get(ROOT+"/patients", headers=auth(user)).status_code == 403
    assert client.post(ROOT+"/generate-qr", headers=auth(user)).status_code == 403

@pytest.mark.parametrize("path", ["", "/timeline", "/notes", "/reviews"])
def test_assignment_and_foreign_isolation(loop, path):
    client, _, patient, foreign, doctors = loop
    assert client.get(ROOT+f"/patients/{patient.id}"+path, headers=auth(doctors[0])).status_code == 403
    grant(loop)
    assert client.get(ROOT+f"/patients/{patient.id}"+path, headers=auth(doctors[0])).status_code == 200
    for pid, doctor in ((patient.id, doctors[1]), (foreign.id, doctors[0]), ("missing", doctors[0])):
        assert client.get(ROOT+f"/patients/{pid}"+path, headers=auth(doctor)).status_code == 403


def test_access_lifecycle_unique_tokens_expiry_revocation_regrant(loop):
    client, db, patient, foreign, doctors = loop
    first = grant(loop)
    second = grant(loop, doctor=1)
    assert first.access_token != second.access_token
    data = client.get(ROOT+"/access", headers=auth(patient)).json()
    assert all(r["granted_by"] == patient.id and r["claimed_at"] for r in data)
    assert "access_token" not in json.dumps(data)
    assert client.delete(ROOT+f"/access/{first.id}", headers=auth(foreign)).status_code == 404
    assert client.post(ROOT+"/claim", headers=auth(doctors[1]), json={"access_token":first.access_token}).status_code == 403
    assert client.delete(ROOT+f"/access/{first.id}", headers=auth(patient)).json()["revoked_by"] == patient.id
    assert client.get(ROOT+"/patients/patient/timeline", headers=auth(doctors[0])).status_code == 403
    assert client.get(ROOT+"/patients", headers=auth(doctors[0])).json() == []
    assert review(loop).status_code == 403
    assert client.post(ROOT+"/patients/patient/notes", headers=auth(doctors[0]), json={"content":"Clinical note after revoke"}).status_code == 403
    assert client.post(ROOT+"/claim", headers=auth(doctors[0]), json={"access_token":first.access_token}).status_code == 400
    assert client.get(ROOT+"/patients/patient", headers=auth(doctors[1])).status_code == 200
    second.expires_at = datetime.now(timezone.utc)-timedelta(seconds=1); db.commit()
    assert client.get(ROOT+"/patients/patient", headers=auth(doctors[1])).status_code == 403
    assert client.get(ROOT+"/access", headers=auth(patient)).json()[1]["status"] == "expired"
    grant(loop)
    assert client.delete(ROOT+"/revoke/foreign", headers=auth(patient)).status_code == 403
    assert client.delete(ROOT+"/revoke/patient", headers=auth(patient)).status_code == 200
    assert client.get(ROOT+"/patients", headers=auth(doctors[0])).json() == []


def test_notes_visibility_immutable_identity_and_links(loop):
    client, db, patient, _, doctors = loop; grant(loop)
    action = review(loop).json()
    route = ROOT+"/patients/patient/notes"
    internal = client.post(route, headers=auth(doctors[0]), json={"content":"Internal clinical deliberation"}).json()
    public = client.post(route, headers=auth(doctors[0]), json={"content":"Please arrange your follow up", "patient_visible": True,
        "category":"recommendation", "review_action_id": action["id"], "timeline_item_id":f"profile:{patient.id}:record"}).json()
    assert internal["patient_visible"] is False
    assert public["doctor_id"] == doctors[0].id and public["provenance"] == "clinician_authored"
    assert public["created_at"] == public["updated_at"]
    assert len(client.get(route, headers=auth(doctors[0])).json()) == 2
    status = client.get(ROOT+"/review-status", headers=auth(patient)).json()
    assert [n["id"] for n in status["notes"]] == [public["id"]]
    assert internal["content"] not in json.dumps(status)
    for method in ("patch", "put", "delete"):
        assert getattr(client, method)(route+"/"+internal["id"], headers=auth(doctors[0])).status_code in (404,405)
    assert db.query(ClinicalNote).count() == 2
    audits = db.query(AuditLog).filter_by(action="CLINICAL_NOTE_ADDED").all()
    assert len(audits) == 2 and all("content" not in a.details for a in audits)

@pytest.mark.parametrize("payload", [{"content":"short"}, {"content":" "*20},
    {"content":"Clinical note here", "unknown":1}, {"content":"Clinical note here", "priority":"diagnosis"},
    {"content":"Clinical note here", "timeline_item_id":"profile:foreign:record"},
    {"content":"Clinical note here", "review_action_id":"missing"}])
def test_invalid_note_no_partial_persistence(loop, payload):
    client, db, _, _, doctors=loop;grant(loop)
    assert client.post(ROOT+"/patients/patient/notes", headers=auth(doctors[0]), json=payload).status_code == 422
    assert db.query(ClinicalNote).count() == 0
    assert db.query(AuditLog).filter_by(action="CLINICAL_NOTE_ADDED").count() == 0

@pytest.mark.parametrize("payload", [{"state":"unknown"}, {"expected_sequence":-1}, {"expected_sequence":True},
    {"recommendation":"diagnosis"}, {"recommendation":"track"}, {"rationale":" "*15}, {"unknown":True}])
def test_invalid_review_no_partial_persistence(loop, payload):
    _, db, _, _, _=loop;grant(loop)
    assert review(loop, **payload).status_code == 422
    assert db.query(DoctorReviewAction).count() == 0
    assert db.query(AuditLog).filter_by(action="DOCTOR_REVIEW_RECORDED").count() == 0


def test_review_history_states_conflict_and_visibility(loop):
    client, db, patient, _, doctors=loop;grant(loop)
    assert client.get(ROOT+"/review-status", headers=auth(patient)).json()["state"] == "pending"
    for sequence, state in enumerate(("pending", "in_review", "reviewed", "follow_up_needed")):
        response=review(loop, state=state, expected_sequence=sequence, patient_visible=sequence==2,
            recommendation="doctor_review", rationale="Clinician recommendation for follow up")
        assert response.status_code == 201 and response.json()["sequence"] == sequence+1
        assert response.json()["doctor_id"] == doctors[0].id
    assert review(loop).status_code == 409
    assert db.query(DoctorReviewAction).count() == 4
    patient_result = client.get(ROOT+"/review-status", headers=auth(patient)).json()
    assert patient_result["state"] == "follow_up_needed" and patient_result["current_decision"] is None
    assert len(patient_result["history"]) == 1 and patient_result["changed_by"] == doctors[0].id
    assert len(client.get(ROOT+"/patients/patient/reviews", headers=auth(doctors[0])).json()["history"]) == 4
    assert db.query(AuditLog).filter_by(action="DOCTOR_REVIEW_RECORDED").count() == 4

@pytest.mark.parametrize("recommendation", ["track", "low_risk_self_care", "doctor_review", "urgent"])
def test_clinician_cannot_erase_safety(loop, recommendation):
    client, db, patient, _, doctors=loop;grant(loop); evidence=urgent(db,patient)
    before=client.get("/api/v1/safety",headers=auth(patient)).json()
    response=review(loop, recommendation=recommendation, rationale="Recorded clinician decision after review", patient_visible=True)
    assert response.status_code==201
    result=response.json()
    assert result["safety_at_review"]["status"]=="urgent" and result["urgent_safety_preserved"]
    assert result["lower_than_current_safety"] == (recommendation!="urgent")
    assert result["diverges_from_current_safety"] == (recommendation!="urgent")
    after=client.get("/api/v1/safety",headers=auth(patient)).json()
    assert before["reasons"]==after["reasons"] and after["status"]=="urgent"
    assert any(e["id"]==evidence.id for reason in result["safety_at_review"]["reasons"] for e in reason["evidence"])
    status=client.get(ROOT+"/review-status",headers=auth(patient)).json()
    assert status["safety"]["status"]=="urgent" and status["current_decision"]["recommendation"]==recommendation
    listing=client.get(ROOT+"/patients",headers=auth(doctors[0])).json()[0]
    assert listing["priority"]=="urgent" and listing["safety"]["status"]=="urgent"
    assert client.post("/api/v1/assistance", headers=auth(patient), json={"message":"I feel reassured"}).json()["authoritative_safety"]["status"]=="urgent"


def test_timeline_sources_provenance_order_pagination_and_unknowns(loop):
    client,db,patient,foreign,doctors=loop;grant(loop)
    now=datetime.now(timezone.utc)-timedelta(minutes=1)
    patient.profile_context={"sensitivities_allergies":["fragrance"]};db.commit()
    product=Product(id="product",user_id=patient.id,name="Serum",active_ingredients=["niacinamide", "retinol"])
    db.add(product);db.commit()
    entry=RoutineEntry(id="entry",user_id=patient.id,product_id=product.id,schedule="AM",frequency="daily",start_date=now.date(),source="user_configured",active_am_product=product.id)
    db.add(entry);db.commit()
    exp=Experiment(id="exp",user_id=patient.id,product_id=product.id,routine_entry_id=entry.id,engine_version=2,
        intervention={"type":"stop_entry"},source="user_configured",status="completed",target_days=7)
    db.add(exp);db.commit()
    capture=Capture(id="capture",user_id=patient.id,state="accepted",source="camera",view="front",quality={"decision":"accepted"},storage="not_persisted",server_version="v1",received_at=now)
    db.add(capture);db.commit()
    db.add_all([DailyContext(user_id=patient.id,date=now.date(),unusual_conditions=False),
        RoutineAdherence(user_id=patient.id,routine_entry_id=entry.id,date=now.date(),slot="AM",status="completed",configuration_snapshot={}),
        ExperimentEvaluation(user_id=patient.id,experiment_id=exp.id,result={"engine_version":2,"label":"insufficient_evidence"}),
        Measurement(user_id=patient.id,capture_id=capture.id,algorithm_version="v1",status="unavailable",results={},quality_reference={},comparison={}),
        CheckIn(id="ai",user_id=patient.id,date_str="today",ai_vision_analysis={"simulated":True,"assessment":"Model prose"}),
        CheckIn(id="foreign-record",user_id=foreign.id,date_str="today",notes="Foreign secret"),
        CheckIn(id="future",user_id=patient.id,date_str="future",created_at=now+timedelta(days=2))])
    for day in range(20):
        db.add(CheckIn(id=f"history-{day}",user_id=patient.id,date_str="day",created_at=now-timedelta(days=day),
            hydration_score=50,texture_score=50,redness_score=50,ai_vision_analysis={"measurement_source":"manual"}))
    db.commit();review(loop)
    client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[0]),json={"content":"Clinician timeline assessment"})
    response=client.get(ROOT+"/patients/patient/timeline?limit=200",headers=auth(doctors[0]))
    assert response.status_code==200
    result=response.json();items=result["items"]
    sources={i["source"] for i in items}
    assert {"profile","baseline","checkin","daily_context","routine","adherence","experiment","experiment_evaluation","capture","measurement","product_intelligence","safety","personal_skin_model","clinical_note","doctor_review"} <= sources
    assert {i["category"] for i in items}=={"patient_reported","system_observed","deterministic_derived","ai_inferred","clinician_authored"}
    assert all(i["category"]=="clinician_authored" for i in items if i["source"] in ("clinical_note","doctor_review"))
    assert next(i for i in items if i["source_id"]=="ai" and i["field"]=="ai_analysis")["category"]=="ai_inferred"
    assert any(i["source_id"]=="history-19" and i["field"]=="tracking_scores" for i in items)
    assert not any(i["source_id"] in ("foreign-record","future") for i in items)
    assert "Foreign secret" not in json.dumps(result) and "access_token" not in json.dumps(result) and "hashed_password" not in json.dumps(result)
    assert len({i["id"] for i in items})==len(items)
    assert items==sorted(items,key=lambda i:(i["recorded_at"] or "",i["id"]))
    page=client.get(ROOT+"/patients/patient/timeline?offset=1&limit=2",headers=auth(doctors[0])).json()
    assert [i["id"] for i in page["items"]]==[i["id"] for i in items[1:3]] and page["next_offset"]==3
    assert result["unknowns"]


def test_missing_sources_stay_unknown(loop):
    client,_,_,_,doctors=loop;grant(loop)
    result=client.get(ROOT+"/patients/patient/timeline",headers=auth(doctors[0])).json()
    assert result["derived_source_availability"]["checkin"]["state"]=="missing"
    assert next(i for i in result["items"] if i["source"]=="profile")["data"]["disclosures"] is None
    assert any("absence is not negative" in u for u in result["unknowns"])

@pytest.mark.parametrize("owner", ["patient", "doctor"])
def test_deletion_cleans_clinician_records_and_sessions(loop,monkeypatch,owner):
    client,db,patient,_,doctors=loop;grant(loop);review(loop)
    action=db.query(DoctorReviewAction).one()
    client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[0]),json={"content":"Linked clinical note", "review_action_id":action.id})
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",lambda _:None)
    doctor_headers=auth(doctors[0])
    target=patient if owner=="patient" else doctors[0]
    headers=auth(target)
    assert client.delete("/api/v1/users/me",headers=headers).status_code==204
    assert db.query(DoctorReviewAction).count()==db.query(ClinicalNote).count()==db.query(DoctorPatientAccess).count()==0
    assert client.get("/api/v1/users/me",headers=headers).status_code==401
    assert client.get(ROOT+"/patients/patient",headers=doctor_headers).status_code in (401,403)


def test_logged_out_doctor_session_denied(loop):
    client,_,_,_,doctors=loop;grant(loop);headers=auth(doctors[0])
    assert client.post("/api/v1/auth/logout",headers=headers).status_code==204
    assert client.get(ROOT+"/patients/patient/timeline",headers=headers).status_code==401

@pytest.mark.parametrize("kind", ["notes","reviews","generate-qr","claim","revoke"])
def test_commit_failure_rolls_back_clinician_and_audit(loop,monkeypatch,kind):
    client,db,patient,_,doctors=loop;access=grant(loop)
    count=db.query(AuditLog).count()
    monkeypatch.setattr(db,"commit",Mock(side_effect=RuntimeError("Database unavailable")))
    if kind=="notes":
        response=client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[0]),json={"content":"Clinical assessment note"})
    elif kind=="reviews": response=review(loop)
    elif kind=="generate-qr":response=client.post(ROOT+"/generate-qr",headers=auth(patient))
    elif kind=="claim":response=client.post(ROOT+"/claim",headers=auth(doctors[0]),json={"access_token":access.access_token})
    else:response=client.delete(ROOT+f"/access/{access.id}",headers=auth(patient))
    assert response.status_code==503
    assert db.query(ClinicalNote).count()==db.query(DoctorReviewAction).count()==0
    assert db.query(AuditLog).count()==count and db.query(DoctorPatientAccess).count()==1
    assert db.get(DoctorPatientAccess,access.id).status=="active"


@pytest.mark.parametrize("values", [{"patient_visible":"false"}, {"patient_visible":1}, {"doctor_id":"foreign"}])
def test_note_identity_visibility_payload_is_strict(loop, values):
    client,db,_,_,doctors=loop;grant(loop)
    assert client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[0]),
        json={"content":"Clinical note content",**values}).status_code==422
    assert db.query(ClinicalNote).count()==0


def test_foreign_review_link_is_rejected(loop):
    client,db,patient,foreign,doctors=loop;grant(loop);access=grant(loop,patient=foreign)
    action=client.post(ROOT+"/patients/foreign/reviews",headers=auth(doctors[0]),json={"state":"reviewed","expected_sequence":0}).json()
    assert client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[0]),
        json={"content":"Clinical note content","review_action_id":action["id"]}).status_code==422
    assert db.query(ClinicalNote).count()==0


def test_measurement_validation_and_safety_snapshot_are_preserved(loop):
    client,db,patient,_,doctors=loop;grant(loop);urgent(db,patient)
    action=review(loop,recommendation="track",rationale="Clinician decision after examining patient").json()
    now=datetime.now(timezone.utc)
    c=Capture(id="validated-capture",user_id=patient.id,state="accepted",source="camera",view="front",quality={},storage="not_persisted",server_version="v1")
    db.add(c);db.commit()
    valid={"status":"measured","method_version":"v1","source_capture_id":c.id,"unit":"fraction_0_to_1","value":0.4}
    db.add(Measurement(id="validated-measurement",user_id=patient.id,capture_id=c.id,algorithm_version="v1",status="measured",
        results={"red_chromaticity_proxy":valid,"texture_contrast_proxy":{**valid,"source_capture_id":"foreign"}},
        quality_reference={"decision":"accepted"},comparison={}))
    db.commit()
    timeline=client.get(ROOT+"/patients/patient/timeline?limit=200",headers=auth(doctors[0])).json()
    item=next(i for i in timeline["items"] if i["source_id"]=="validated-measurement")
    assert item["category"]=="system_observed"
    assert set(item["data"]["values"])=={"red_chromaticity_proxy"}
    assert item["provenance"]["clinical_measurement"] is False
    # Later safety freshness changes cannot rewrite a clinician's recorded snapshot.
    for row in db.query(CheckIn): row.created_at=now-timedelta(days=20)
    db.commit()
    current=client.get(ROOT+"/patients/patient/reviews",headers=auth(doctors[0])).json()
    assert current["safety"]["status"]=="track"
    assert current["history"][0]["safety_at_review"]==action["safety_at_review"]


def test_doctor_deletion_cleans_other_clinician_note_link_safely(loop, monkeypatch):
    client,db,patient,_,doctors=loop;grant(loop);grant(loop,doctor=1)
    action=review(loop).json()
    assert client.post(ROOT+"/patients/patient/notes",headers=auth(doctors[1]),json={
        "content":"Linked cross clinician clinical note", "review_action_id":action["id"]}).status_code==201
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",lambda _:None)
    assert client.delete("/api/v1/users/me",headers=auth(doctors[0])).status_code==204
    assert db.query(ClinicalNote).count()==db.query(DoctorReviewAction).count()==0
    assert client.get(ROOT+"/patients/patient",headers=auth(doctors[1])).status_code==200


@pytest.mark.parametrize("query", ["limit=0","limit=201","offset=-1","offset=invalid"])
def test_invalid_timeline_pagination(loop,query):
    client,_,_,_,doctors=loop;grant(loop)
    assert client.get(ROOT+"/patients/patient/timeline?"+query,headers=auth(doctors[0])).status_code==422
