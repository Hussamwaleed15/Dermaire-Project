"""Synthetic contract tests; no external services or patient data."""
from datetime import datetime, timedelta, timezone
import json
import pytest
from fastapi import HTTPException
from app.core.security import create_doctor_access_token
from app.models import DoctorPatientAccess, AuditLog
from app.services.doctor_loop import authorize, access_out
from tests.test_doctor_loop import loop, auth, grant, ROOT


def generate(loop, payload=None):
    client, _, patient, _, _ = loop
    return client.post(ROOT + "/generate-qr", headers=auth(patient),
        **({"json": payload} if payload is not None else {}))


@pytest.mark.parametrize("payload", [None, {"view_consent": True},
    {"view_consent": True, "export_consent": False}])
def test_view_never_implies_export(loop, payload):
    client, db, patient, _, doctors = loop
    created = generate(loop, payload)
    assert created.status_code == 200
    receipt = created.json()["access"]
    assert receipt["scopes"] == ["VIEW"] and receipt["export_consent"] is False
    assert receipt["effective_scopes"] == []
    claimed = client.post(ROOT + "/claim", headers=auth(doctors[0]),
        json={"access_token": created.json()["access_token"]})
    assert claimed.status_code == 200
    assert claimed.json()["access"]["effective_scopes"] == ["VIEW"]
    row = db.get(DoctorPatientAccess, receipt["id"])
    row.export_consent = True  # Legacy/default bool cannot broaden signed intent.
    db.commit()
    assert access_out(row)["export_consent"] is False
    assert authorize(db, doctors[0], patient.id)[1].id == row.id
    with pytest.raises(HTTPException) as denied:
        authorize(db, doctors[0], patient.id, scope="EXPORT")
    assert denied.value.status_code == 403


def test_explicit_export_bound_to_selected_doctor_and_receipts(loop):
    client, db, patient, foreign, doctors = loop
    created = generate(loop, {"view_consent": True, "export_consent": True, "doctor_id": doctors[0].id})
    assert created.status_code == 200
    token = created.json()["access_token"]
    pending = created.json()["access"]
    assert pending["doctor_name"] == doctors[0].full_name
    assert pending["scopes"] == ["VIEW", "EXPORT"] and pending["effective_scopes"] == []
    assert pending["granted_by"] == patient.id and pending["consent_version"] == 2
    assert client.post(ROOT + "/claim", headers=auth(doctors[1]), json={"access_token": token}).status_code == 403
    assert client.post(ROOT + "/claim", headers=auth(patient), json={"access_token": token}).status_code == 403
    claimed = client.post(ROOT + "/claim", headers=auth(doctors[0]), json={"access_token": token})
    assert claimed.status_code == 200
    assert claimed.json()["access"]["effective_scopes"] == ["VIEW", "EXPORT"]
    row = authorize(db, doctors[0], patient.id, scope="EXPORT")[1]
    owned = client.get(ROOT + "/access", headers=auth(patient)).json()
    assert owned == [claimed.json()["access"]]
    assert token not in json.dumps(owned)
    assert client.get(ROOT + "/access", headers=auth(foreign)).json() == []
    assert client.post(ROOT + "/claim", headers=auth(doctors[0]), json={"access_token": token}).status_code == 409
    assert db.query(AuditLog).filter_by(action="PATIENT_ACCESS_CLAIMED").count() == 1
    revoked = client.delete(ROOT + f"/access/{row.id}", headers=auth(patient)).json()
    assert revoked["effective_scopes"] == [] and revoked["revoked_by"] == patient.id
    with pytest.raises(HTTPException):
        authorize(db, doctors[0], patient.id, scope="EXPORT")


@pytest.mark.parametrize("payload", [ {}, {"view_consent": False}, {"view_consent": "true"},
    {"view_consent": 1}, {"view_consent": True, "export_consent": 1},
    {"view_consent": True, "export_consent": "true"},
    {"view_consent": True, "export_consent": True},
    {"view_consent": True, "actor_id": "foreign"},
    {"view_consent": True, "scopes": ["EXPORT"]}])
def test_bad_consent_cannot_create_grant(loop, payload):
    _, db, _, _, _ = loop
    assert generate(loop, payload).status_code == 422
    assert db.query(DoctorPatientAccess).count() == 0


@pytest.mark.parametrize("kind", ["missing", "patient"])
def test_selected_doctor_must_exist_with_live_role(loop, kind):
    _, db, patient, _, _ = loop
    assert generate(loop, {"view_consent": True, "doctor_id": patient.id if kind == "patient" else "missing"}).status_code == 404
    assert db.query(DoctorPatientAccess).count() == 0


@pytest.mark.parametrize("kind", ["expired", "revoked", "logout", "credential", "legacy", "owner"])
def test_pending_invalid_or_stale_intent_cannot_be_claimed(loop, kind):
    client, db, patient, foreign, doctors = loop
    headers = auth(patient)
    created = client.post(ROOT + "/generate-qr", headers=headers).json()
    row = db.get(DoctorPatientAccess, created["access"]["id"])
    if kind == "expired": row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    elif kind == "revoked": client.delete(ROOT + f"/access/{row.id}", headers=auth(patient))
    elif kind == "logout": client.post("/api/v1/auth/logout", headers=headers)
    elif kind == "credential": patient.hashed_password = "changed-test-only"
    elif kind == "legacy": row.access_token = create_doctor_access_token(patient.id)
    elif kind == "owner": row.patient_id = foreign.id
    db.commit()
    assert client.post(ROOT + "/claim", headers=auth(doctors[0]), json={"access_token": row.access_token}).status_code in (400, 403)
    assert db.get(DoctorPatientAccess, row.id).status != "active"


def test_legacy_active_view_preserved_export_denied(loop):
    client, db, patient, _, doctors = loop
    row = grant(loop)
    row.access_token = create_doctor_access_token(patient.id)
    row.export_consent = True
    db.commit()
    assert client.get(ROOT + "/patients/patient/timeline", headers=auth(doctors[0])).status_code == 200
    receipt = access_out(row)
    assert receipt["scopes"] == ["VIEW"] and receipt["export_consent"] is False
    assert receipt["consent_source"] == "legacy_view_only"
    with pytest.raises(HTTPException): authorize(db, doctors[0], patient.id, scope="EXPORT")
    row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert access_out(row)["effective_scopes"] == []


def test_model_new_grants_deny_export_by_default(loop):
    _, db, patient, _, _ = loop
    row = DoctorPatientAccess(patient_id=patient.id, access_token="synthetic-only",
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=10))
    db.add(row); db.commit()
    assert row.export_consent is False


def test_qr_fits_existing_db_and_untrusted_export_query_is_ignored(loop):
    client, _, patient, _, _ = loop
    result = client.post(ROOT + "/generate-qr?export_consent=true", headers=auth(patient))
    assert result.status_code == 200
    assert len(result.json()["access_token"]) <= 512
    assert result.json()["access"]["scopes"] == ["VIEW"]
