"""Synthetic loopback-only PostgreSQL adoption rehearsal. Never accepts production URLs."""

import os, sys, json, time, pathlib, subprocess, hashlib
from datetime import date, datetime, timedelta, timezone
from sqlalchemy import text, create_engine, MetaData
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError, OperationalError, DBAPIError
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from alembic.autogenerate import compare_metadata
import psycopg


def main():
    repo = pathlib.Path(__file__).resolve().parents[3]
    url = make_url(os.environ["DATABASE_URL"])
    if (
        os.environ.get("ENVIRONMENT") != "test"
        or url.host != "127.0.0.1"
        or url.database != "reconciliation"
        or url.port != 55439
    ):
        raise RuntimeError(
            "Rehearsal requires ENVIRONMENT=test and the dedicated loopback reconciliation database on port 55439"
        )
    from app.core.database import engine, Base
    from app.models import (
        User,
        Product,
        RoutineEntry,
        Experiment,
        CheckIn,
        DoctorPatientAccess,
        DoctorReviewAction,
        ClinicalNote,
        Capture,
        Measurement,
        ProductIntelligence,
        ExperimentEvaluation,
        RoutineAdherence,
        AuditLog,
        RewardRedemption,
        DailyContext,
    )
    from app.tools.schema_audit import audit

    cfg = Config(str(repo / "backend/alembic.ini"))
    command.upgrade(cfg, "20261006_01")
    with engine.begin() as c:
        c.execute(
            text("ALTER TABLE users ALTER COLUMN reset_token_attempts SET DEFAULT 0")
        )
        c.execute(
            text("ALTER TABLE experiments DROP CONSTRAINT experiments_active_owner_key")
        )
        c.execute(
            text(
                "CREATE UNIQUE INDEX uq_experiments_active_owner ON public.experiments USING btree (active_owner)"
            )
        )
        c.execute(
            text(
                "CREATE INDEX ix_experiments_routine_entry_id ON public.experiments USING btree (routine_entry_id)"
            )
        )
        c.execute(text("DROP INDEX ix_users_reset_token_hash"))
        c.execute(text("DROP TABLE alembic_version"))
    now = datetime.now(timezone.utc)
    with Session(engine) as db:
        db.add(
            User(
                id="adoption-doctor",
                email="doctor@example.invalid",
                full_name="Synthetic",
                hashed_password="synthetic",
                role="doctor",
            )
        )
        db.add_all(
            [
                User(
                    id="adoption-p-" + str(i),
                    email="patient-" + str(i) + "@example.invalid",
                    full_name="Synthetic",
                    hashed_password="synthetic",
                )
                for i in range(30)
            ]
        )
        db.commit()
        db.add_all(
            [
                Product(
                    id="adoption-product-" + str(i),
                    user_id="adoption-p-" + str(i),
                    name="Synthetic product",
                )
                for i in range(30)
            ]
        )
        db.commit()
        db.add_all(
            [
                RoutineEntry(
                    id="adoption-entry-" + str(i),
                    user_id="adoption-p-" + str(i),
                    product_id="adoption-product-" + str(i),
                    schedule="AM",
                    frequency="daily",
                    start_date=date(2026, 10, 1),
                    active=True,
                    active_am_product="adoption-product-" + str(i),
                    source="user_configured",
                )
                for i in range(30)
            ]
        )
        db.commit()
        for i in range(30):
            uid = "adoption-p-" + str(i)
            pid = "adoption-product-" + str(i)
            rid = "adoption-entry-" + str(i)
            db.add(
                Experiment(
                    id="adoption-active-" + str(i),
                    user_id=uid,
                    product_id=pid,
                    routine_entry_id=rid,
                    engine_version=2,
                    intervention={},
                    source="user_configured",
                    status="active",
                    active_owner=uid,
                    activated_at=now,
                    definition_snapshot={},
                )
            )
            db.add(
                Experiment(
                    id="adoption-stopped-" + str(i),
                    user_id=uid,
                    product_id=pid,
                    routine_entry_id=rid,
                    engine_version=2,
                    intervention={},
                    source="user_configured",
                    status="stopped",
                    active_owner=None,
                )
            )
            db.add(
                DoctorPatientAccess(
                    id="adoption-grant-" + str(i),
                    doctor_id="adoption-doctor",
                    patient_id=uid,
                    access_token="synthetic-token-" + str(i),
                    status="active",
                    expires_at=now + timedelta(hours=1),
                )
            )
            db.add(
                Capture(
                    id="adoption-capture-" + str(i),
                    user_id=uid,
                    state="accepted",
                    source="camera",
                    view="front",
                    quality={},
                    storage="not_persisted",
                    server_version="synthetic",
                )
            )
        db.commit()
        for i in range(30):
            uid = "adoption-p-" + str(i)
            db.add_all(
                [
                    CheckIn(
                        user_id=uid,
                        experiment_id="adoption-active-" + str(i),
                        date_str="2026-10-01",
                    ),
                    CheckIn(
                        user_id=uid,
                        experiment_id="adoption-stopped-" + str(i),
                        date_str="2026-10-02",
                    ),
                ]
            )
            db.add(
                DoctorReviewAction(
                    id="adoption-review-" + str(i),
                    patient_id=uid,
                    doctor_id="adoption-doctor",
                    access_id="adoption-grant-" + str(i),
                    sequence=1,
                    state="in_review",
                    safety_snapshot={},
                )
            )
            db.add(
                Measurement(
                    user_id=uid,
                    capture_id="adoption-capture-" + str(i),
                    algorithm_version="synthetic",
                    status="measured",
                    results={},
                    quality_reference={},
                    comparison={},
                )
            )
        db.commit()
        for i in range(30):
            db.add(
                ClinicalNote(
                    patient_id="adoption-p-" + str(i),
                    doctor_id="adoption-doctor",
                    review_action_id="adoption-review-" + str(i),
                    content="Synthetic fixture only",
                )
            )
        db.commit()
        models = (
            User,
            Product,
            RoutineEntry,
            Experiment,
            CheckIn,
            DoctorPatientAccess,
            DoctorReviewAction,
            ClinicalNote,
            Capture,
            Measurement,
        )
        before = {m.__tablename__: db.query(m).count() for m in models}
    # Populate the remaining tables and exercise duplicates/NULL reset tokens.
    with Session(engine) as db:
        for i in range(30):
            uid = "adoption-p-" + str(i)
            pid = "adoption-product-" + str(i)
            rid = "adoption-entry-" + str(i)
            db.get(User, uid).reset_token_hash = (
                "synthetic-duplicate" if i < 15 else None
            )
            db.add(ProductIntelligence(user_id=uid, product_id=pid, document={}))
            db.add(
                ExperimentEvaluation(
                    user_id=uid, experiment_id="adoption-active-" + str(i), result={}
                )
            )
            db.add(
                RoutineAdherence(
                    user_id=uid,
                    routine_entry_id=rid,
                    date=date(2026, 10, 1),
                    slot="AM",
                    status="completed",
                    configuration_snapshot={},
                )
            )
            db.add(
                AuditLog(actor_id=uid, action="synthetic", target_resource="synthetic")
            )
            db.add(RewardRedemption(user_id=uid, reward_title="synthetic"))
            db.add(DailyContext(user_id=uid, date=date(2026, 10, 1)))
        db.commit()
        db.add_all(
            [
                Experiment(
                    id="legacy-" + str(i),
                    user_id="adoption-p-" + str(i),
                    engine_version=None,
                    status="paused",
                )
                for i in range(30)
            ]
        )
        db.commit()

    def snapshot():
        with engine.connect() as c:
            return {
                name: {
                    "count": c.execute(
                        text('SELECT count(*) FROM public."' + name + '"')
                    ).scalar(),
                    "hash": hashlib.sha256(
                        c.execute(
                            text(
                                "SELECT COALESCE(string_agg(row_to_json(t)::text, chr(10) ORDER BY id),'') FROM public.\""
                                + name
                                + '" t'
                            )
                        )
                        .scalar()
                        .encode()
                    ).hexdigest(),
                }
                for name in sorted(Base.metadata.tables)
            }

    def catalog(c):
        return list(
            c.execute(
                text(
                    "SELECT tablename,indexname,indexdef FROM pg_indexes WHERE schemaname='public' ORDER BY tablename,indexname"
                )
            ).mappings()
        )

    result = {
        "production_mutations": False,
        "synthetic_only": True,
        "host": "127.0.0.1",
    }
    with engine.connect() as c:
        result["server_version"] = c.execute(text("SHOW server_version")).scalar()
        result["collation"] = c.execute(
            text("SELECT datcollate FROM pg_database WHERE datname=current_database()")
        ).scalar()
        prod = json.loads(pathlib.Path(os.environ["PRODUCTION_CATALOG"]).read_text())
        result["exact_production_index_catalog_match"] = [
            dict(x) for x in catalog(c)
        ] == prod["indexes"]
        assert result["exact_production_index_catalog_match"]
        old = MetaData()
        for table in Base.metadata.sorted_tables:
            table.to_metadata(old)
        old.tables["experiments"].indexes = {
            i
            for i in old.tables["experiments"].indexes
            if i.name != "ix_experiments_routine_entry_id"
        }
        result["frozen_orm_difference_kinds"] = [
            d[0]
            for d in compare_metadata(
                MigrationContext.configure(c, opts={"compare_type": True}), old
            )
        ]
        result["corrected_orm_pre_adoption_differences"] = audit(c)[
            "detected_differences"
        ]
        assert sorted(result["frozen_orm_difference_kinds"]) == [
            "add_constraint",
            "add_index",
            "remove_index",
            "remove_index",
        ]
        result["pre_constraint_catalog"] = [
            dict(x)
            for x in c.execute(
                text(
                    "SELECT conrelid::regclass::text AS table_name,conname,contype,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE connamespace='public'::regnamespace ORDER BY conrelid::regclass::text,conname"
                )
            ).mappings()
        ]
        # Compare all FK/CHECK expressions, not just Alembic's index/type comparison.
        for kind in ["f", "c"]:
            local = [
                (x["table_name"], x["conname"], x["definition"])
                for x in result["pre_constraint_catalog"]
                if x["contype"] == kind
            ]
            actual = [
                (x["table_name"], x["conname"], x["definition"])
                for x in prod["constraints"]
                if x["contype"] == kind
            ]
            assert local == actual, (
                kind,
                "Production-shaped constraint definition mismatch",
            )
        result["exact_production_fk_check_match"] = True
        columns = [
            dict(x)
            for x in c.execute(
                text(
                    "SELECT table_name,column_name,data_type,is_nullable,column_default,character_maximum_length,collation_name FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name,ordinal_position"
                )
            ).mappings()
        ]
        # Prior ctypes inventory encodes SQL NULL as empty text, other values as text.
        normalized = [
            {k: "" if v is None else str(v) for k, v in row.items()} for row in columns
        ]
        assert {(x["table_name"], x["column_name"]): x for x in normalized} == {
        (x["table_name"], x["column_name"]): x for x in prod["columns"]
    }
        result["exact_production_columns_match"] = True
        result["original_index_oids"] = {
            name: c.execute(
                text("SELECT to_regclass(:name)::oid"), {"name": name}
            ).scalar()
            for name in [
                "ix_experiments_routine_entry_id",
                "uq_experiments_active_owner",
            ]
        }
    before = snapshot()

    # ALTER attachment locks even readers. Observe actual lock, timeout and rollback.
    with engine.connect() as first, engine.connect() as observer:
        tick = time.perf_counter()
        first.execute(
            text(
                "ALTER TABLE public.experiments ADD CONSTRAINT uq_experiments_active_owner UNIQUE USING INDEX uq_experiments_active_owner"
            )
        )
        result["attachment_operation_seconds"] = round(time.perf_counter() - tick, 6)
        pid = first.execute(text("SELECT pg_backend_pid()")).scalar()
        result["attachment_lock_modes"] = list(
            observer.execute(
                text(
                    "SELECT mode FROM pg_locks WHERE pid=:pid AND relation='public.experiments'::regclass AND granted"
                ),
                {"pid": pid},
            ).scalars()
        )
        observer.execute(text("SET LOCAL lock_timeout='250ms'"))
        start = time.perf_counter()
        try:
            observer.execute(text("SELECT count(*) FROM experiments"))
            raise AssertionError("ALTER did not block reader")
        except OperationalError as exc:
            assert exc.orig.sqlstate == "55P03"
            result["attachment_blocked_reader_seconds"] = round(
                time.perf_counter() - start, 3
            )
            observer.rollback()
        first.rollback()
    assert snapshot() == before

    # PostgreSQL rejects concurrent builds in transaction blocks, and failed
    # concurrent builds can leave an invalid index that must be explicitly removed.
    with engine.connect() as c:
        try:
            c.execute(
                text(
                    "CREATE INDEX CONCURRENTLY probe_transaction ON users(reset_token_hash)"
                )
            )
            raise AssertionError("Concurrent index accepted inside transaction")
        except DBAPIError as exc:
            assert exc.orig.sqlstate == "25001"
            c.rollback()
    result["concurrently_in_transaction_rejected"] = "25001"
    blocker = psycopg.connect(
        host="127.0.0.1", port=55439, user="reconciliation", dbname="reconciliation"
    )
    builder = psycopg.connect(
        host="127.0.0.1",
        port=55439,
        user="reconciliation",
        dbname="reconciliation",
        autocommit=True,
    )
    try:
        blocker.execute("UPDATE users SET full_name=full_name WHERE id='adoption-p-0'")
        builder.execute("SET lock_timeout='250ms'")
        try:
            builder.execute(
                "CREATE INDEX CONCURRENTLY probe_failed_build ON users(reset_token_hash)"
            )
            raise AssertionError("Concurrent build should have waited for old writer")
        except psycopg.errors.LockNotAvailable:
            pass
        state = builder.execute(
            "SELECT indisvalid,indisready FROM pg_index WHERE indexrelid='probe_failed_build'::regclass"
        ).fetchone()
        assert not state[0]
        result["failed_concurrent_build_invalid_state"] = {
            "indisvalid": state[0],
            "indisready": state[1],
        }
        blocker.rollback()
        builder.execute("DROP INDEX CONCURRENTLY probe_failed_build")
        result["failed_concurrent_build_cleanup"] = (
            "PASS: standalone DROP INDEX CONCURRENTLY after inspecting probe index"
        )
    finally:
        blocker.close()
        builder.close()
    assert snapshot() == before

    # Execute the EXACT psql adoption file, while holding an old users writer open.
    # Concurrent index construction must allow a different users writer to proceed.
    conn = psycopg.connect(
        host="127.0.0.1", port=55439, user="reconciliation", dbname="reconciliation"
    )
    conn.execute("UPDATE users SET full_name=full_name WHERE id='adoption-p-0'")
    proc = subprocess.Popen(
        [
            os.environ["PSQL_BIN"],
            "-X",
            "-h",
            "127.0.0.1",
            "-p",
            "55439",
            "-U",
            "reconciliation",
            "-d",
            "reconciliation",
            "-f",
            str(repo / "docs/production-baseline-adoption.sql"),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    started = time.perf_counter()
    observed = False
    try:
        for attempt in range(160):
            with engine.connect() as c:
                progress = (
                    c.execute(
                        text(
                            "SELECT p.pid,p.phase FROM pg_stat_progress_create_index p WHERE p.relid='public.users'::regclass"
                        )
                    )
                    .mappings()
                    .first()
                )
                if progress:
                    result["concurrent_build_observed_phase"] = progress["phase"]
                    result["concurrent_build_lock_modes"] = list(
                        c.execute(
                            text(
                                "SELECT mode FROM pg_locks WHERE pid=:pid AND relation='public.users'::regclass AND granted"
                            ),
                            {"pid": progress["pid"]},
                        ).scalars()
                    )
                    c.execute(text("SET LOCAL lock_timeout='500ms'"))
                    tick = time.perf_counter()
                    c.execute(
                        text(
                            "UPDATE users SET full_name=full_name WHERE id='adoption-p-1'"
                        )
                    )
                    c.rollback()
                    result["writer_during_concurrent_build_seconds"] = round(
                        time.perf_counter() - tick, 3
                    )
                    observed = True
                    break
            if proc.poll() is not None:
                break
            time.sleep(0.02)
        assert observed, "Concurrent index lock observation was not reached"
    finally:
        conn.rollback()
        conn.close()
    stdout, stderr = proc.communicate(timeout=45)
    assert proc.returncode == 0, "Adoption psql script failed; diagnostics withheld"
    result["exact_sql_script_exit_code"] = proc.returncode
    result["adoption_total_seconds"] = round(time.perf_counter() - started, 3)
    # Separate measurement of attachment was rolled back, so this is the persisted state.
    with engine.connect() as c:
        result["post_adoption_differences"] = audit(c)["detected_differences"]
        assert not result["post_adoption_differences"]
        result["retained_original_index_oids"] = all(
            c.execute(text("SELECT to_regclass(:name)::oid"), {"name": name}).scalar()
            == oid
            for name, oid in result["original_index_oids"].items()
        )
        assert result["retained_original_index_oids"]
        result["final_index_state"] = [
            dict(x)
            for x in c.execute(
                text(
                    "SELECT i.indexrelid::regclass::text AS name, i.indisvalid,i.indisready,i.indislive,i.indisunique,i.indnullsnotdistinct,pg_get_expr(i.indpred,i.indrelid) AS predicate,pg_get_indexdef(i.indexrelid) AS definition FROM pg_index i WHERE i.indexrelid IN ('public.ix_experiments_routine_entry_id'::regclass,'public.ix_users_reset_token_hash'::regclass,'public.uq_experiments_active_owner'::regclass) ORDER BY name"
                )
            ).mappings()
        ]
        assert all(
            i["indisvalid"] and i["indisready"] and i["indislive"]
            for i in result["final_index_state"]
        )
        result["attached_constraint"] = dict(
            c.execute(
                text(
                    "SELECT conname,convalidated,condeferrable,pg_get_constraintdef(oid) AS definition FROM pg_constraint WHERE conname='uq_experiments_active_owner'"
                )
            )
            .mappings()
            .one()
        )
        assert (
            result["attached_constraint"]["convalidated"]
            and not result["attached_constraint"]["condeferrable"]
        )
        result["constraint_violations"] = {}
        for name, t in Base.metadata.tables.items():
            for fk in t.foreign_key_constraints:
                cols = list(fk.columns)
                targets = [e.column for e in fk.elements]
                sql = (
                    'SELECT count(*) FROM "'
                    + name
                    + '" child WHERE '
                    + " AND ".join('child."' + x.name + '" IS NOT NULL' for x in cols)
                    + ' AND NOT EXISTS (SELECT 1 FROM "'
                    + targets[0].table.name
                    + '" parent WHERE '
                    + " AND ".join(
                        'child."' + a.name + '"=parent."' + b.name + '"'
                        for a, b in zip(cols, targets)
                    )
                    + ")"
                )
                key = "fk:" + name + ":" + ",".join(x.name for x in cols)
                result["constraint_violations"][key] = c.execute(text(sql)).scalar()
            checks = c.execute(
                text(
                    "SELECT conname,pg_get_expr(conbin,conrelid) AS expression FROM pg_constraint WHERE contype='c' AND conrelid=to_regclass(:name)"
                ),
                {"name": name},
            ).mappings()
            for check in checks:
                result["constraint_violations"]["check:" + check["conname"]] = (
                    c.execute(
                        text(
                            'SELECT count(*) FROM "'
                            + name
                            + '" WHERE ('
                            + check["expression"]
                            + ") IS FALSE"
                        )
                    ).scalar()
                )
        assert not any(result["constraint_violations"].values())
        assert (
            c.execute(
                text(
                    "SELECT column_default FROM information_schema.columns WHERE table_name='users' AND column_name='reset_token_attempts'"
                )
            ).scalar()
            == "0"
        )
        result["default_zero_preserved"] = True

    # Negative enforcement probes always roll back; no synthetic probe remains.
    probes = {
        "duplicate_active_owner": (
            "INSERT INTO experiments(id,user_id,active_owner) VALUES ('probe','adoption-p-0','adoption-p-0')",
            "23505",
        ),
        "missing_fk": (
            "INSERT INTO experiments(id,user_id) VALUES ('probe','absent')",
            "23503",
        ),
        "invalid_v2_definition": (
            "INSERT INTO experiments(id,user_id,engine_version) VALUES ('probe','adoption-p-0',2)",
            "23514",
        ),
        "invalid_v2_owner": (
            "UPDATE experiments SET active_owner=NULL WHERE id='adoption-active-0'",
            "23514",
        ),
    }
    result["enforcement_probes"] = {}
    for name, (sql, state) in probes.items():
        with engine.connect() as c:
            try:
                c.execute(text(sql))
                raise AssertionError(name + " accepted")
            except IntegrityError as exc:
                assert exc.orig.sqlstate == state
                result["enforcement_probes"][name] = state
                c.rollback()
    with engine.connect() as c:
        c.execute(
            text(
                "INSERT INTO experiments(id,user_id,active_owner) VALUES ('probe-null-1','adoption-p-0',NULL),('probe-null-2','adoption-p-0',NULL)"
            )
        )
        c.execute(
            text(
                "UPDATE users SET reset_token_hash='synthetic-duplicate' WHERE id='adoption-doctor'"
            )
        )
        c.rollback()
    result["multiple_null_owners_and_duplicate_reset_hashes_allowed"] = True
    command.stamp(cfg, "20261006_01")
    command.upgrade(cfg, "head")
    command.check(cfg)
    result["alembic_check"] = "PASS: No new upgrade operations detected"
    with engine.connect() as c:
        result["revision"] = c.execute(
            text("SELECT version_num FROM alembic_version")
        ).scalar()
        assert result["revision"] == "20261008_01"
    after = snapshot()
    assert before == after
    result["row_invariants"] = {
        "before": before,
        "after": after,
        "identical_counts_and_full_row_hashes": True,
        "total_rows": sum(x["count"] for x in before.values()),
    }
    # Actual migration must reject an incorrectly shaped same-name index.
    with engine.begin() as c:
        c.execute(text("DROP INDEX ix_experiments_routine_entry_id"))
        c.execute(
            text("CREATE INDEX ix_experiments_routine_entry_id ON experiments(user_id)")
        )
        c.execute(text("UPDATE alembic_version SET version_num='20261006_01'"))
    try:
        command.upgrade(cfg, "head")
        raise AssertionError("Wrong index silently adopted")
    except RuntimeError as exc:
        assert (
            str(exc) == "Existing routine-entry index differs from reviewed definition"
        )
        result["wrong_same_name_index_rejected"] = True
    with engine.begin() as c:
        c.execute(text("DROP INDEX ix_experiments_routine_entry_id"))
        c.execute(
            text(
                "CREATE INDEX ix_experiments_routine_entry_id ON experiments(routine_entry_id)"
            )
        )
    command.upgrade(cfg, "head")
    command.check(cfg)
    # Fresh installation path proves frozen baseline + new revision agree with ORM.
    os.environ["DATABASE_URL"] = str(url.set(database="fresh"))
    from app.core.config import settings

    settings.DATABASE_URL = os.environ["DATABASE_URL"]
    command.upgrade(cfg, "head")
    command.check(cfg)
    result["fresh_database_upgrade_and_check"] = "PASS"
    result["limits"] = (
        "PostgreSQL 18.6 Windows C collation, loopback plaintext, synthetic rows; exact production index/FK/CHECK definitions. No Azure performance, production collation/ACL or RTO certification."
    )
    pathlib.Path(os.environ["REHEARSAL_OUTPUT"]).write_text(
        json.dumps(result, indent=2, default=str), encoding="utf-8"
    )
    print(
        json.dumps(
            {
                k: v
                for k, v in result.items()
                if k
                not in [
                    "row_invariants",
                    "pre_constraint_catalog",
                    "constraint_violations",
                ]
            },
            indent=2,
            default=str,
        )
    )


if __name__ == "__main__":
    main()
