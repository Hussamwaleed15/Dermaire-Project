from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import pytest
from tests.test_account_deletion import deletion_context
from tests.test_baseline_authority import add_measurement
from app.models import Experiment, Product, CheckIn
from app.core.security import create_access_token


def test_owner_projection_quarantines_seeded_truth(deletion_context):
    client, db, auth = deletion_context
    exp = db.get(Experiment, "owned-experiment")
    exp.current_day = 4
    exp.target_days = 14
    exp.primary_concern = "redness"
    exp.redness_delta_percent = -80
    db.commit()
    assert client.get("/api/v1/home").status_code == 401
    home = client.get("/api/v1/home", headers=auth).json()
    assert home["experiment"]["current_day"] == 4
    assert home["experiment"]["target_days"] == 14
    assert home["experiment"]["primary_concern"] == "redness"
    assert home["experiment"]["product_name"] == "Private product"
    assert home["experiment"]["redness_delta_percent"] is None
    assert home["journal"] == [] and home["today_checked_in"] is False
    add_measurement(db, 0, user="delete-doctor")
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    isolated = client.get("/api/v1/home", headers=other).json()
    assert isolated["experiment"] is None
    assert len(isolated["journal"]) == 1
    assert client.get("/api/v1/home", headers=auth).json()["journal"] == []
    # A corrupted product association must not disclose another owner's product.
    db.add(Product(id="other-product", user_id="delete-doctor", name="Other private product"))
    db.commit()
    exp.product_id = "other-product"
    db.commit()
    assert client.get("/api/v1/home", headers=auth).json()["experiment"]["product_name"] is None


def test_refresh_and_restart_use_persisted_measurements(deletion_context):
    client, db, auth = deletion_context
    for day in range(5):
        add_measurement(db, day, texture=50)
    exp = db.get(Experiment, "owned-experiment")
    exp.created_at = datetime(2026, 2, 1)
    db.commit()
    data = {"hydration_score": 80, "texture_score": 75, "redness_score": 10,
            "experiment_id": exp.id}
    response = client.post("/api/v1/checkins", headers=auth, data=data)
    assert response.status_code == 201
    home = client.get("/api/v1/home", headers=auth).json()
    assert home["experiment"]["texture_delta_percent"] == 50
    assert home["experiment"]["redness_delta_percent"] == -50
    assert home["today_checked_in"] is True
    assert home["journal"][0]["id"] == response.json()["id"]
    assert len(home["journal"]) == 2
    db.expire_all()
    fresh = client.get("/api/v1/home", headers=auth).json()
    # Dynamic Safety is reevaluated; its identity/time differ, persisted inputs do not.
    assert fresh["safety"]["provenance"]["evaluation_id"] != home["safety"]["provenance"]["evaluation_id"]
    for projection in (fresh, home):
        projection["safety"].pop("evaluated_at")
        projection["safety"]["provenance"].pop("evaluation_id")
        projection["safety"]["provenance"].pop("as_of")
    assert {k: v for k, v in fresh.items() if k != "as_of"} == {k: v for k, v in home.items() if k != "as_of"}
    assert client.patch(f"/api/v1/experiments/{exp.id}/toggle-pause", headers=auth).status_code == 200
    assert client.get("/api/v1/home", headers=auth).json()["experiment"]["status"] == "paused"
    # Newest legacy/default rows never become Home measurements or fake comparisons.
    db.add(CheckIn(user_id="delete-patient", experiment_id=exp.id, date_str="seed",
        created_at=datetime.now(timezone.utc) + timedelta(seconds=1)))
    db.commit()
    fresh = client.get("/api/v1/home", headers=auth).json()
    assert fresh["journal"] == home["journal"]
    assert fresh["experiment"]["texture_delta_percent"] is None
    exp.status = "completed"
    db.commit()
    assert client.get("/api/v1/home", headers=auth).json()["experiment"] is None


def test_missing_or_zero_reference_and_database_failure(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    for day in range(5):
        add_measurement(db, day, texture=0)
    exp = db.get(Experiment, "owned-experiment")
    exp.created_at = datetime(2026, 2, 1)
    db.commit()
    assert client.post("/api/v1/checkins", headers=auth, data={"hydration_score": 80,
        "texture_score": 75, "redness_score": 10, "experiment_id": exp.id}).status_code == 201
    assert client.get("/api/v1/home", headers=auth).json()["experiment"]["texture_delta_percent"] is None
    monkeypatch.setattr(db, "query", Mock(side_effect=RuntimeError("Unavailable")))
    with pytest.raises(RuntimeError):
        client.get("/api/v1/home", headers=auth)


def test_report_only_completion_is_separate_and_owned(deletion_context):
    import json
    client, db, auth = deletion_context
    before = client.get("/api/v1/baseline", headers=auth).json()
    response = client.post("/api/v1/checkins", headers=auth,
        data={"report": json.dumps({"overall_change": "same", "symptoms": []})})
    assert response.status_code == 201
    identifier = response.json()["id"]
    home = client.get("/api/v1/home", headers=auth).json()
    assert home["today_checked_in"] is False and home["journal"] == []
    observation = home["observation_status"]
    assert observation["today_completed"] is True
    assert observation["day_basis"] == "UTC"
    assert observation["recent"][0]["id"] == identifier
    assert observation["recent"][0]["kind"] == "report_only"
    assert observation["recent"][0]["measurement_available"] is False
    assert client.get("/api/v1/baseline", headers=auth).json() == before
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get("/api/v1/home", headers=other).json()["observation_status"]["recent"] == []
    row = db.get(CheckIn, identifier)
    row.created_at = datetime.now(timezone.utc) - timedelta(days=1)
    db.commit()
    assert client.get("/api/v1/home", headers=auth).json()["observation_status"]["today_completed"] is False
    db.delete(row)
    db.commit()
    assert client.get("/api/v1/home", headers=auth).json()["observation_status"]["recent"] == []
