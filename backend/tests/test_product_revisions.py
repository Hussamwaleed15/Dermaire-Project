from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from unittest.mock import Mock
from pathlib import Path
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine, text, MetaData
from sqlalchemy.orm import sessionmaker
from alembic import command
from alembic.config import Config
from app.core.database import Base
from app.core.config import settings
from app.core.security import create_access_token
from app.models import User, Product, AuditLog
from app.schemas import ProductUpdate
from app.api.v1.products import update_product, delete_product
from app.services import product_revisions
from app.services.deletion_journal import deletion_journal
from tests.test_account_deletion import deletion_context

URL = "/api/v1/products/owned-product"

def test_opt_in_stale_no_bypass_and_readback(deletion_context):
    client, db, auth = deletion_context
    before = client.get(URL, headers=auth)
    assert before.headers["etag"] == '"1"'
    assert before.json()["revision_protected"] is False
    first = client.patch(URL, headers={**auth, "If-Match": '"1"'}, json={"notes": "first"})
    assert first.status_code == 200
    assert first.json()["revision"] == 2 and first.json()["revision_protected"] is True
    assert first.headers["etag"] == '"2"'
    assert client.patch(URL, headers={**auth, "If-Match": '"1"'}, json={"notes": "stale"}).status_code == 412
    assert client.patch(URL, headers=auth, json={"notes": "legacy stale"}).status_code == 428
    assert client.delete(URL, headers=auth).status_code == 428
    assert client.delete(URL, headers={**auth, "If-Match": '"1"'}).status_code == 412
    db.expire_all()
    current = client.get(URL, headers=auth).json()
    assert current["notes"] == "first" and current["revision"] == 2
    assert client.patch(URL, headers={**auth, "If-Match": '"2"'}, json={"notes": "next"}).json()["revision"] == 3
    other = {"Authorization": "Bearer " + create_access_token("delete-doctor", "doctor", hashed_password="unused"), "If-Match": '"3"'}
    assert client.patch(URL, headers=other, json={"notes": "foreign"}).status_code == 404
    assert client.delete(URL, headers=other).status_code == 404

@pytest.mark.parametrize("etag", ['W/"1"', '*', '1', '"0"', '"01"', '"2147483648"'])
def test_invalid_precondition_never_mutates(deletion_context, etag):
    client, db, auth = deletion_context
    assert client.patch(URL, headers={**auth, "If-Match": etag}, json={"notes": "bad"}).status_code == 422
    assert client.get(URL, headers=auth).json()["revision"] == 1


@pytest.mark.parametrize("method",["patch","delete"])
def test_duplicate_product_revision_headers_rejected(deletion_context,method):
    client,db,auth=deletion_context
    headers=[*auth.items(),("If-Match",'"1"'),("If-Match",'"1"')]
    result=client.patch(URL,headers=headers,json={"notes":"Denied"}) if method=="patch" else client.delete(URL,headers=headers)
    assert result.status_code == 422
    assert client.get(URL,headers=auth).json()["revision"] == 1

def test_legacy_keeps_behavior_and_all_orm_writers_increment(deletion_context):
    client, db, auth = deletion_context
    assert client.patch(URL, headers=auth, json={"notes": "legacy"}).json()["revision"] == 2
    row = db.get(Product, "owned-product")
    row.in_experiment = True
    db.commit()
    current = client.get(URL, headers=auth).json()
    assert current["revision"] == 3 and current["revision_protected"] is False
    assert client.patch(URL, headers={**auth, "If-Match": '"2"'}, json={"notes": "stale"}).status_code == 412

def test_audit_and_revision_rollback_together(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    count = db.query(AuditLog).filter_by(action="PRODUCT_UPDATED").count()
    monkeypatch.setattr(db, "commit", Mock(side_effect=RuntimeError("synthetic failure")))
    assert client.patch(URL, headers={**auth, "If-Match": '"1"'}, json={"notes": "rollback"}).status_code == 503
    db.expire_all()
    assert db.get(Product, "owned-product").revision == 1
    assert db.get(Product, "owned-product").revision_protected is False
    assert db.query(AuditLog).filter_by(action="PRODUCT_UPDATED").count() == count

@pytest.mark.parametrize("race", ["same_field", "different_fields", "delete_update"])
def test_real_parallel_cas(tmp_path, monkeypatch, race):
    engine = create_engine("sqlite:///"+(tmp_path/"products.db").as_posix(), connect_args={"check_same_thread": False, "timeout": 10})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autoflush=False)
    with factory() as db:
        db.add(User(id="owner", email="owner@synthetic.test", full_name="Synthetic", hashed_password="unused"))
        db.commit()
        db.add(Product(id="product", user_id="owner", name="Synthetic product"))
        db.commit()
    barrier = Barrier(2)
    original = product_revisions.enforce
    def simultaneous(row, etag):
        original(row, etag)
        barrier.wait(timeout=10)
    monkeypatch.setattr(product_revisions, "enforce", simultaneous)
    journal = Mock()
    monkeypatch.setattr(deletion_journal, "record_product", journal)
    def mutate(index):
        with factory() as db:
            try:
                user = db.get(User, "owner")
                if race == "delete_update" and index:
                    delete_product("product", if_match='"1"', current_user=user, db=db)
                    return 204
                payload = {"notes": "A" if index else "B"}
                if race == "different_fields" and index:
                    payload = {"brand": "A"}
                update_product("product", ProductUpdate(**payload), if_match='"1"', current_user=user, db=db)
                return 200
            except HTTPException as exc:
                return exc.status_code
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(mutate, index) for index in range(2)]
        codes = [future.result(timeout=20) for future in futures]
    assert codes.count(412) == 1
    assert len([code for code in codes if code in (200,204)]) == 1
    with factory() as db:
        row = db.get(Product, "product")
        if 204 in codes:
            assert row is None and journal.call_count == 1
        else:
            assert row.revision == 2 and row.revision_protected is True
            assert journal.call_count == 0
        assert db.query(AuditLog).count() == 1
    engine.dispose()

def test_isolated_migration_data_preservation_and_rollback_guard(tmp_path, monkeypatch):
    url = "sqlite:///"+(tmp_path/"migration.db").as_posix()
    monkeypatch.setattr(settings, "DATABASE_URL", url)
    config = Config(str(Path(__file__).parents[1]/"alembic.ini"))
    command.upgrade(config, "20261008_01")
    engine = create_engine(url)
    with engine.begin() as conn:
        conn.execute(text("INSERT INTO users(id,email,hashed_password,full_name,role,reset_token_attempts) VALUES ('owner','owner@synthetic.test','unused','Synthetic','patient',0)"))
        conn.execute(text("INSERT INTO products(id,user_id,name,category) VALUES ('product','owner','Preserve me','treatment')"))
    command.upgrade(config, "head")
    command.check(config)
    with engine.connect() as conn:
        row = conn.execute(text("SELECT name,revision,revision_protected FROM products")).one()
        assert row == ("Preserve me",1,0)
    command.downgrade(config, "20261008_01")
    command.upgrade(config, "head")
    with engine.begin() as conn:
        conn.execute(text("UPDATE products SET revision_protected=true WHERE id='product'"))
    with pytest.raises(RuntimeError, match="protected products"):
        command.downgrade(config, "20261008_01")
    with engine.connect() as conn:
        assert conn.execute(text("SELECT name,revision_protected FROM products")).one() == ("Preserve me",1)
    engine.dispose()
