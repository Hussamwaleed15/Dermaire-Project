from tests.test_account_deletion import deletion_context
from app.core.security import create_access_token


def test_product_roundtrip_and_validation(deletion_context):
    client, db, auth = deletion_context
    payload = {"name": "Barrier serum", "active_ingredients": ["Niacinamide"],
               "category": "serum", "frequency_per_week": 3, "time_of_use": "both",
               "tags": ["barrier"], "start_date": "2026-10-01T00:00:00"}
    created = client.post("/api/v1/products", json=payload, headers=auth)
    assert created.status_code == 201
    product = created.json()
    assert product["id"] and product["start_date"].startswith("2026-10-01")
    assert client.post("/api/v1/products", json=payload, headers=auth).status_code == 409
    path = "/api/v1/products/" + product["id"]
    patch = {"status": "archived", "in_routine": False, "tags": ["old"],
             "end_date": "2026-10-02T00:00:00", "notes": "Confirmed"}
    assert client.patch(path, json=patch, headers=auth).status_code == 200
    db.expire_all()
    fresh = client.get(path, headers=auth).json()
    assert fresh["tags"] == ["old"] and fresh["status"] == "archived"
    assert fresh["notes"] == "Confirmed" and fresh["in_routine"] is False
    assert client.patch(path, json={"name": "Private product"}, headers=auth).status_code == 409
    assert client.patch(path, json={"in_routine": None}, headers=auth).status_code == 422
    assert client.get(path, headers=auth).json()["name"] == "Barrier serum"
    assert client.delete(path, headers=auth).status_code == 204
    assert client.get(path, headers=auth).status_code == 404


def test_owner_isolation_and_empty_list(deletion_context):
    client, db, auth = deletion_context
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get("/api/v1/products", headers=other).json() == []
    for method in (client.get, client.delete):
        assert method("/api/v1/products/owned-product", headers=other).status_code == 404
    assert client.patch("/api/v1/products/owned-product", json={"name": "Changed"}, headers=other).status_code == 404
    assert client.get("/api/v1/products/owned-product", headers=auth).json()["name"] == "Private product"
    assert client.get("/api/v1/products").status_code == 401


def test_experiment_archive_and_delete_protection(deletion_context):
    client, db, auth = deletion_context
    path = "/api/v1/products/owned-product"
    assert client.patch(path, json={"in_experiment": True}, headers=auth).status_code == 200
    assert client.patch(path, json={"status": "archived"}, headers=auth).status_code == 409
    assert client.delete(path, headers=auth).status_code == 409
