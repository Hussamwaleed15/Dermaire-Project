from datetime import datetime, timedelta, timezone
from unittest.mock import Mock

import pytest
from tests.test_account_deletion import deletion_context
from app.models import CheckIn, User, Experiment
from app.core.security import create_access_token
from app.services.azure_vision import azure_vision_service
from app.services.azure_blob import azure_blob_service
from fastapi.testclient import TestClient
from app.main import app


def add_measurement(db, day, texture=60, source="manual", user="delete-patient", linked=None):
    row = CheckIn(user_id=user, date_str="ignored display date", experiment_id=linked,
                  created_at=datetime(2026, 1, 1) + timedelta(days=day, seconds=db.query(CheckIn).count()),
                  hydration_score=80, texture_score=texture, redness_score=20,
                  ai_vision_analysis={"measurement_source": source})
    db.add(row)
    db.commit()
    return row


def test_empty_legacy_and_owner_isolation(deletion_context):
    client, db, auth = deletion_context
    user = db.get(User, "delete-patient")
    user.baseline_checkins_count = 5
    add_measurement(db, 0, source="simulated")
    add_measurement(db, 1, source=None)
    add_measurement(db, 2, user="delete-doctor")
    snapshot = client.get("/api/v1/baseline", headers=auth).json()
    assert snapshot["completed_days"] == 0 and snapshot["metrics"] == {}
    assert snapshot["today_checked_in"] is False
    assert client.get("/api/v1/users/me", headers=auth).json()["baseline_checkins_count"] == 0
    assert client.get("/api/v1/baseline").status_code == 401
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get("/api/v1/baseline", headers=other).json()["completed_days"] == 1
    # Stored seed deltas from old experiments must never escape through reads.
    exp = db.get(Experiment, "owned-experiment")
    exp.redness_delta_percent = -8
    db.commit()
    assert client.get("/api/v1/experiments/current", headers=auth).json()["redness_delta_percent"] is None


def test_distinct_days_averages_restart_and_frozen_reference(deletion_context):
    client, db, auth = deletion_context
    ids = []
    for day in range(5):
        ids.append(add_measurement(db, day, texture=60 + day).id)
        add_measurement(db, day, texture=99)  # Same UTC day does not advance progress.
    add_measurement(db, 6, texture=10)
    add_measurement(db, 7, linked="owned-experiment")
    snapshot = client.get("/api/v1/baseline", headers=auth).json()
    assert snapshot["status"] == "ready" and snapshot["completed_days"] == 5
    assert snapshot["checkin_ids"] == ids
    assert snapshot["metrics"]["texture"]["mean"] == 62
    assert snapshot["metrics"]["texture"]["standard_deviation"] == pytest.approx(2 ** .5)
    db.expire_all()
    assert client.get("/api/v1/baseline", headers=auth).json() == snapshot
    assert client.get("/api/v1/users/me", headers=auth).json()["baseline_checkins_count"] == 5


def test_confirmed_write_and_no_default_measurement_success(deletion_context):
    client, db, auth = deletion_context
    before = db.query(CheckIn).count()
    balance = db.get(User, "delete-patient").tokens_balance
    for data in ({}, {"hydration_score": 101, "texture_score": 70, "redness_score": 20},
                 {"hydration_score": "nan", "texture_score": 70, "redness_score": 20},
                 {"hydration_score": 80}):
        assert client.post("/api/v1/checkins", headers=auth, data=data).status_code == 422
    valid = {"hydration_score": 80, "texture_score": 70, "redness_score": 20}
    assert client.post("/api/v1/checkins", headers=auth, data={**valid, "experiment_id": "unknown"}).status_code == 404
    assert db.query(CheckIn).count() == before
    assert db.get(User, "delete-patient").tokens_balance == balance
    response = client.post("/api/v1/checkins", headers=auth, data=valid)
    assert response.status_code == 201
    assert response.json()["ai_vision_analysis"]["measurement_source"] == "manual"
    # Two writes today are two history entries, but one baseline day.
    assert client.post("/api/v1/checkins", headers=auth, data=valid).status_code == 201
    snapshot = client.get("/api/v1/baseline", headers=auth).json()
    assert snapshot["completed_days"] == 1 and snapshot["today_checked_in"] is True
    db.expire_all()
    assert client.get("/api/v1/baseline", headers=auth).json() == snapshot


def test_photo_failure_does_not_store_or_reward(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    before = db.query(CheckIn).count()
    balance = db.get(User, "delete-patient").tokens_balance
    monkeypatch.setattr(azure_vision_service, "analyze_skin_image", Mock(return_value={
        "azure_vision_status": "FALLBACK_SIMULATED", "erythema_redness_score": 22.5,
        "surface_texture_score": 78, "estimated_hydration_score": 75}))
    upload = Mock()
    monkeypatch.setattr(azure_blob_service, "upload_capture", upload)
    response = client.post("/api/v1/checkins", headers=auth, files={"photo": ("skin.png", valid_photo(), "image/png")})
    assert response.status_code == 503
    assert db.query(CheckIn).count() == before
    assert db.get(User, "delete-patient").tokens_balance == balance
    upload.assert_not_called()


def test_photo_proxy_is_explicit_and_server_supplies_measurements(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    monkeypatch.setattr(azure_vision_service, "analyze_skin_image", Mock(return_value={
        "azure_vision_status": "ANALYSIS_COMPLETE", "erythema_redness_score": 10,
        "surface_texture_score": 65, "estimated_hydration_score": 85}))
    monkeypatch.setattr(azure_blob_service, "upload_capture", Mock())
    response = client.post("/api/v1/checkins", headers=auth,
        files={"photo": ("skin.png", valid_photo(), "image/png")})
    assert response.status_code == 201 and response.json()["texture_score"] == 65
    assert response.json()["ai_vision_analysis"]["measurement_source"] == "image_proxy"
    assert client.get("/api/v1/baseline", headers=auth).json()["completed_days"] == 1


def test_deltas_use_confirmed_pre_experiment_baseline(deletion_context):
    client, db, auth = deletion_context
    for day in range(5):
        add_measurement(db, day, texture=50)
    data = {"hydration_score": 80, "texture_score": 75, "redness_score": 10,
            "experiment_id": "owned-experiment"}
    assert client.post("/api/v1/checkins", headers=auth, data=data).status_code == 201
    fresh = client.get("/api/v1/experiments/current", headers=auth).json()
    assert fresh["texture_delta_percent"] == 50 and fresh["redness_delta_percent"] == -50
    # Post-start measurements cannot fabricate a missing historical reference.
    exp = db.get(Experiment, "owned-experiment")
    exp.created_at = datetime(2025, 12, 1)
    db.commit()
    assert client.get("/api/v1/experiments/current", headers=auth).json()["texture_delta_percent"] is None


def test_database_failure_never_confirms_write(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    before = db.query(CheckIn).count()
    monkeypatch.setattr(db, "commit", Mock(side_effect=RuntimeError("Unavailable")))
    assert client.post("/api/v1/checkins", headers=auth,
                    data={"hydration_score": 80, "texture_score": 70, "redness_score": 20}).status_code == 503
    db.rollback()
    assert db.query(CheckIn).count() == before


def test_invalid_image_returns_unavailable():
    result = azure_vision_service.analyze_skin_image(b"not an image")
    assert result["azure_vision_status"] == "ANALYSIS_UNAVAILABLE"
    assert "surface_texture_score" not in result


def test_real_image_processing_produces_bounded_explicit_proxies():
    import io
    from PIL import Image
    image = io.BytesIO()
    Image.new("RGB", (20, 20), color=(120, 100, 100)).save(image, format="PNG")
    result = azure_vision_service.analyze_skin_image(image.getvalue())
    assert result["azure_vision_status"] == "ANALYSIS_COMPLETE"
    assert result["measurement_source"] == "image_proxy"
    assert "not Azure clinical analysis" in result["measurement_method"]
    assert 0 <= result["estimated_hydration_score"] <= 100


def test_baseline_read_failure_is_not_empty_success(deletion_context, monkeypatch):
    _, db, auth = deletion_context
    # Keep authentication's User lookup working and fail the health-data read.
    query = db.query
    def unavailable(model):
        if model is CheckIn:
            raise RuntimeError("Database unavailable")
        return query(model)
    monkeypatch.setattr(db, "query", unavailable)
    with TestClient(app, raise_server_exceptions=False) as client:
        assert client.get("/api/v1/baseline", headers=auth).status_code == 500


def test_storage_failure_cannot_advance_baseline(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    before = db.query(CheckIn).count()
    balance = db.get(User, "delete-patient").tokens_balance
    monkeypatch.setattr(azure_vision_service, "analyze_skin_image", Mock(return_value={
        "azure_vision_status": "ANALYSIS_COMPLETE", "erythema_redness_score": 10,
        "surface_texture_score": 65, "estimated_hydration_score": 85}))
    monkeypatch.setattr(azure_blob_service, "upload_capture", Mock(side_effect=RuntimeError("Storage unavailable")))
    assert client.post("/api/v1/checkins", headers=auth, files={"photo": ("skin.png", valid_photo(), "image/png")}).status_code == 503
    assert db.query(CheckIn).count() == before
    assert db.get(User, "delete-patient").tokens_balance == balance



def valid_photo():
    from io import BytesIO
    from pathlib import Path
    from PIL import Image
    image = Image.open(Path(__file__).parent / "fixtures/astronaut.png").crop((80, 0, 340, 320)).resize((800, 1000))
    buffer = BytesIO()
    image.save(buffer, format="PNG")
    image.close()
    return buffer.getvalue()
