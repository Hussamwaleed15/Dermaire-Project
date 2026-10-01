from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from sqlalchemy.exc import IntegrityError

from app.core.database import Base, get_db
from app.core.exceptions import DermaireException
from app.core.security import create_access_token, verify_password
from app.main import app
from app.models import User, AuditLog, DoctorPatientAccess, ClinicalNote
from app.tools import provision_user as tool
from app.tools.provision_user import ProvisionRequest, provision_user


@pytest.fixture
def provisioning_context():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as client:
        yield db, client
    app.dependency_overrides.clear()
    db.close(); engine.dispose()


def request(role="doctor", email="trusted@example.com", **overrides):
    data = dict(email=email, full_name="Verified clinician", role=role,
                password="Test-only-password-12!", verification_reference="TEST-APPROVAL")
    data.update(overrides)
    return ProvisionRequest(**data)


def auth(user):
    return {"Authorization": "Bearer " + create_access_token(user.id, user.role, hashed_password=user.hashed_password)}


@pytest.mark.parametrize("role", ["doctor", "admin", "support"])
def test_trusted_provisioning_and_real_login(provisioning_context, role):
    db, client = provisioning_context
    user = provision_user(db, request(role), operator="test-operator")
    assert user.role == role
    assert verify_password("Test-only-password-12!", user.hashed_password)
    assert user.hashed_password != "Test-only-password-12!"
    assert not user.safety_accepted
    audit = db.query(AuditLog).one()
    assert audit.action == "PRIVILEGED_ACCOUNT_PROVISIONED"
    assert audit.details["role"] == role
    assert "password" not in str(audit.details)
    login = client.post("/api/v1/auth/login", json={"email": user.email, "password": "Test-only-password-12!"})
    assert login.status_code == 200
    assert login.json()["role"] == role
    assert login.json()["user_id"] == user.id
    assert client.get("/api/v1/users/me", headers={"Authorization": "Bearer " + login.json()["access_token"]}).json()["role"] == role


@pytest.mark.parametrize("role", ["doctor", "admin", "support"])
def test_public_creation_and_elevation_cannot_assign_roles(provisioning_context, role):
    db, client = provisioning_context
    payload = dict(email="public@example.com", password="Public-test-password!", full_name="Public patient", accept_safety=True)
    assert client.post("/api/v1/auth/register", json={**payload, "role": role}).status_code == 422
    assert db.query(User).count() == 0
    response = client.post("/api/v1/auth/register", json=payload)
    assert response.status_code == 201
    headers = {"Authorization": "Bearer " + response.json()["access_token"]}
    for route in ("/api/v1/auth/provision", "/api/v1/users/provision", "/api/v1/doctor/register"):
        assert client.post(route, json={**payload, "role": role}).status_code == 404
        assert client.post(route, headers=headers, json={**payload, "role": role}).status_code == 404
    client.patch("/api/v1/users/skin-profile", headers=headers, json={"role": role})
    assert client.get("/api/v1/users/me", headers=headers).json()["role"] == "patient"
    # Even a misleading claim in a valid token cannot override the database role.
    patient = db.query(User).one()
    forged_role = {"Authorization": "Bearer " + create_access_token(patient.id, role, hashed_password=patient.hashed_password)}
    assert client.get("/api/v1/doctor/patients", headers=forged_role).status_code == 403
    assert client.get("/api/v1/doctor/patients").status_code == 401
    assert client.get("/api/v1/doctor/patients", headers=headers).status_code == 403


def test_google_signup_stays_patient_and_existing_doctor_authenticates(provisioning_context, monkeypatch):
    db, client = provisioning_context
    from app.api.v1 import auth as auth_module
    verifier = Mock(return_value={"email": "google@example.com", "email_verified": True, "name": "Verified Google"})
    monkeypatch.setattr(auth_module.google_id_token, "verify_oauth2_token", verifier)
    response = client.post("/api/v1/auth/google", json={"id_token": "test-token", "role": "admin"})
    assert response.status_code == 200
    assert response.json()["role"] == "patient"
    doctor = provision_user(db, request(), operator="test-operator")
    verifier.return_value = {"email": doctor.email, "email_verified": True, "name": doctor.full_name}
    response = client.post("/api/v1/auth/google", json={"id_token": "test-token"})
    assert response.json()["role"] == "doctor"
    assert response.json()["user_id"] == doctor.id


def test_duplicate_and_patient_conversion_are_rejected(provisioning_context):
    db, client = provisioning_context
    client.post("/api/v1/auth/register", json=dict(email="trusted@example.com", password="Patient-test-password!", full_name="Patient", accept_safety=True))
    before = db.query(User).one().hashed_password
    with pytest.raises(DermaireException) as error:
        provision_user(db, request(email="TRUSTED@example.com"), operator="test-operator")
    assert error.value.status_code == 409
    user = db.query(User).one()
    assert user.role == "patient" and user.hashed_password == before
    assert db.query(AuditLog).filter(AuditLog.action == "PRIVILEGED_ACCOUNT_PROVISIONED").count() == 0
    doctor = provision_user(db, request(email="second@example.com"), operator="test-operator")
    with pytest.raises(DermaireException):
        provision_user(db, request(role="admin", email=doctor.email), operator="test-operator")
    assert doctor.role == "doctor"


@pytest.mark.parametrize("override", [
    {"role": "patient"}, {"role": "root"}, {"email": "invalid"},
    {"full_name": " "}, {"password": "short"}, {"password": "a" * 73},
    {"verification_reference": " "}, {"unknown": True},
])
def test_invalid_provisioning_is_rejected(override):
    with pytest.raises(ValidationError):
        request(**override)


@pytest.mark.parametrize("failure", [RuntimeError("Commit unavailable"), IntegrityError("conflict", {}, None)])
def test_provisioning_failure_rolls_back_account_and_audit(provisioning_context, monkeypatch, failure):
    db, _ = provisioning_context
    monkeypatch.setattr(db, "commit", Mock(side_effect=failure))
    with pytest.raises((RuntimeError, DermaireException)):
        provision_user(db, request(), operator="test-operator")
    assert db.query(User).count() == 0
    assert db.query(AuditLog).count() == 0


def test_cli_requires_interactive_operator_and_hides_invalid_password(provisioning_context, monkeypatch, capsys):
    db, _ = provisioning_context
    args = ["--email", "trusted@example.com", "--full-name", "Verified Clinician", "--role", "doctor", "--verification-reference", "TEST-APPROVAL"]
    monkeypatch.setattr(tool.sys.stdin, "isatty", lambda: False)
    with pytest.raises(SystemExit):
        tool.main(args)
    monkeypatch.setattr(tool.sys.stdin, "isatty", lambda: True)
    monkeypatch.setattr(tool.getpass, "getpass", lambda _: "short")
    assert tool.main(args) == 1
    assert "short" not in capsys.readouterr().err
    assert db.query(User).count() == 0


def test_doctor_consent_access_remains_server_enforced(provisioning_context):
    db, client = provisioning_context
    doctor = provision_user(db, request(), operator="test-operator")
    other = provision_user(db, request(email="other@example.com"), operator="test-operator")
    support = provision_user(db, request(role="support", email="support@example.com"), operator="test-operator")
    registered = client.post("/api/v1/auth/register", json=dict(email="patient@example.com", password="Patient-test-password!", full_name="Patient", accept_safety=True)).json()
    patient_id = registered["user_id"]
    patient_headers = {"Authorization": "Bearer " + registered["access_token"]}
    note_route = f"/api/v1/doctor/patients/{patient_id}/notes"
    assert client.post(note_route, headers=auth(doctor), json={"content": "A verified clinical note."}).status_code == 403
    qr = client.post("/api/v1/doctor/generate-qr", headers=patient_headers).json()["access_token"]
    assert client.post("/api/v1/doctor/claim", headers=auth(support), json={"access_token": qr}).status_code == 403
    assert client.post("/api/v1/doctor/claim", headers=auth(doctor), json={"access_token": qr}).status_code == 200
    assert client.post("/api/v1/doctor/claim", headers=auth(other), json={"access_token": qr}).status_code == 403
    assert client.get("/api/v1/doctor/patients", headers=auth(other)).json() == []
    assert client.get("/api/v1/doctor/patients", headers=auth(doctor)).json()[0]["patient_id"] == patient_id
    assert client.post(note_route, headers=auth(doctor), json={"content": "A verified clinical note."}).status_code == 201
    grant = db.query(DoctorPatientAccess).one()
    grant.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db.commit()
    assert client.get("/api/v1/doctor/patients", headers=auth(doctor)).json() == []
    assert client.post(note_route, headers=auth(doctor), json={"content": "An expired note request."}).status_code == 403
    grant.expires_at = datetime.now(timezone.utc) + timedelta(hours=1)
    db.commit()
    assert client.delete(f"/api/v1/doctor/revoke/{patient_id}", headers=patient_headers).status_code == 200
    assert client.get("/api/v1/doctor/patients", headers=auth(doctor)).json() == []
    assert client.post(note_route, headers=auth(doctor), json={"content": "A revoked note request."}).status_code == 403
    assert db.query(ClinicalNote).count() == 1


def test_operator_identity_is_required(provisioning_context):
    db, _ = provisioning_context
    with pytest.raises(ValueError):
        provision_user(db, request(), operator=" ")
    assert db.query(User).count() == 0


def test_cli_provisions_and_rejects_password_mismatch(provisioning_context, monkeypatch, capsys):
    db, _ = provisioning_context
    args = ["--email", "TRUSTED@example.com", "--full-name", "Verified Clinician", "--role", "doctor", "--verification-reference", "TEST-APPROVAL"]
    monkeypatch.setattr(tool.sys.stdin, "isatty", lambda: True)
    passwords = iter(["Test-only-password-12!", "Mismatch-only-password-12!"])
    monkeypatch.setattr(tool.getpass, "getpass", lambda _: next(passwords))
    assert tool.main(args) == 1
    assert db.query(User).count() == 0
    monkeypatch.setattr(tool.getpass, "getpass", lambda _: "Test-only-password-12!")
    monkeypatch.setattr(tool.getpass, "getuser", lambda: "test-operator")
    monkeypatch.setattr(tool, "SessionLocal", lambda: db)
    assert tool.main(args) == 0
    assert db.query(User).one().email == "trusted@example.com"
    assert db.query(AuditLog).one().details["operator"] == "test-operator"
    output = capsys.readouterr()
    assert "Test-only-password" not in output.out + output.err
