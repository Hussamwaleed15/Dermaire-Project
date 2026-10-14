"""Real parallel sessions on isolated SQLite; not PostgreSQL lock proof."""
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from datetime import datetime, timezone
import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Query
from app.core.database import Base
from app.api.v1.doctor import generate_doctor_qr_access, claim_patient_access
from app.models import User, DoctorPatientAccess, AuditLog
from app.schemas import GenerateQrRequest, ClaimAccessRequest


@pytest.fixture
def race_db(tmp_path):
    engine = create_engine("sqlite:///" + (tmp_path / "grants.db").as_posix(),
        connect_args={"check_same_thread": False, "timeout": 10})
    Base.metadata.create_all(engine)
    factory = sessionmaker(bind=engine)
    with factory() as db:
        patient = User(id="patient", email="patient@race.test", full_name="Synthetic patient", hashed_password="test-only", role="patient")
        db.add_all([patient] + [User(id=f"doctor{i}", email=f"doctor{i}@race.test",
            full_name=f"Synthetic doctor {i}", hashed_password="test-only", role="doctor") for i in range(2)])
        db.commit()
        qr = generate_doctor_qr_access(payload=GenerateQrRequest(view_consent=True),
            minutes_valid=60, current_user=patient, session={"jti": "synthetic-session"}, db=db)
        yield factory, qr.access_token, qr.access["id"]
    engine.dispose()


def claim(factory, token, doctor):
    with factory() as db:
        try:
            result = claim_patient_access(ClaimAccessRequest(access_token=token), db.get(User, doctor), db)
            return 200, result
        except HTTPException as exc:
            return exc.status_code, None


def test_parallel_claimers_cannot_reassign_or_replay(race_db, monkeypatch):
    factory, token, access_id = race_db
    barrier = Barrier(2)
    original = Query.update
    def simultaneous(query, *args, **kwargs):
        barrier.wait(timeout=10)
        return original(query, *args, **kwargs)
    monkeypatch.setattr(Query, "update", simultaneous)
    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(claim, factory, token, f"doctor{i}") for i in range(2)]
        results = [future.result(timeout=15) for future in futures]
    assert sorted(status for status, _ in results) == [200, 409]
    winner = next(result for status, result in results if status == 200)
    with factory() as db:
        row = db.get(DoctorPatientAccess, access_id)
        assert row.status == "active" and row.claimed_at is not None
        assert row.doctor_id == winner["access"]["doctor_id"]
        assert db.query(AuditLog).filter_by(action="PATIENT_ACCESS_CLAIMED").count() == 1
