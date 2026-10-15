import json
import os
from pathlib import Path
import pytest
from sqlalchemy import create_engine,text
from app.tools.rehearse_current_schema import run,validate_target
from tests.test_postgres_gate import pg_engine


def evidence(result,name):
    if os.environ.get("DERMAIRE_REHEARSAL_EVIDENCE_DIR"):
        target=Path(os.environ["DERMAIRE_REHEARSAL_EVIDENCE_DIR"])
        target.mkdir(parents=True,exist_ok=True)
        (target/name).write_text(json.dumps(result,indent=2),encoding="utf-8")


def test_current_schema_seeded_sqlite(tmp_path):
    engine=create_engine("sqlite:///"+(tmp_path/"dermaire_rehearsal_f5.db").as_posix())
    try:
        result=run(engine)
        assert result["revision"] == "20261015_06" and result["seeded_rows"] == 8
        assert result["data_preserved"] and result["checkin_reconciliation_preserved"]
        evidence(result,"H2_SCHEMA_REHEARSAL_SQLITE.json")
        with pytest.raises(RuntimeError,match="empty disposable"):
            run(engine)
    finally:engine.dispose()


def test_current_schema_seeded_pg(pg_engine):
    result=run(pg_engine)
    assert result["revision"] == "20261015_06" and result["seeded_rows"] == 8
    assert result["data_preserved"] and result["legacy_export_not_broadened"]
    assert "18.6" in result["database_version"]
    evidence(result,"H2_SCHEMA_REHEARSAL_POSTGRESQL.json")
    with pytest.raises(RuntimeError,match="empty disposable"):run(pg_engine)


@pytest.mark.parametrize("url,environment",[
    ("postgresql+psycopg://gate@production.invalid:55441/dermaire_gate_"+"a"*32,"test"),
    ("postgresql+psycopg://gate@127.0.0.1:5432/dermaire_gate_"+"a"*32,"test"),
    ("postgresql+psycopg://gate@127.0.0.1:55441/real_database","test"),
    ("postgresql+psycopg://realuser@127.0.0.1:55441/dermaire_gate_"+"a"*32,"test"),
    ("sqlite:///dermaire_rehearsal_probe.db","production"),
    ("sqlite:///dermaire_dev.db","test"),
    ("sqlite:///:memory:","test"),
    ("sqlite:///dermaire_rehearsal_probe.db?mode=rw","test"),
])
def test_rehearsal_target_guard(url,environment):
    with pytest.raises(RuntimeError):validate_target(url,environment)


def test_existing_sqlite_data_refused(tmp_path):
    engine=create_engine("sqlite:///"+(tmp_path/"dermaire_rehearsal_existing.db").as_posix())
    try:
        with engine.begin() as c:
            c.execute(text("CREATE TABLE sentinel (id INTEGER PRIMARY KEY)"));c.execute(text("INSERT INTO sentinel VALUES (1)"))
        with pytest.raises(RuntimeError,match="empty disposable"):run(engine)
        with engine.connect() as c:assert c.execute(text("SELECT id FROM sentinel")).scalar() == 1
    finally:engine.dispose()


def test_historical_rehearsal_fails_before_target_access(monkeypatch):
    from app.tools import rehearse_index_adoption as historical
    from unittest.mock import Mock
    create=Mock(side_effect=AssertionError("Database access forbidden"))
    monkeypatch.setattr(historical,"create_engine",create)
    monkeypatch.delenv("DATABASE_URL",raising=False)
    with pytest.raises(RuntimeError,match="retired"):historical.main()
    create.assert_not_called()
