"""Current H1/H2 schema rehearsal. Only new synthetic local databases are accepted."""
import hashlib
import json
import os
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from sqlalchemy import MetaData, create_engine, inspect, select
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session
from alembic import command
from alembic.config import Config


def validate_target(value, environment):
    url = make_url(value)
    if environment != "test" or url.query:
        raise RuntimeError("Rehearsal requires test environment and a dedicated synthetic target")
    if url.drivername == "postgresql+psycopg":
        if url.host != "127.0.0.1" or url.port != 55441 or url.username != "gate" or not re.fullmatch(r"dermaire_gate_[0-9a-f]{32}",url.database or ""):
            raise RuntimeError("Rehearsal PG target must be the dedicated loopback disposable gate")
    elif url.drivername == "sqlite":
        if not url.database or url.database == ":memory:" or not Path(url.database).name.startswith("dermaire_rehearsal_"):
            raise RuntimeError("Rehearsal SQLite target requires a dedicated dermaire_rehearsal_* file")
    else:
        raise RuntimeError("Unsupported rehearsal driver")
    return url


def run(engine):
    validate_target(engine.url,os.environ.get("ENVIRONMENT"))
    # Never downgrade/drop existing application objects, even on an allowed host.
    if inspect(engine).get_table_names():
        raise RuntimeError("Rehearsal requires an empty disposable database; existing data is refused")
    from app.core.config import settings
    from app.models import Product, RoutineEntry, Experiment, DoctorPatientAccess
    from app.schemas import CheckInReport
    from app.services import checkin_attempts
    from app.services.doctor_loop import access_out
    config=Config(str(Path(__file__).resolve().parents[2]/"alembic.ini"))
    previous=settings.DATABASE_URL
    settings.DATABASE_URL=engine.url.render_as_string(hide_password=False)
    try:
        command.upgrade(config,"20261008_01")
        old=MetaData();old.reflect(engine)
        now=datetime.now(timezone.utc).replace(tzinfo=None)
        key="synthetic-rehearsal-checkin-0001"
        report=CheckInReport(overall_change="same")
        checkin_id=checkin_attempts.identity("owner",key)
        digest=checkin_attempts.fingerprint("Morning",None,None,report,[None,None,None])
        with engine.begin() as c:
            c.execute(old.tables["users"].insert(),[dict(id=i,email=i+"@synthetic.test",hashed_password="test-only",full_name="Synthetic",role="patient" if i=="owner" else "doctor",reset_token_attempts=0) for i in ("owner","doctor")])
            c.execute(old.tables["products"].insert().values(id="product",user_id="owner",name="Preserved product",category="treatment",status="active"))
            c.execute(old.tables["routine_entries"].insert().values(id="entry",user_id="owner",product_id="product",schedule="AM",frequency="daily",start_date=now.date(),active=True,am_order=0,pm_order=0,source="user_configured",created_at=now,updated_at=now,instructions="Preserved configuration"))
            c.execute(old.tables["experiments"].insert().values(id="experiment",user_id="owner",product_id="product",status="completed",engine_version=None,notes="Preserved legacy",target_days=7,current_day=1,start_date=now,created_at=now))
            c.execute(old.tables["routine_adherence"].insert().values(id="adherence",user_id="owner",routine_entry_id="entry",date=now.date(),slot="AM",status="completed",source="user_reported",created_at=now,note="Preserved report",configuration_snapshot={"schedule":"AM","active":True,"frequency":"daily","product_id":"product"}))
            c.execute(old.tables["checkins"].insert().values(id=checkin_id,user_id="owner",date_str=now.date().isoformat(),time_of_day="Morning",created_at=now,observation={"schema_version":1,"user_reported":report.model_dump(),"daily_context_date":now.date().isoformat(),"provenance":{"report":"user_reported","created_at":"server_recorded"},"attempt":{"schema_version":1,"payload_hash":digest}},ai_vision_analysis={"measurement_source":"none"}))
            c.execute(old.tables["doctor_patient_access"].insert().values(id="grant",patient_id="owner",doctor_id="doctor",access_token="synthetic-not-a-valid-token",status="active",export_consent=True,expires_at=now+timedelta(minutes=10),created_at=now))
        def snapshot():
            with engine.connect() as c:
                return {name:[dict(row) for row in c.execute(select(table).order_by(table.c.id)).mappings()] for name,table in old.tables.items() if name != "alembic_version"}
        before=snapshot()
        command.upgrade(config,"head")
        command.check(config)
        after=snapshot()
        assert before == after, "Original columns/rows were not preserved"
        with Session(engine) as db:
            for model in (Product,RoutineEntry,Experiment):
                row=db.query(model).one()
                assert row.revision == 1 and row.revision_protected is False
            assert "EXPORT" not in access_out(db.get(DoctorPatientAccess,"grant"),db)["effective_scopes"]
            found=checkin_attempts.lookup(db,"owner",key)
            assert found["status"] == "committed" and found["result"]["id"] == checkin_id
            assert checkin_attempts.lookup(db,"doctor",key)["status"] == "unknown"
        with engine.connect() as c:
            from sqlalchemy import text
            revision=c.execute(text("SELECT version_num FROM alembic_version")).scalar()
            version=c.execute(text("SELECT version()" if engine.dialect.name=="postgresql" else "SELECT sqlite_version()")).scalar()
        return {"synthetic_only":True,"live_calls":False,"driver":engine.url.drivername,"database_version":version,"revision":revision,
            "seed_revision":"20261008_01","data_preserved":True,"tables_checked":len(before),"seeded_rows":sum(len(rows) for rows in before.values()),
            "original_columns_digest":hashlib.sha256(json.dumps(before,sort_keys=True,default=str).encode()).hexdigest(),
            "legacy_export_not_broadened":True,"checkin_reconciliation_preserved":True,"default_revisions_verified":True,
            "alembic_check":"no new upgrade operations","limits":"No managed deployment, index adoption, latency, collation, roles or DR certification"}
    finally:
        settings.DATABASE_URL=previous


def main():
    value=os.environ["DERMAIRE_REHEARSAL_URL"]
    url=validate_target(value,os.environ.get("ENVIRONMENT"))
    engine=create_engine(url)
    try:
        result=run(engine)
        destination=Path(os.environ["DERMAIRE_REHEARSAL_OUTPUT"])
        destination.write_text(json.dumps(result,indent=2),encoding="utf-8")
        print(json.dumps(result,indent=2))
    finally:
        engine.dispose()


if __name__ == "__main__":
    main()
