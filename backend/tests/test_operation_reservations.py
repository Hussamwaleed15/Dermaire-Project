from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from alembic import command
from alembic.config import Config
from pathlib import Path

from app.core.database import Base
from app.models import OperationReservation, User
from app.services import operation_reservations as reservations


OWNER = "reservation-owner"
KEY = "synthetic_operation_key_0000000001"
DIGEST = reservations.payload_digest({"resource": "synthetic", "value": 1})


@pytest.fixture
def factory():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(engine)
    maker = sessionmaker(bind=engine, autoflush=False)
    with maker() as db:
        db.add(User(id=OWNER, email="reservation@synthetic.test", hashed_password="test",
                    full_name="Synthetic", role="patient"))
        db.commit()
    try:
        yield maker
    finally:
        engine.dispose()


def claim(db, **overrides):
    values = dict(owner_id=OWNER, domain="products", operation="create", key=KEY,
                  payload_hash=DIGEST)
    values.update(overrides)
    return reservations.reserve(db, **values)


def test_commit_replay_binding_and_no_raw_secrets(factory):
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with factory() as db:
        first = claim(db, now=now)
        db.commit()
        assert first.status == "reserved" and first.generation == 1 and first.lease_token
        row = db.get(OperationReservation, first.reservation_id)
        assert row.key_hash != KEY and row.lease_token_hash != first.lease_token
        reservations.commit(db, owner_id=OWNER, reservation_id=first.reservation_id,
                            generation=first.generation, lease_token=first.lease_token,
                            result_snapshot={"resource_id": "synthetic"}, now=now)
        db.commit()
        replay = claim(db, now=now + timedelta(seconds=1))
        assert replay.status == "committed"
        assert replay.result_snapshot == {"resource_id": "synthetic"}
        with pytest.raises(reservations.ReservationConflict):
            claim(db, payload_hash="f" * 64, now=now + timedelta(seconds=1))
        db.rollback()
        stored = repr(db.get(OperationReservation, first.reservation_id).__dict__)
        assert KEY not in stored and first.lease_token not in stored


def test_crash_takeover_generation_fences_old_worker(factory):
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with factory() as db:
        old = claim(db, now=now, lease=timedelta(seconds=2))
        db.commit()
        new = claim(db, now=now + timedelta(seconds=3), lease=timedelta(seconds=2))
        db.commit()
        assert new.reservation_id == old.reservation_id and new.generation == 2
        with pytest.raises(reservations.ReservationFenceLost):
            reservations.commit(db, owner_id=OWNER, reservation_id=old.reservation_id,
                                generation=old.generation, lease_token=old.lease_token,
                                now=now + timedelta(seconds=3))
        db.rollback()
        reservations.commit(db, owner_id=OWNER, reservation_id=new.reservation_id,
                            generation=new.generation, lease_token=new.lease_token,
                            now=now + timedelta(seconds=3))
        db.commit()


def test_rollback_failure_retry_retention_and_purge(factory):
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with factory() as db:
        rolled_back = claim(db, now=now)
        db.rollback()
        assert db.get(OperationReservation, rolled_back.reservation_id) is None
        first = claim(db, now=now, retention=timedelta(minutes=2))
        db.commit()
        reservations.fail(db, owner_id=OWNER, reservation_id=first.reservation_id,
                          generation=1, lease_token=first.lease_token,
                          failure_code="retryable_failure", now=now)
        db.commit()
        retry = claim(db, now=now + timedelta(seconds=1), retention=timedelta(minutes=2))
        assert retry.generation == 2 and retry.status == "reserved"
        db.commit()
        with pytest.raises(reservations.ReservationExpired):
            claim(db, now=now + timedelta(minutes=3), retention=timedelta(minutes=2))
        db.rollback()
        assert reservations.purge_expired(db, owner_id=OWNER,
                                           now=now + timedelta(minutes=3)) == 1
        db.commit()
        assert db.query(OperationReservation).count() == 0


def test_lease_never_outlives_retention(factory):
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    with factory() as db:
        first = claim(db, now=now, lease=timedelta(minutes=1),
                      retention=timedelta(minutes=2))
        db.commit()
        expiry = reservations.renew(
            db, owner_id=OWNER, reservation_id=first.reservation_id,
            generation=first.generation, lease_token=first.lease_token,
            now=now + timedelta(seconds=30), lease=timedelta(minutes=5))
        assert expiry == now.replace(tzinfo=None) + timedelta(minutes=2)
        db.commit()
        with pytest.raises(reservations.ReservationFenceLost):
            reservations.commit(
                db, owner_id=OWNER, reservation_id=first.reservation_id,
                generation=first.generation, lease_token=first.lease_token,
                now=now + timedelta(minutes=2))
        db.rollback()


def test_database_constraints_reject_invalid_shape(factory):
    with factory() as db:
        db.execute(text("PRAGMA foreign_keys=ON"))
        bad = OperationReservation(
            id="bad", owner_id=OWNER, domain="products", operation="create",
            key_hash="a" * 64, payload_hash="b" * 64, status="committed", generation=0,
            lease_token_hash="c" * 64, lease_expires_at=datetime(2026, 1, 2),
            created_at=datetime(2026, 1, 1), updated_at=datetime(2026, 1, 1),
            retain_until=datetime(2026, 2, 1),
        )
        db.add(bad)
        with pytest.raises(Exception):
            db.flush()
        db.rollback()


def test_sqlite_additive_migration_and_guarded_downgrade(tmp_path, monkeypatch):
    from app.core.config import settings
    url = "sqlite:///" + (tmp_path / "reservation-migration.db").as_posix()
    monkeypatch.setattr(settings, "DATABASE_URL", url)
    cfg = Config(str(Path(__file__).parents[1] / "alembic.ini"))
    command.upgrade(cfg, "head")
    engine = create_engine(url)
    maker = sessionmaker(bind=engine, autoflush=False)
    try:
        with maker() as db:
            db.add(User(id=OWNER, email="migration@synthetic.test", hashed_password="test",
                        full_name="Synthetic", role="patient"))
            db.commit()
            value = claim(db)
            db.commit()
            assert value.status == "reserved"
        with pytest.raises(RuntimeError, match="non-empty operation_reservations"):
            command.downgrade(cfg, "20261024_14")
        with engine.connect() as connection:
            assert connection.execute(text("SELECT version_num FROM alembic_version")).scalar() == "20261024_15"
            assert connection.execute(text("SELECT count(*) FROM operation_reservations")).scalar() == 1
    finally:
        engine.dispose()
