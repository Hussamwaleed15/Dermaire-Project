from unittest.mock import Mock
from types import SimpleNamespace

import pytest
from app.models import User, Product, ProductIntelligence
from app.services.deletion_journal import DeletionJournal
from tests.test_deletion_journal import Container
from tests.test_account_deletion import deletion_context


def fixture_product(db, identifier="erasable"):
    db.add(Product(id=identifier, user_id="delete-patient", name=identifier))
    db.commit()
    db.add(ProductIntelligence(user_id="delete-patient", product_id=identifier,
                               document={"private": "synthetic evidence"}))
    db.commit()


def test_product_intent_failure_preserves_product_and_intelligence(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    fixture_product(db)
    journal = Mock()
    journal.record_product.side_effect = RuntimeError("private failure text")
    monkeypatch.setattr("app.api.v1.products.deletion_journal", journal)
    response = client.delete("/api/v1/products/erasable", headers=auth)
    assert response.status_code == 503
    assert "private failure text" not in response.text
    assert db.get(Product, "erasable") is not None
    assert db.query(ProductIntelligence).filter_by(product_id="erasable").count() == 1


def test_product_delete_persists_before_db_removal(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    fixture_product(db)
    journal = DeletionJournal(Container(), "j" * 32, True)
    original = journal.record_product
    def record(owner, product):
        assert db.get(Product, product) is not None
        assert db.query(ProductIntelligence).filter_by(product_id=product).count() == 1
        return original(owner, product)
    monkeypatch.setattr(journal, "record_product", record)
    monkeypatch.setattr("app.api.v1.products.deletion_journal", journal)
    assert client.delete("/api/v1/products/erasable", headers=auth).status_code == 204
    assert len(journal.inventory()) == 1
    assert db.get(Product, "erasable") is None
    assert db.query(ProductIntelligence).filter_by(product_id="erasable").count() == 0


def test_product_replay_preserves_account_siblings_photos_and_source(deletion_context):
    _, db, _ = deletion_context
    fixture_product(db)
    fixture_product(db, "sibling")
    journal = DeletionJournal(Container(), "j" * 32, True)
    name = journal.record_product("delete-patient", "erasable")
    assert name.startswith("v3/")
    assert journal.record_product("delete-patient", "erasable") == name
    snapshot = dict(journal.container.data)
    assert b"delete-patient" not in snapshot[name] and b"erasable" not in snapshot[name]
    storage = Mock(is_live=True)
    storage.container_client.list_blobs.return_value = [SimpleNamespace(name="skin_photos/delete-patient/a.png")]
    account_delete = Mock()
    result = journal.replay(db, storage, account_delete)
    assert result["restored_products_removed"] == 1
    assert db.get(User, "delete-patient") is not None
    assert db.get(Product, "sibling") is not None
    assert db.get(Product, "owned-product") is not None
    assert db.query(ProductIntelligence).filter_by(product_id="sibling").count() == 1
    account_delete.assert_not_called()
    storage.delete_image.assert_not_called()
    assert journal.replay(db, storage, account_delete)["restored_products_removed"] == 0
    assert journal.container.data == snapshot


def test_product_replay_bad_owner_and_dependencies_fail_closed(deletion_context):
    _, db, _ = deletion_context
    fixture_product(db)
    journal = DeletionJournal(Container(), "j" * 32, True)
    journal.record_product("delete-doctor", "erasable")
    storage = Mock(is_live=True)
    storage.container_client.list_blobs.return_value = []
    assert journal.replay(db, storage, Mock())["restored_products_removed"] == 0
    journal.record_product("delete-patient", "owned-product")
    with pytest.raises(RuntimeError, match="dependencies"):
        journal.replay(db, storage, Mock())
    assert db.get(Product, "erasable") is not None
    assert db.get(Product, "owned-product") is not None
