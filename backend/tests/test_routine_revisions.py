from datetime import date
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.orm.exc import StaleDataError
from app.core.database import Base
from app.models import User, Product, RoutineEntry
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create, report
from tests.test_experiment_engine_v2 import context, draft
from tests.test_postgres_gate import pg_engine


def test_routine_opt_in_history_and_preconditions(deletion_context):
    client, db, auth = deletion_context
    first = create(client, auth)
    assert first.headers["etag"] == '"1"'
    row = first.json()
    path = "/api/v1/routine/entries/"+row["id"]
    assert report(client, auth, row).status_code == 201
    edited = client.patch(path, headers={**auth,"If-Match":'"1"'}, json={"instructions":"Changed"})
    assert edited.status_code == 200
    current = edited.json()
    assert current["revision"] > 1 and current["revision_protected"]
    assert edited.headers["etag"] == f'"{current["revision"]}"'
    assert client.get(path,headers=auth).headers["etag"] == edited.headers["etag"]
    assert client.patch(path,headers=auth,json={"instructions":"old"}).status_code == 428
    assert client.delete(path,headers=auth).status_code == 428
    assert client.patch(path,headers={**auth,"If-Match":'"1"'},json={}).status_code == 412
    assert client.delete(path,headers={**auth,"If-Match":'"1"'}).status_code == 412
    logs = client.get("/api/v1/routine/adherence",headers=auth).json()
    assert logs[0]["configuration_snapshot"]["revision"] == 1
    assert logs[0]["configuration_snapshot"]["instructions"] == row["instructions"]
    stopped = client.delete(path,headers={**auth,"If-Match":edited.headers["etag"]})
    assert stopped.status_code == 204
    assert client.get(path,headers=auth).json()["active"] is False
    assert client.patch(path,headers={**auth,"If-Match":stopped.headers["etag"]},json={}).status_code == 409
    assert client.get(path).status_code == 401


@pytest.mark.parametrize("value", ['1','*','W/"1"','"0"','"01"','"2147483648"','"1", "1"'])
def test_routine_malformed_headers(deletion_context,value):
    client,db,auth=deletion_context
    row=create(client,auth).json()
    path="/api/v1/routine/entries/"+row["id"]
    assert client.patch(path,headers={**auth,"If-Match":value},json={}).status_code == 422
    assert client.get(path,headers=auth).json()["revision"] == 1


def test_duplicate_and_foreign_preconditions(deletion_context):
    from app.core.security import create_access_token
    client,db,auth=deletion_context
    row=create(client,auth).json(); path="/api/v1/routine/entries/"+row["id"]
    assert client.patch(path,headers=[*auth.items(),("If-Match",'"1"'),("If-Match",'"1"')],json={}).status_code == 422
    other={"Authorization":"Bearer "+create_access_token("delete-doctor","doctor",hashed_password="unused")}
    assert client.get(path,headers=other).status_code == 404
    assert client.patch(path,headers=other,json={}).status_code == 404
    assert client.delete(path,headers=other).status_code == 404


def test_activation_requires_protected_routine_revision(context):
    client,db,auth,payload=context
    path="/api/v1/routine/entries/"+payload["routine_entry_id"]
    response=client.patch(path,headers={**auth,"If-Match":'"1"'},json={})
    assert response.status_code == 200
    identifier=draft(context,intervention={"type":"change_schedule","schedule":"PM"}).json()["id"]
    activation=f"/api/v1/experiments/{identifier}/activate"
    assert client.post(activation,headers=auth).status_code == 428
    assert client.post(activation,headers={**auth,"Routine-If-Match":'"1"'}).status_code == 412
    assert client.post(activation,headers={**auth,"Routine-If-Match":response.headers["etag"]}).status_code == 200
    assert client.get(path,headers=auth).json()["schedule"] == "PM"


def test_protected_routine_cannot_be_bypassed_by_product_archive(deletion_context):
    client,db,auth=deletion_context
    row=create(client,auth).json();path="/api/v1/routine/entries/"+row["id"]
    changed=client.patch(path,headers={**auth,"If-Match":'"1"'},json={"instructions":"protected"})
    assert client.patch("/api/v1/products/owned-product",headers=auth,json={"status":"archived"}).status_code == 409
    assert client.get(path,headers=auth).json()["active"]
    assert client.get("/api/v1/products/owned-product",headers=auth).json()["status"] == "active"
    assert client.delete(path,headers={**auth,"If-Match":changed.headers["etag"]}).status_code == 204
    assert client.patch("/api/v1/products/owned-product",headers=auth,json={"status":"archived"}).status_code == 200


def test_routine_failed_commit_rolls_back_reserved_revision(deletion_context,monkeypatch):
    from unittest.mock import Mock
    client,db,auth=deletion_context
    row=create(client,auth).json();path="/api/v1/routine/entries/"+row["id"]
    monkeypatch.setattr(db,"commit",Mock(side_effect=RuntimeError("synthetic failure")))
    assert client.patch(path,headers={**auth,"If-Match":'"1"'},json={"instructions":"discard"}).status_code == 503
    db.expire_all()
    saved=client.get(path,headers=auth).json()
    assert saved["revision"] == 1 and not saved["revision_protected"] and saved["instructions"] == row["instructions"]


def race(engine, kind):
    Base.metadata.create_all(engine)
    factory=sessionmaker(bind=engine)
    with factory() as db:
        db.add(User(id="owner",email="owner@synthetic.test",full_name="Synthetic",hashed_password="test"));db.commit()
        db.add(Product(id="product",user_id="owner",name="Synthetic"));db.commit()
        db.add(RoutineEntry(id="entry",user_id="owner",product_id="product",schedule="AM",frequency="daily",start_date=__import__("app.services.routine",fromlist=["today"]).today()));db.commit()
    barrier=Barrier(2)
    def mutate(index):
        with factory() as db:
            row=db.get(RoutineEntry,"entry");barrier.wait(timeout=5)
            row.revision_protected=True
            if kind == "delete_update" and index:
                from app.services.routine import deactivate
                deactivate(row)
            else:
                setattr(row,"am_order" if kind=="different_fields" and index else "instructions",index if kind=="different_fields" and index else str(index))
            try:
                db.commit();return 200
            except StaleDataError:
                db.rollback();return 412
    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(mutate,range(2))) == [200,412]
    with factory() as db:
        assert db.get(RoutineEntry,"entry").revision == 2


@pytest.mark.parametrize("kind",["same_field","different_fields","delete_update"])
def test_routine_sqlite_cas(tmp_path,kind):
    engine=create_engine("sqlite:///"+(tmp_path/"routine.db").as_posix(),connect_args={"check_same_thread":False,"timeout":10})
    try: race(engine,kind)
    finally: engine.dispose()


@pytest.mark.parametrize("kind",["same_field","different_fields","delete_update"])
def test_routine_pg_cas(pg_engine,kind):
    race(pg_engine,kind)


def migrate(engine, monkeypatch):
    from pathlib import Path
    from sqlalchemy import text
    from alembic import command
    from alembic.config import Config
    from app.core.config import settings
    monkeypatch.setattr(settings,"DATABASE_URL",engine.url.render_as_string(hide_password=False))
    cfg=Config(str(Path(__file__).parents[1]/"alembic.ini"))
    command.upgrade(cfg,"20261014_01")
    with engine.begin() as c:
        c.execute(text("INSERT INTO users(id,email,hashed_password,full_name,role,reset_token_attempts) VALUES ('owner','owner@synthetic.test','test','Synthetic','patient',0)"))
        c.execute(text("INSERT INTO products(id,user_id,name,category) VALUES ('product','owner','Preserved','treatment')"))
        c.execute(text("INSERT INTO routine_entries(id,user_id,product_id,schedule,frequency,start_date,active,am_order,pm_order,source,created_at,updated_at,instructions) VALUES ('entry','owner','product','AM','daily','2026-01-01',true,0,0,'user_configured','2026-01-01','2026-01-01','Preserved')"))
    command.upgrade(cfg,"20261014_02")
    with engine.connect() as c:
        assert tuple(c.execute(text("SELECT instructions,revision,revision_protected FROM routine_entries")).one()) == ("Preserved",1,False)
    command.downgrade(cfg,"20261014_01");command.upgrade(cfg,"20261014_02")
    with engine.begin() as c:
        c.execute(text("UPDATE routine_entries SET revision_protected=true"))
    with pytest.raises(RuntimeError,match="protected routine"):
        command.downgrade(cfg,"20261014_01")
    with engine.connect() as c:
        assert c.execute(text("SELECT instructions,revision_protected FROM routine_entries")).one() == ("Preserved",True)


def test_routine_seeded_sqlite_migration(tmp_path,monkeypatch):
    engine=create_engine("sqlite:///"+(tmp_path/"migration.db").as_posix())
    try:migrate(engine,monkeypatch)
    finally:engine.dispose()


def test_routine_seeded_pg_migration(pg_engine,monkeypatch):
    migrate(pg_engine,monkeypatch)
