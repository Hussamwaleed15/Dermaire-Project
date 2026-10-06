from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import pytest
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool
from fastapi.testclient import TestClient

from app.main import app
from app.core.database import Base, get_db
from app.core.security import create_access_token, create_refresh_token
from app.models import (User, Product, Experiment, CheckIn, ClinicalNote,
                        DoctorPatientAccess, AuditLog, RewardRedemption)
from app.services.azure_blob import azure_blob_service, AzureBlobService


@pytest.fixture
def deletion_context():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    @event.listens_for(engine, "connect")
    def foreign_keys(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")
    Base.metadata.create_all(engine)
    db = sessionmaker(bind=engine)()
    patient = User(id="delete-patient", email="delete@example.com", full_name="Private Name", hashed_password="unused")
    doctor = User(id="delete-doctor", email="doctor@example.com", full_name="Doctor", hashed_password="unused", role="doctor")
    db.add_all([patient, doctor]); db.commit()
    db.add(Product(id="owned-product", user_id=patient.id, name="Private product")); db.commit()
    db.add(Experiment(id="owned-experiment", user_id=patient.id, product_id="owned-product")); db.commit()
    db.add_all([
        CheckIn(user_id=patient.id, experiment_id="owned-experiment", date_str="2026-10-01", image_blob_name="skin_photos/owned.jpg", notes="Health data"),
        ClinicalNote(doctor_id=doctor.id, patient_id=patient.id, content="Private medical note"),
        DoctorPatientAccess(doctor_id=doctor.id, patient_id=patient.id, access_token="private-code", expires_at=datetime.now(timezone.utc)+timedelta(hours=1)),
        RewardRedemption(user_id=patient.id, reward_title="Reward"),
        AuditLog(actor_id=patient.id, action="PROFILE_UPDATED", target_resource="users", details={"email": patient.email, "notes": "health"}, ip_address="127.0.0.1"),
        AuditLog(actor_id=doctor.id, action="CLINICAL_NOTE_ADDED", target_resource="clinical_notes", details={"patient_id": patient.id}),
    ]); db.commit()
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as client:
        yield client, db, {"Authorization": "Bearer " + create_access_token(patient.id, "patient", hashed_password=patient.hashed_password)}
    app.dependency_overrides.clear()
    db.close(); engine.dispose()


def test_delete_success_and_retry(deletion_context, monkeypatch):
    client, db, headers = deletion_context
    delete = Mock()
    monkeypatch.setattr(azure_blob_service, "delete_image", delete)
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204
    delete.assert_called_once_with("skin_photos/owned.jpg")
    for model in (Product, Experiment, CheckIn, ClinicalNote, DoctorPatientAccess, RewardRedemption):
        assert db.query(model).count() == 0
    assert db.query(User).count() == 1
    assert client.get("/api/v1/users/me", headers=headers).status_code == 401
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204
    assert db.query(AuditLog).filter(AuditLog.action == "ACCOUNT_DELETED").count() == 1
    for audit in db.query(AuditLog):
        assert audit.actor_id != "delete-patient"
        assert audit.details == {}
        assert audit.ip_address is None


@pytest.mark.parametrize("authorization", [None, "Bearer invalid", "refresh"])
def test_delete_unauthorized(deletion_context, authorization):
    client, db, _ = deletion_context
    if authorization == "refresh":
        authorization = "Bearer " + create_refresh_token("delete-patient")
    headers = {"Authorization": authorization} if authorization else {}
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 401
    assert db.query(User).count() == 2


def test_cleanup_failure_can_retry(deletion_context, monkeypatch):
    client, db, headers = deletion_context
    delete = Mock(side_effect=OSError("Storage unavailable"))
    monkeypatch.setattr(azure_blob_service, "delete_image", delete)
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 503
    assert db.query(CheckIn).count() == 1
    assert db.query(ClinicalNote).count() == 1
    assert client.get("/api/v1/users/me", headers=headers).status_code == 200
    delete.side_effect = None
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204


def test_journal_failure_precedes_every_destructive_operation(deletion_context, monkeypatch):
    from app.services.account_deletion import deletion_journal
    client, db, headers = deletion_context
    monkeypatch.setattr(deletion_journal, "record", Mock(side_effect=OSError("journal unavailable")))
    delete = Mock()
    monkeypatch.setattr(azure_blob_service, "delete_image", delete)
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 503
    delete.assert_not_called()
    assert db.query(User).count() == 2
    assert db.query(CheckIn).count() == 1


def test_database_failure_rolls_back(deletion_context, monkeypatch):
    client, db, headers = deletion_context
    monkeypatch.setattr(azure_blob_service, "delete_image", Mock())
    commit = db.commit
    monkeypatch.setattr(db, "commit", Mock(side_effect=RuntimeError("Database unavailable")))
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 503
    assert db.query(User).count() == 2
    assert db.query(CheckIn).count() == 1
    monkeypatch.setattr(db, "commit", commit)
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204


def test_local_blob_cleanup_is_idempotent(tmp_path):
    service = object.__new__(AzureBlobService)
    service.is_live = False
    service.local_upload_dir = str(tmp_path)
    (tmp_path / "owned.jpg").write_bytes(b"private")
    service.delete_image("skin_photos/owned.jpg")
    service.delete_image("skin_photos/owned.jpg")
    assert not (tmp_path / "owned.jpg").exists()


def test_azure_cleanup_only_ignores_missing_blob():
    from azure.core.exceptions import ResourceNotFoundError
    service = object.__new__(AzureBlobService)
    service.is_live = True
    service.client = Mock()
    service.client.get_service_properties.return_value = {}
    service.container_client = Mock()
    service.container_client.list_blobs.return_value = []
    service.container_client.delete_blob.side_effect = ResourceNotFoundError("missing")
    service.delete_image("owned")
    service.container_client.delete_blob.assert_called_once_with("owned", delete_snapshots="include")
    service.container_client.delete_blob.side_effect = OSError("offline")
    with pytest.raises(OSError):
        service.delete_image("owned")


def test_namespaced_orphan_cleanup(tmp_path):
    service = object.__new__(AzureBlobService)
    service.is_live = False
    service.local_upload_dir = str(tmp_path)
    blob_name = "skin_photos/owner-1/owner-1_file.png"
    (tmp_path / "owner-1_file.png").write_bytes(b"private")
    (tmp_path / "owner-2_file.png").write_bytes(b"private")
    assert blob_name.startswith("skin_photos/owner-1/")
    service.delete_owned_images("owner-1")
    service.delete_owned_images("owner-1")
    assert len(list(tmp_path.iterdir())) == 1
    assert next(tmp_path.iterdir()).name.startswith("owner-2_")


def test_doctor_deletion_removes_grants_and_notes(deletion_context, monkeypatch):
    client, db, _ = deletion_context
    monkeypatch.setattr(azure_blob_service, "delete_owned_images", Mock())
    headers = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 204
    assert db.query(ClinicalNote).count() == 0
    assert db.query(DoctorPatientAccess).count() == 0
    assert db.query(CheckIn).count() == 1
    assert db.query(User).filter(User.id == "delete-patient").count() == 1


@pytest.mark.parametrize("properties", [
    {"delete_retention_policy": {"enabled": True}},
    {"is_versioning_enabled": True},
])
def test_retention_cannot_report_permanent_cleanup(properties):
    service = object.__new__(AzureBlobService)
    service.is_live = True
    service.client = Mock()
    service.client.get_service_properties.return_value = properties
    service.container_client = Mock()
    with pytest.raises(RuntimeError):
        service.delete_image("owned")
    service.container_client.delete_blob.assert_not_called()


def test_inconsistent_cross_owner_links_fail_without_mutation(deletion_context, monkeypatch):
    client, db, headers = deletion_context
    cleanup = Mock()
    monkeypatch.setattr(azure_blob_service, "delete_image", cleanup)
    db.add(Experiment(id="other-experiment", user_id="delete-doctor", product_id="owned-product"))
    db.add(CheckIn(id="other-checkin", user_id="delete-doctor", experiment_id="owned-experiment", date_str="today"))
    db.commit()
    assert client.delete("/api/v1/users/me", headers=headers).status_code == 503
    cleanup.assert_not_called()
    assert db.query(User).count() == 2
    assert db.get(Experiment, "other-experiment").product_id == "owned-product"
    assert db.get(CheckIn, "other-checkin").experiment_id == "owned-experiment"


def test_historical_blob_copies_block_success():
    service = object.__new__(AzureBlobService)
    service.is_live = True
    service.client = Mock()
    service.client.get_service_properties.return_value = {}
    service.container_client = Mock()
    blob = Mock()
    blob.name = "owned"
    blob.deleted = True
    blob.version_id = None
    service.container_client.list_blobs.return_value = [blob]
    with pytest.raises(RuntimeError):
        service.delete_image("owned")
    service.container_client.delete_blob.assert_not_called()
