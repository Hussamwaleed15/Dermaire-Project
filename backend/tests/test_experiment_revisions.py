from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from pathlib import Path
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.orm.exc import StaleDataError
from alembic import command
from alembic.config import Config
from app.core.database import Base
from app.core.config import settings
from app.models import User, Experiment, ExperimentEvaluation, RoutineEntry
from tests.test_account_deletion import deletion_context
from tests.test_experiment_engine_v2 import context, draft, collect
from tests.test_postgres_gate import pg_engine


def test_draft_activation_finish_preconditions_and_frozen_evidence(context,monkeypatch):
    client,db,auth,payload=context
    created=draft(context);assert created.headers["etag"] == '"1"'
    path="/api/v1/experiments/"+created.json()["id"]
    edit=client.patch(path,headers={**auth,"If-Match":'"1"'},json={"notes":"Protected"})
    assert edit.status_code == 200 and edit.json()["revision_protected"]
    assert client.patch(path,headers=auth,json={}).status_code == 428
    assert client.post(path+"/activate",headers=auth).status_code == 428
    assert client.delete(path,headers=auth).status_code == 428
    assert client.patch(path,headers={**auth,"If-Match":'"1"'},json={}).status_code == 412
    active=client.post(path+"/activate",headers={**auth,"If-Match":edit.headers["etag"]})
    assert active.status_code == 200
    row=active.json();assert row["revision"] > edit.json()["revision"]
    snapshot=row["definition_snapshot"]
    assert client.patch(path,headers={**auth,"If-Match":active.headers["etag"]},json={"notes":"immutable"}).status_code == 409
    collect(context,row,monkeypatch)
    assert client.post(path+"/evaluate",headers=auth).status_code == 428
    result=client.post(path+"/evaluate",headers={**auth,"If-Match":active.headers["etag"]})
    assert result.status_code == 201
    assert "experiment-etag" in result.headers
    assert client.post(path+"/evaluate",headers={**auth,"If-Match":active.headers["etag"]}).status_code == 412
    assert db.query(ExperimentEvaluation).filter_by(experiment_id=row["id"]).count() == 1
    saved=client.get(path,headers=auth)
    assert saved.headers["etag"] == result.headers["experiment-etag"]
    assert saved.json()["definition_snapshot"] == snapshot
    stop=client.post(path+"/finish",headers={**auth,"If-Match":saved.headers["etag"]},json={"status":"stopped"})
    assert stop.status_code == 200 and stop.json()["revision"] > saved.json()["revision"]
    assert client.get(path,headers=auth).json()["result"]["id"] == result.json()["id"]
    assert client.delete(path,headers={**auth,"If-Match":saved.headers["etag"]}).status_code == 412


@pytest.mark.parametrize("value",['*','1','W/"1"','"0"','"01"','"2147483648"','"1", "1"'])
def test_experiment_malformed_header(context,value):
    client,db,auth,_=context
    row=draft(context).json();path="/api/v1/experiments/"+row["id"]
    assert client.patch(path,headers={**auth,"If-Match":value},json={}).status_code == 422
    assert client.get(path,headers=auth).json()["revision"] == 1


def test_experiment_duplicate_foreign_legacy_and_cancel(context):
    from app.core.security import create_access_token
    client,db,auth,_=context
    row=draft(context).json();path="/api/v1/experiments/"+row["id"]
    assert client.patch(path,headers=[*auth.items(),("If-Match",'"1"'),("If-Match",'"1"')],json={}).status_code == 422
    other={"Authorization":"Bearer "+create_access_token("delete-doctor","doctor",hashed_password="unused")}
    for method in ("get","delete"):
        assert getattr(client,method)(path,headers=other).status_code == 404
    assert client.patch(path,headers=other,json={}).status_code == 404
    assert client.post(path+"/activate",headers=other).status_code == 404
    assert client.post(path+"/evaluate",headers=other).status_code == 404
    assert client.get(path).status_code == 401
    updated=client.patch(path,headers=auth,json={"notes":"Legacy"})
    assert updated.status_code == 200 and not updated.json()["revision_protected"]
    cancelled=client.delete(path,headers={**auth,"If-Match":updated.headers["etag"]})
    assert cancelled.status_code == 200 and cancelled.json()["status"] == "cancelled" and cancelled.json()["revision_protected"]


def test_experiment_slot_failure_rolls_back_all_revisions(context):
    client,db,auth,payload=context
    assert client.post("/api/v1/routine/entries",headers=auth,json={"product_id":"owned-product","schedule":"PM","frequency":"daily","start_date":payload["start_date"]}).status_code == 201
    row=draft(context,intervention={"type":"change_schedule","schedule":"BOTH"}).json()
    before=db.get(RoutineEntry,payload["routine_entry_id"]).revision
    assert client.post(f"/api/v1/experiments/{row['id']}/activate",headers={**auth,"If-Match":'"1"'}).status_code == 409
    db.expire_all()
    assert db.get(Experiment,row["id"]).revision == 1 and not db.get(Experiment,row["id"]).revision_protected
    assert db.get(RoutineEntry,payload["routine_entry_id"]).revision == before


def race(engine,kind):
    Base.metadata.create_all(engine);factory=sessionmaker(bind=engine)
    with factory() as db:
        db.add(User(id="owner",email="owner@synthetic.test",full_name="Synthetic",hashed_password="test"));db.commit()
        # Legacy nullable definition isolates mapper CAS from v2 business guards.
        db.add(Experiment(id="experiment",user_id="owner",status="draft"));db.commit()
    barrier=Barrier(2)
    def write(index):
        with factory() as db:
            row=db.get(Experiment,"experiment");barrier.wait(timeout=5)
            row.revision_protected=True
            if kind=="update_cancel" and index:row.status="cancelled"
            else:setattr(row,"goal" if kind=="different_fields" and index else "notes",str(index))
            try:db.commit();return 200
            except StaleDataError:db.rollback();return 412
    with ThreadPoolExecutor(2) as pool:assert sorted(pool.map(write,range(2))) == [200,412]
    with factory() as db:assert db.get(Experiment,"experiment").revision == 2


@pytest.mark.parametrize("kind",["same_field","different_fields","update_cancel"])
def test_experiment_sqlite_cas(tmp_path,kind):
    engine=create_engine("sqlite:///"+(tmp_path/"experiment.db").as_posix(),connect_args={"check_same_thread":False,"timeout":10})
    try:race(engine,kind)
    finally:engine.dispose()


@pytest.mark.parametrize("kind",["same_field","different_fields","update_cancel"])
def test_experiment_pg_cas(pg_engine,kind):race(pg_engine,kind)


def migrate(engine,monkeypatch):
    monkeypatch.setattr(settings,"DATABASE_URL",engine.url.render_as_string(hide_password=False))
    cfg=Config(str(Path(__file__).parents[1]/"alembic.ini"));command.upgrade(cfg,"20261014_02")
    with engine.begin() as c:
        c.execute(text("INSERT INTO users(id,email,hashed_password,full_name,role,reset_token_attempts) VALUES ('owner','owner@synthetic.test','test','Synthetic','patient',0)"))
        c.execute(text("INSERT INTO experiments(id,user_id,status,notes) VALUES ('experiment','owner','active','Preserved legacy')"))
    command.upgrade(cfg,"20261014_03")
    with engine.connect() as c:assert c.execute(text("SELECT notes,engine_version,revision,revision_protected FROM experiments")).one() == ("Preserved legacy",None,1,False)
    command.downgrade(cfg,"20261014_02");command.upgrade(cfg,"20261014_03")
    with engine.begin() as c:c.execute(text("UPDATE experiments SET revision_protected=true"))
    with pytest.raises(RuntimeError,match="protected experiments"):command.downgrade(cfg,"20261014_02")


def test_experiment_sqlite_migration(tmp_path,monkeypatch):
    engine=create_engine("sqlite:///"+(tmp_path/"migration.db").as_posix())
    try:migrate(engine,monkeypatch)
    finally:engine.dispose()


def test_experiment_pg_migration(pg_engine,monkeypatch):migrate(pg_engine,monkeypatch)
