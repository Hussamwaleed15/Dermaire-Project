"""Authorization and receipt regression coverage on existing routes only."""
from datetime import datetime, timedelta, timezone
import json
import pytest
from fastapi import HTTPException
from app.models import DoctorPatientAccess, AuditLog
from app.services.doctor_loop import authorize
from tests.test_doctor_loop import loop, auth, grant, ROOT


def export_grant(loop):
    client, db, patient, _, doctors = loop
    created = client.post(ROOT + "/generate-qr", headers=auth(patient), json={
        "view_consent": True, "export_consent": True, "doctor_id": doctors[0].id}).json()
    assert client.post(ROOT + "/claim", headers=auth(doctors[0]),
        json={"access_token": created["access_token"]}).status_code == 200
    return db.get(DoctorPatientAccess, created["access"]["id"])


def test_scopes_resolve_eligible_grant_without_broadening_newer_view(loop):
    client, db, patient, _, doctors = loop
    export = export_grant(loop)
    view = grant(loop)
    assert authorize(db, doctors[0], patient.id, scope="EXPORT")[1].id == export.id
    assert client.delete(ROOT + f"/access/{export.id}", headers=auth(patient)).json()["effective_scopes"] == []
    assert authorize(db, doctors[0], patient.id)[1].id == view.id
    for scope in ("EXPORT", "ADMIN", "export", ""):
        with pytest.raises(HTTPException) as denied: authorize(db, doctors[0], patient.id, scope=scope)
        assert denied.value.status_code == 403


@pytest.mark.parametrize("change", ["revoked", "expired", "foreign_doctor", "foreign_patient", "missing_receipt", "legacy_true"])
def test_export_permission_requires_current_owned_evidence(loop, change):
    client, db, patient, foreign, doctors = loop
    row = export_grant(loop)
    if change == "revoked": client.delete(ROOT + f"/access/{row.id}", headers=auth(patient))
    elif change == "expired": row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    elif change == "missing_receipt":
        receipt = db.query(AuditLog).filter_by(action="DOCTOR_QR_GENERATED").one()
        receipt.details = {}
    elif change == "legacy_true":
        from app.core.security import create_doctor_access_token
        row.access_token = create_doctor_access_token(patient.id)
        row.export_consent = True
    db.commit()
    with pytest.raises(HTTPException) as denied:
        authorize(db, doctors[1] if change == "foreign_doctor" else doctors[0],
            foreign.id if change == "foreign_patient" else patient.id, scope="EXPORT")
    assert denied.value.status_code == 403


def test_revoke_is_owned_repeatable_and_never_leaks_private_intent(loop):
    client, db, patient, foreign, doctors = loop
    row = export_grant(loop)
    for who in (foreign, doctors[0]):
        response = client.delete(ROOT + f"/access/{row.id}", headers=auth(who))
        assert response.status_code in (403, 404)
        assert row.access_token not in response.text and patient.email not in response.text
    first = client.delete(ROOT + f"/access/{row.id}", headers=auth(patient))
    again = client.delete(ROOT + f"/access/{row.id}", headers=auth(patient))
    assert first.status_code == again.status_code == 200 and first.json() == again.json()
    assert first.json()["status"] == "revoked" and first.json()["effective_scopes"] == []
    assert db.query(AuditLog).filter_by(action="PATIENT_ACCESS_REVOKED").count() == 1
    readback = client.get(ROOT + "/access", headers=auth(patient))
    assert readback.json() == [first.json()]
    for receipt in (first.text, readback.text):
        assert all(private not in receipt for private in ("credential", "session_jti", "access_token", "hashed_password"))


@pytest.mark.parametrize("change", ["logout", "credential", "role"])
def test_claim_checks_current_doctor_identity_not_stale_jwt(loop, change):
    client, db, patient, _, doctors = loop
    created = client.post(ROOT + "/generate-qr", headers=auth(patient)).json()
    headers = auth(doctors[0])
    if change == "logout": client.post("/api/v1/auth/logout", headers=headers)
    elif change == "credential": doctors[0].hashed_password = "changed-test-only"
    else: doctors[0].role = "patient"
    db.commit()
    response = client.post(ROOT + "/claim", headers=headers, json={"access_token": created["access_token"]})
    assert response.status_code == (403 if change == "role" else 401)
    assert db.get(DoctorPatientAccess, created["access"]["id"]).status == "pending"
    assert db.query(AuditLog).filter_by(action="PATIENT_ACCESS_CLAIMED").count() == 0
