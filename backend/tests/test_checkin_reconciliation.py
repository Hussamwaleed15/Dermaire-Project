import json
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
from app.core.security import create_access_token
from app.models import CheckIn
from app.services.azure_blob import azure_blob_service
from tests.test_account_deletion import deletion_context

KEY = "receipt-readback-0001"
URL = "/api/v1/checkins"

def test_committed_lost_reply_exact_record_and_expired_readback(deletion_context):
    client, db, auth = deletion_context
    # Deliberately ignore POST body: recover by attempt after a lost acknowledgement.
    response = client.post(URL, headers={**auth,"Idempotency-Key":KEY},
        data={"report":json.dumps({"overall_change":"same", "safety":None})})
    assert response.status_code == 201
    db.expire_all()
    attempt = client.get(URL+"/attempts/"+KEY, headers=auth).json()
    assert attempt["status"] == "committed"
    identifier = attempt["resource_id"]
    saved = client.get(URL+"/"+identifier, headers=auth)
    assert saved.status_code == 200
    assert saved.json()["receipt"] == attempt["result"]["receipt"]
    assert saved.json()["observation"]["user_reported"]["safety"] is None
    assert saved.json()["hydration_score"] is None
    assert "payload_hash" not in saved.text
    row = db.get(CheckIn, identifier)
    row.created_at = datetime.now(timezone.utc)-timedelta(days=31)
    db.commit()
    expired = client.get(URL+"/attempts/"+KEY, headers=auth).json()
    assert expired["status"] == "expired" and expired["result"] is None
    resource = client.get(URL+"/"+identifier, headers=auth).json()
    assert resource["receipt"]["status"] == "expired"
    assert resource["id"] == identifier

def test_unknown_has_no_success_fields_and_corrupt_evidence_is_unknown(deletion_context):
    client, db, auth = deletion_context
    unknown = client.get(URL+"/attempts/"+KEY, headers=auth).json()
    assert unknown["status"] == "unknown"
    assert all(unknown[field] is None for field in ("resource_id","committed_at","expires_at","result"))
    response = client.post(URL, headers={**auth,"Idempotency-Key":KEY}, data={"report":json.dumps({"overall_change":"same"})})
    row = db.get(CheckIn, response.json()["id"])
    row.observation = {**row.observation, "attempt":{"schema_version":99,"payload_hash":"invalid"}}
    db.commit()
    assert client.get(URL+"/attempts/"+KEY, headers=auth).json()["status"] == "unknown"
    assert client.get(URL+"/"+row.id, headers=auth).json()["receipt"] is None

def test_readback_is_owned_authenticated_and_erased(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    response = client.post(URL, headers={**auth,"Idempotency-Key":KEY}, data={"report":json.dumps({"overall_change":"same"})})
    identifier = response.json()["id"]
    path = URL+"/"+identifier
    other = {"Authorization":"Bearer "+create_access_token("delete-doctor","doctor",hashed_password="unused")}
    assert client.get(path).status_code == 401
    assert client.get(path, headers={"Authorization":"Bearer invalid"}).status_code == 401
    assert client.get(path, headers=other).status_code == 404
    assert client.get(URL+"/attempts/"+KEY, headers=other).json()["status"] == "unknown"
    assert client.get(URL+"/missing", headers=auth).status_code == 404
    monkeypatch.setattr(azure_blob_service,"delete_image",Mock())
    monkeypatch.setattr(azure_blob_service,"delete_owned_images",Mock())
    assert client.delete("/api/v1/users/me",headers=auth).status_code == 204
    assert client.get(path,headers=auth).status_code == 401
    assert client.get(URL+"/attempts/"+KEY,headers=auth).status_code == 401
