"""Opt-in disposable PG tests. Never derive targets from application DATABASE_URL."""
import os
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path
from threading import Barrier
from threading import Event
import time
import pytest
import psycopg
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm.exc import StaleDataError
from alembic import command
from alembic.config import Config
from app.core.database import Base
from app.core.config import settings
from app.models import User, Product, DoctorPatientAccess
from app.schemas import GenerateQrRequest, ClaimAccessRequest
from app.api.v1.doctor import generate_doctor_qr_access, claim_patient_access, revoke_one
from app.services.doctor_loop import authorize
from fastapi import HTTPException
from app.core.exceptions import DermaireException


@pytest.fixture
def pg_engine():
    if os.environ.get("DERMAIRE_LOCAL_PG_GATE") != "55441":
        pytest.skip("Dedicated loopback PostgreSQL gate not enabled")
    name = "dermaire_gate_" + uuid.uuid4().hex
    # No arbitrary URL/host/user/database override; fresh DB owned by test-only gate.
    with psycopg.connect(host="127.0.0.1", port=55441, user="gate", dbname="postgres", autocommit=True) as admin:
        admin.execute('CREATE DATABASE "' + name + '"')
        engine = create_engine(f"postgresql+psycopg://gate@127.0.0.1:55441/{name}",
                               connect_args={"options": "-c timezone=UTC -c lock_timeout=3000 -c statement_timeout=10000"})
        try:
            yield engine
        finally:
            engine.dispose()
            admin.execute('DROP DATABASE "' + name + '" WITH (FORCE)')


def seed(engine):
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine, autoflush=False)
    with factory() as db:
        db.add_all([User(id=i, email=i+"@synthetic.test", full_name="Synthetic", hashed_password="test-only", role="patient" if i == "owner" else "doctor") for i in ("owner", "doctor0", "doctor1")])
        db.commit()
    return factory


def observe_lock_wait(engine):
    deadline=time.monotonic()+2
    while time.monotonic() < deadline:
        with engine.connect() as c:
            count=c.execute(text("SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock'")).scalar()
            if count:
                return
        time.sleep(0.02)
    raise AssertionError("Expected real PostgreSQL lock wait was not observed")


def test_pg_seeded_migrations_and_protected_downgrade(pg_engine, monkeypatch):
    monkeypatch.setattr(settings, "DATABASE_URL", pg_engine.url.render_as_string(hide_password=False))
    cfg = Config(str(Path(__file__).parents[1] / "alembic.ini"))
    command.upgrade(cfg, "20261008_01")
    with pg_engine.begin() as c:
        c.execute(text("INSERT INTO users(id,email,hashed_password,full_name,role,reset_token_attempts) VALUES ('owner','owner@synthetic.test','test','Synthetic','patient',0)"))
        c.execute(text("INSERT INTO products(id,user_id,name,category) VALUES ('product','owner','Preserved','treatment')"))
    command.upgrade(cfg, "20261014_01")
    with pg_engine.connect() as c:
        assert c.execute(text("SELECT name,revision,revision_protected FROM products")).one() == ("Preserved", 1, False)
    command.downgrade(cfg, "20261008_01")
    command.upgrade(cfg, "head")
    command.check(cfg)
    with pg_engine.begin() as c:
        c.execute(text("UPDATE products SET revision_protected=true"))
    with pytest.raises(RuntimeError, match="protected products"):
        command.downgrade(cfg, "20261008_01")
    with pg_engine.connect() as c:
        assert c.execute(text("SELECT name,revision_protected FROM products")).one() == ("Preserved", True)


@pytest.mark.parametrize("different_payload", [False, True])
def test_pg_checkin_independent_connections(pg_engine, tmp_path, monkeypatch, different_payload):
    from tests import test_checkin_attempts as existing
    monkeypatch.setattr(existing, "create_engine", lambda *a, **kw: pg_engine)
    existing.test_parallel_unique_commit_and_inflight_unknown(tmp_path, monkeypatch, different_payload)


@pytest.mark.parametrize("different_field", [False, True])
def test_pg_product_cas_independent_connections(pg_engine, different_field):
    factory = seed(pg_engine)
    with factory() as db:
        db.add(Product(id="product", user_id="owner", name="Synthetic")); db.commit()
    barrier = Barrier(2)
    def write(index):
        with factory() as db:
            row = db.get(Product, "product")
            assert row.revision == 1
            barrier.wait(timeout=5)
            row.revision_protected = True
            setattr(row, "brand" if different_field and index else "notes", str(index))
            try:
                db.commit(); return 200
            except StaleDataError:
                db.rollback(); return 412
    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(write, range(2)))
    assert sorted(results) == [200, 412]
    with factory() as db:
        assert db.get(Product, "product").revision == 2


def test_pg_claim_replay_scopes_and_revoke(pg_engine):
    factory = seed(pg_engine)
    with factory() as db:
        qr = generate_doctor_qr_access(GenerateQrRequest(view_consent=True), 60, db.get(User, "owner"), {"jti":"synthetic"}, db)
    barrier = Barrier(2)
    def claim(index):
        with factory() as db:
            barrier.wait(timeout=5)
            try:
                result = claim_patient_access(ClaimAccessRequest(access_token=qr.access_token), db.get(User, "doctor"+str(index)), db)
                return 200, result["access"]["doctor_id"]
            except (HTTPException, DermaireException) as exc:
                db.rollback(); return exc.status_code, None
    with ThreadPoolExecutor(2) as pool:
        results = list(pool.map(claim, range(2)))
    assert sum(code == 200 for code, _ in results) == 1
    winner = next(actor for code, actor in results if code == 200)
    with factory() as db:
        doctor = db.get(User, winner)
        assert authorize(db, doctor, "owner")[1].id == qr.access["id"]
        with pytest.raises(HTTPException) as denied:
            authorize(db, doctor, "owner", scope="EXPORT")
        assert denied.value.status_code == 403
        with pytest.raises((HTTPException, DermaireException)):
            claim_patient_access(ClaimAccessRequest(access_token=qr.access_token), doctor, db)
        db.rollback()
        revoke_one(qr.access["id"], db.get(User, "owner"), db)
        with pytest.raises((HTTPException, DermaireException)):
            authorize(db, doctor, "owner")


@pytest.mark.parametrize("change", ["revoke", "expiry"])
def test_pg_revoke_expiry_before_waiting_claim(pg_engine, change):
    factory = seed(pg_engine)
    with factory() as db:
        qr = generate_doctor_qr_access(GenerateQrRequest(view_consent=True), 60, db.get(User, "owner"), {"jti":"synthetic"}, db)
    with factory() as blocker:
        blocker.query(User).filter_by(id="owner").with_for_update().one()
        with ThreadPoolExecutor(1) as pool:
            def claim():
                with factory() as db:
                    try:
                        claim_patient_access(ClaimAccessRequest(access_token=qr.access_token), db.get(User, "doctor0"), db)
                        return 200
                    except (HTTPException, DermaireException) as exc:
                        db.rollback(); return exc.status_code
            pending = pool.submit(claim)
            observe_lock_wait(pg_engine)
            if change == "revoke":
                revoke_one(qr.access["id"], blocker.get(User,"owner"), blocker)
            else:
                blocker.get(DoctorPatientAccess,qr.access["id"]).expires_at = datetime.now(timezone.utc)-timedelta(seconds=1)
                blocker.commit()
            assert pending.result(timeout=8) != 200
    with factory() as db:
        assert db.get(DoctorPatientAccess,qr.access["id"]).claimed_at is None


def test_pg_row_lock_timeout_and_rollback(pg_engine):
    factory = seed(pg_engine)
    with factory() as first, factory() as second:
        first.query(User).filter_by(id="owner").with_for_update().one()
        second.execute(text("SET LOCAL lock_timeout='150ms'"))
        with pytest.raises(OperationalError) as blocked:
            second.query(User).filter_by(id="owner").with_for_update().one()
        assert blocked.value.orig.sqlstate == "55P03"
        second.rollback(); first.rollback()
        assert second.query(User).filter_by(id="owner").with_for_update().one()
        assert second.execute(text("SHOW transaction_isolation")).scalar() == "read committed"
        assert second.execute(text("SHOW TimeZone")).scalar() == "UTC"


@pytest.fixture
def pg_loop(pg_engine, monkeypatch):
    from tests import test_doctor_loop as original
    monkeypatch.setattr(original, "create_engine", lambda *a, **kw: pg_engine)
    # The original fixture enables SQLite PRAGMA; PG enforces FKs natively.
    monkeypatch.setattr(original.event, "listens_for", lambda *a, **kw: lambda fn: fn)
    fixture = original.loop.__wrapped__()
    try:
        yield next(fixture)
    finally:
        fixture.close()
        from app.main import app
        app.dependency_overrides.clear()


def test_pg_explicit_export_actor_isolation(pg_loop):
    from tests.test_doctor_consent import test_explicit_export_bound_to_selected_doctor_and_receipts
    test_explicit_export_bound_to_selected_doctor_and_receipts(pg_loop)


def test_pg_view_never_implies_export(pg_loop):
    from tests.test_doctor_consent import test_view_never_implies_export
    test_view_never_implies_export(pg_loop, None)


def test_pg_checkin_ttl_isolation_lost_response(pg_engine):
    import asyncio
    from app.models import CheckIn
    from app.api.v1.checkins import submit_daily_checkin
    from app.services import checkin_attempts
    factory = seed(pg_engine)
    key = "synthetic-attempt-ttl-001"
    def submit(db):
        return asyncio.run(submit_daily_checkin(time_of_day="Morning", hydration_score=50,
            texture_score=60, redness_score=70, notes=None, experiment_id=None, photo=None,
            report=None, idempotency_key=key, current_user=db.get(User,"owner"), db=db))
    with factory() as db:
        result = submit(db)
    with factory() as fresh:
        lookup = checkin_attempts.lookup(fresh,"owner",key)
        assert lookup["status"] == "committed" and lookup["result"]["id"] == result.id
        assert checkin_attempts.lookup(fresh,"doctor0",key)["status"] == "unknown"
        assert submit(fresh).id == result.id
        fresh.get(CheckIn,result.id).created_at = datetime.now(timezone.utc)-timedelta(days=30, seconds=1)
        fresh.commit()
        assert checkin_attempts.lookup(fresh,"owner",key)["status"] == "expired"
        with pytest.raises(HTTPException) as expired:
            submit(fresh)
        assert expired.value.status_code == 410


@pytest.mark.parametrize("operation",["note","review"])
@pytest.mark.parametrize("ordering",["clinical_first","revoke_first"])
def test_pg_clinical_revoke_lock_order(pg_engine,monkeypatch,operation,ordering):
    from app.api.v1 import doctor as api
    from app.schemas import ClinicalNoteCreate
    from app.schemas.doctor_loop import ReviewActionCreate
    from app.models import ClinicalNote,DoctorReviewAction
    factory=seed(pg_engine)
    with factory() as db:
        qr=generate_doctor_qr_access(GenerateQrRequest(view_consent=True),60,db.get(User,"owner"),{"jti":"synthetic"},db)
        claim_patient_access(ClaimAccessRequest(access_token=qr.access_token),db.get(User,"doctor0"),db)
    model=ClinicalNote if operation=="note" else DoctorReviewAction
    def clinical():
        with factory() as db:
            actor=db.get(User,"doctor0")
            if operation=="note":api.add_clinical_note("owner",ClinicalNoteCreate(content="Synthetic clinical note"),actor,db)
            else:api.add_review("owner",ReviewActionCreate(state="reviewed",expected_sequence=0),actor,db)
    def revoke():
        with factory() as db:revoke_one(qr.access["id"],db.get(User,"owner"),db)
    if ordering=="revoke_first":
        revoke()
        with pytest.raises(HTTPException) as denied:clinical()
        assert denied.value.status_code == 403
        with factory() as db:assert db.query(model).count() == 0
        return
    reached,resume=Event(),Event()
    original=api.authorize
    def pause_after_authorization(*args,**kwargs):
        result=original(*args,**kwargs);reached.set()
        assert resume.wait(timeout=5)
        return result
    monkeypatch.setattr(api,"authorize",pause_after_authorization)
    with ThreadPoolExecutor(2) as pool:
        first=pool.submit(clinical);assert reached.wait(timeout=5)
        second=pool.submit(revoke)
        try:observe_lock_wait(pg_engine)
        finally:resume.set()
        first.result(timeout=8);second.result(timeout=8)
    with factory() as db:
        assert db.query(model).count() == 1
        assert db.get(DoctorPatientAccess,qr.access["id"]).status == "revoked"


def test_pg_product_api_if_match_and_parallel_cas(pg_engine):
    from app.api.v1.products import update_product
    from app.schemas import ProductUpdate
    factory=seed(pg_engine)
    with factory() as db:db.add(Product(id="product",user_id="owner",name="Synthetic"));db.commit()
    barrier=Barrier(2)
    def write(index):
        with factory() as db:
            actor=db.get(User,"owner");barrier.wait(timeout=5)
            try:
                update_product("product",ProductUpdate(notes=str(index)),if_match='"1"',current_user=actor,db=db);return 200
            except HTTPException as exc:db.rollback();return exc.status_code
    with ThreadPoolExecutor(2) as pool:assert sorted(pool.map(write,range(2))) == [200,412]
    with factory() as db:
        for value,code in [(None,428),('"1"',412)]:
            with pytest.raises(HTTPException) as denied:update_product("product",ProductUpdate(notes="Denied"),if_match=value,current_user=db.get(User,"owner"),db=db)
            assert denied.value.status_code == code
            db.rollback()


def test_pg_deadlock_detection_is_bounded(pg_engine):
    factory=seed(pg_engine);barrier=Barrier(2)
    def opposing(index):
        with factory() as db:
            first,second=("owner","doctor0") if index else ("doctor0","owner")
            db.query(User).filter_by(id=first).with_for_update().one()
            barrier.wait(timeout=5)
            try:
                db.query(User).filter_by(id=second).with_for_update().one();db.commit();return "committed"
            except OperationalError as exc:
                state=exc.orig.sqlstate;db.rollback();return state
    with ThreadPoolExecutor(2) as pool:assert sorted(pool.map(opposing,range(2))) == ["40P01","committed"]
    # This deliberately reversed test-only order validates detector/rollback,
    # not a claim that all possible application deadlocks have been enumerated.


def test_pg_product_update_delete_cas(pg_engine):
    factory=seed(pg_engine)
    with factory() as db:db.add(Product(id="product",user_id="owner",name="Synthetic"));db.commit()
    barrier=Barrier(2)
    def mutate(index):
        with factory() as db:
            row=db.get(Product,"product");barrier.wait(timeout=5)
            if index:db.delete(row)
            else:row.notes="Updated"
            try:db.commit();return "committed"
            except StaleDataError:db.rollback();return "stale"
    with ThreadPoolExecutor(2) as pool:assert sorted(pool.map(mutate,range(2))) == ["committed","stale"]
