from copy import deepcopy
from pathlib import Path
from unittest.mock import Mock
import sqlite3
import pytest
from app.models import User, ProductIntelligence
from app.core.security import create_access_token
from app.services.azure_blob import azure_blob_service
from app.services.product_intelligence import ingredient_key
from tests.test_account_deletion import deletion_context
from tests.test_experiment_engine_v2 import context as experiment_context, active

READ = "/api/v1/products/owned-product/intelligence"
WRITE = "/api/v1/admin/product-intelligence/owned-product"
ROUTINE = "/api/v1/routine/intelligence"


@pytest.fixture
def intelligence_context(deletion_context):
    client, db, auth = deletion_context
    db.add(User(id="intelligence-admin", email="admin@example.com", full_name="Admin", role="admin", hashed_password="unused"))
    db.commit()
    admin = {"Authorization": "Bearer " + create_access_token("intelligence-admin", "admin", hashed_password="unused")}
    return client, db, auth, admin


def document(names=("Niacinamide",), complete=True):
    return {"sources": [{"id": "label", "type": "manufacturer_label", "reference": "Reviewed label, variant A",
                         "verification": "verified", "confidence": "high", "last_verified_at": "2026-01-01T00:00:00Z"}],
            "canonical_name": {"value": "Known serum", "source_id": "label"},
            "region": {"value": "EG", "source_id": "label"},
            "ingredients": {"source_id": "label", "completeness": "complete" if complete else "partial",
                            "items": [{"name": name, "source_id": "label", "position": n + 1} for n, name in enumerate(names)]}}


def add_routine(client, auth, product_id):
    response = client.post("/api/v1/routine/entries", headers=auth,
                           json={"product_id": product_id, "schedule": "PM", "frequency": "daily", "start_date": "2026-01-01"})
    assert response.status_code == 201, response.text
    return response.json()["id"]


def second_product(client, auth, names):
    response = client.post("/api/v1/products", headers=auth, json={"name": "Second product", "active_ingredients": names})
    assert response.status_code == 201
    return response.json()["id"]


def test_unknown_and_user_reports_are_not_verified(intelligence_context):
    client, db, auth, _ = intelligence_context
    result = client.get(READ, headers=auth).json()
    assert result["state"] == "unknown" and result["data_completeness"] == "incomplete"
    assert result["ingredients"] == [] and result["warnings"] == []
    assert "complete_ingredient_list" in result["unknowns"]
    assert db.query(ProductIntelligence).count() == 0
    assert client.patch("/api/v1/products/owned-product", headers=auth, json={"active_ingredients": ["Nicotinamide", "Retinol 2%"]}).status_code == 200
    result = client.get(READ, headers=auth).json()
    assert len(result["actives"]) == 1  # No concentration or identity parsed from free text.
    assert result["actives"][0]["normalized_key"] == "niacinamide"
    assert result["actives"][0]["concentration_state"] == "unknown"
    assert result["facts"]["sources"][0]["verification"] == "unverified"


def test_structured_readback_and_fact_provenance(intelligence_context):
    client, db, auth, admin = intelligence_context
    payload = document(("Aqua", "Nicotinamide", "Retinaldehyde"))
    payload["sources"].append({"id": "strength", "type": "curated_internal", "reference": "Reviewed manufacturer strength statement", "verification": "verified", "confidence": "medium", "last_verified_at": "2026-01-01T00:00:00Z"})
    payload["ingredients"]["items"][1]["strength"] = {"value": "5% w/w", "source_id": "strength"}
    payload["formulation_variant"] = {"value": "Label version A", "source_id": "label"}
    assert client.put(WRITE, headers=admin, json=payload).status_code == 200
    result = client.get(READ, headers=auth).json()
    assert [i["position"] for i in result["ingredients"]] == [1, 2, 3]
    assert [i["normalized_key"] for i in result["actives"]] == ["niacinamide", "retinal"]
    assert [i["concentration_state"] for i in result["actives"]] == ["known", "unknown"]
    assert result["actives"][0]["strength"] == payload["ingredients"]["items"][1]["strength"]
    assert result["facts"]["sources"][1]["confidence"] == "medium"
    assert result["facts"]["region"] == payload["region"]
    assert result["updated_at"]
    assert client.get("/api/v1/products/owned-product", headers=auth).json()["name"] == "Private product"
    assert db.query(ProductIntelligence).count() == 1
    assert client.put(WRITE, headers=admin, json=document()).status_code == 200
    assert db.query(ProductIntelligence).count() == 1


@pytest.mark.parametrize("first,second,key", [
    ("Nicotinamide", "Niacinamide", "duplicate_active"),
    ("Retinol", "Adapalene", "duplicate_retinoid_class"),
    ("Glycolic acid", "Lactic acid", "duplicate_exfoliant_class"),
    ("Retinol", "Salicylic acid", "retinoid_exfoliant_caution"),
])
def test_routine_rules_positive_evidence(intelligence_context, first, second, key):
    client, db, auth, admin = intelligence_context
    client.put(WRITE, headers=admin, json=document((first,)))
    pid = second_product(client, auth, [second])
    add_routine(client, auth, "owned-product")
    add_routine(client, auth, pid)
    result = client.get(ROUTINE, headers=auth).json()
    warnings = [w for w in result["warnings"] if w["key"] == key]
    assert len(warnings) == 1
    warning = warnings[0]
    assert warning["severity"] in ("info", "caution")
    assert warning["confidence"] == "low" and warning["data_completeness"] == "incomplete"
    assert len(warning["evidence"]) == 2
    assert {e["product_id"] for e in warning["evidence"]} == {pid, "owned-product"}
    assert warning["limitations"]
    if key == "retinoid_exfoliant_caution":
        assert warning["rule_source"].startswith("https://www.aad.org/")
        assert "may" in warning["explanation"]


def test_unknown_does_not_reassure_or_infer_sensitivity(intelligence_context):
    client, db, auth, admin = intelligence_context
    add_routine(client, auth, "owned-product")
    user = db.get(User, "delete-patient")
    user.skin_type = "sensitive"
    user.profile_context = {"medications_treatments": ["Retinol"], "sensitivities_allergies": None}
    db.commit()
    result = client.get(ROUTINE, headers=auth).json()
    assert result["warnings"] == [] and result["data_completeness"] == "incomplete"
    assert "is_safe" not in str(result)
    client.put(WRITE, headers=admin, json=document(("Fragrance",)))
    assert client.get(ROUTINE, headers=auth).json()["warnings"] == []


def test_explicit_disclosure_only_exact_alias_match(intelligence_context):
    client, db, auth, admin = intelligence_context
    client.put(WRITE, headers=admin, json=document(("Parfum", "Niacinamide")))
    add_routine(client, auth, "owned-product")
    user = db.get(User, "delete-patient")
    user.profile_context = {"sensitivities_allergies": ["عطر", "I think niacinamide bothers me"]}
    db.commit()
    result = client.get(ROUTINE, headers=auth).json()
    assert len(result["warnings"]) == 1 and result["warnings"][0]["key"] == "disclosed_sensitivity_match"
    assert result["warnings"][0]["disclosure"] == "عطر"
    assert client.get(READ, headers=auth).json()["warnings"][0]["key"] == "disclosed_sensitivity_match"
    user.profile_context = None; db.commit()
    assert client.get(ROUTINE, headers=auth).json()["warnings"] == []


def test_current_owner_entries_only_and_deactivation(intelligence_context):
    client, db, auth, admin = intelligence_context
    client.put(WRITE, headers=admin, json=document())
    pid = second_product(client, auth, ["Niacinamide"])
    assert client.get(ROUTINE, headers=auth).json()["products"] == []
    add_routine(client, auth, "owned-product")
    second = add_routine(client, auth, pid)
    assert len(client.get(ROUTINE, headers=auth).json()["warnings"]) == 1
    assert client.delete("/api/v1/routine/entries/" + second, headers=auth).status_code == 204
    result = client.get(ROUTINE, headers=auth).json()
    assert len(result["products"]) == 1 and result["warnings"] == []
    assert client.patch("/api/v1/products/owned-product", headers=auth, json={"status": "inactive"}).status_code == 200
    assert client.get(ROUTINE, headers=auth).json()["products"] == []
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get(ROUTINE, headers=other).json()["products"] == []


def test_authorization_foreign_refs_and_retired_fallback(intelligence_context):
    client, db, auth, admin = intelligence_context
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused")}
    assert client.get(READ, headers=other).status_code == 404
    assert client.get(READ).status_code == 401
    assert client.get(ROUTINE).status_code == 401
    assert client.put(WRITE, headers=auth, json=document()).status_code == 403
    assert client.put(WRITE, headers=other, json=document()).status_code == 403
    assert client.put(WRITE, json=document()).status_code == 401
    assert client.put(WRITE.replace("owned-product", "absent"), headers=admin, json=document()).status_code == 404
    assert client.get(READ.replace("owned-product", "absent"), headers=auth).status_code == 404
    assert client.post("/api/v1/products/check-interactions", headers=auth, json={"ingredients": ["Retinol", "AHA"]}).status_code == 410


@pytest.mark.parametrize("mutation", [
    lambda p: p["ingredients"]["items"][0].update(source_id="missing"),
    lambda p: p["ingredients"]["items"][0].update(position=0),
    lambda p: p["ingredients"]["items"].append({"name": "Nicotinamide", "source_id": "label"}),
    lambda p: p["sources"][0].update(type="user_reported"),
    lambda p: p["sources"][0].update(last_verified_at=None),
    lambda p: p["sources"][0].update(last_verified_at="2099-01-01T00:00:00Z"),
    lambda p: p["sources"][0].update(last_verified_at="2026-01-01T00:00:00"),
    lambda p: p.update(diagnosis="healthy"),
    lambda p: p["ingredients"]["items"][0].update(strength={"value": "", "source_id": "label"}),
    lambda p: p["sources"].append(deepcopy(p["sources"][0])),
])
def test_invalid_documents_leave_no_partial_write(intelligence_context, mutation):
    client, db, auth, admin = intelligence_context
    original = document()
    assert client.put(WRITE, headers=admin, json=original).status_code == 200
    before = client.get(READ, headers=auth).json()
    invalid = document(); mutation(invalid)
    assert client.put(WRITE, headers=admin, json=invalid).status_code == 422
    assert client.get(READ, headers=auth).json() == before
    assert db.query(ProductIntelligence).count() == 1


def test_write_failure_rolls_back(intelligence_context, monkeypatch):
    client, db, auth, admin = intelligence_context
    monkeypatch.setattr(db, "commit", Mock(side_effect=RuntimeError("unavailable")))
    assert client.put(WRITE, headers=admin, json=document()).status_code == 503
    assert db.query(ProductIntelligence).count() == 0


def test_account_deletion_removes_all_evidence_and_invalidates_session(intelligence_context, monkeypatch):
    client, db, auth, admin = intelligence_context
    client.put(WRITE, headers=admin, json=document())
    monkeypatch.setattr(azure_blob_service, "delete_image", Mock())
    monkeypatch.setattr(azure_blob_service, "delete_owned_images", Mock())
    assert client.delete("/api/v1/users/me", headers=auth).status_code == 204
    assert db.query(ProductIntelligence).count() == 0
    assert client.get(READ, headers=auth).status_code == 401
    assert client.get(ROUTINE, headers=auth).status_code == 401


def test_product_delete_cascades_evidence(intelligence_context):
    client, db, auth, admin = intelligence_context
    pid = second_product(client, auth, [])
    assert client.put(WRITE.replace("owned-product", pid), headers=admin, json=document()).status_code == 200
    assert client.delete("/api/v1/products/" + pid, headers=auth).status_code == 204
    assert db.query(ProductIntelligence).count() == 0


def test_aliases_are_exact_and_molecules_not_collapsed():
    assert ingredient_key("  NICOTINAMIDE ") == "niacinamide"
    assert ingredient_key("Retinaldehyde") == "retinal"
    assert ingredient_key("Tretinoin") != ingredient_key("Retinol")
    assert ingredient_key("not retinol") != "retinol"
    assert ingredient_key("Vitamin C") != "ascorbic_acid"


def test_stop_experiment_excludes_product_but_preserves_fact_read(experiment_context):
    client, db, auth, _ = experiment_context
    assert len(client.get(ROUTINE, headers=auth).json()["products"]) == 1
    active(experiment_context, intervention={"type": "stop_entry"})
    assert client.get(ROUTINE, headers=auth).json()["products"] == []
    assert client.get(READ, headers=auth).status_code == 200


def test_logged_out_session_cannot_read_or_ingest(intelligence_context):
    client, db, auth, admin = intelligence_context
    assert client.post("/api/v1/auth/logout", headers=auth).status_code == 204
    assert client.get(READ, headers=auth).status_code == 401
    assert client.get(ROUTINE, headers=auth).status_code == 401
    assert client.post("/api/v1/auth/logout", headers=admin).status_code == 204
    assert client.put(WRITE, headers=admin, json=document()).status_code == 401


def test_partial_positive_facts_and_same_product_caution(intelligence_context):
    client, db, auth, admin = intelligence_context
    payload = document(("Retinol", "Glycolic acid"), complete=False)
    payload["sources"][0].update(type="user_reported", verification="unverified", confidence="low", last_verified_at=None)
    assert client.put(WRITE, headers=admin, json=payload).status_code == 200
    result = client.get(READ, headers=auth).json()
    assert result["data_completeness"] == "incomplete"
    assert result["warnings"][0]["key"] == "retinoid_exfoliant_caution"
    assert result["warnings"][0]["confidence"] == "low"


def test_foreign_product_join_is_excluded_even_with_inconsistent_entry(intelligence_context):
    from app.models import Product, RoutineEntry
    from datetime import date
    client, db, auth, admin = intelligence_context
    db.add(Product(id="foreign-product", user_id="delete-doctor", name="Foreign", active_ingredients=["Retinol"]))
    db.commit()
    db.add(RoutineEntry(user_id="delete-patient", product_id="foreign-product", schedule="PM", frequency="daily", start_date=date(2026, 1, 1)))
    db.commit()
    assert client.get(ROUTINE, headers=auth).json()["products"] == []


def test_sqlite_manual_migration_constraints_and_cascade():
    sql = (Path(__file__).parents[2] / "docs/migrations/product-intelligence-v1-sqlite.sql").read_text()
    db = sqlite3.connect(":memory:")
    db.executescript("CREATE TABLE users(id VARCHAR(36) PRIMARY KEY); CREATE TABLE products(id VARCHAR(36) PRIMARY KEY); INSERT INTO users VALUES ('u'); INSERT INTO products VALUES ('p');")
    db.executescript(sql)
    db.execute("INSERT INTO product_intelligence VALUES ('i','u','p','{}','2026-01-01')")
    with pytest.raises(sqlite3.IntegrityError):
        db.execute("INSERT INTO product_intelligence VALUES ('j','u','p','{}','2026-01-01')")
    db.execute("DELETE FROM products WHERE id='p'")
    assert db.execute("SELECT COUNT(*) FROM product_intelligence").fetchone()[0] == 0
    db.close()
