"""Cross-milestone consent/review receipts against real isolated PostgreSQL."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.orm import sessionmaker

from app.models import AuditLog, User
from app.schemas import AcceptSafetyRequest
from app.services.onboarding import complete_review, review_snapshot
from app.services.policy_consent import accept_policy, consent_snapshot
from tests.test_postgres_gate import observe_lock_wait, pg_engine


def test_aware_historical_timestamps_preserve_instant():
    plus_three = timezone(timedelta(hours=3))
    stamp = datetime(2026, 1, 2, 12, 0, tzinfo=plus_three)
    user = User(role="patient", safety_accepted=True, safety_policy_version="1.0",
                safety_accepted_at=stamp, profile_reviewed_at=stamp)
    assert consent_snapshot(user)["accepted_at"] == datetime(2026, 1, 2, 9, 0, tzinfo=timezone.utc)
    assert review_snapshot(user)["reviewed_at"] == datetime(2026, 1, 2, 9, 0, tzinfo=timezone.utc)
    user.safety_policy_version = "1." + "0" * 20
    assert consent_snapshot(user)["state"] == "unknown"


@pytest.mark.parametrize("first,second", [("accept", "accept"), ("review", "review"), ("accept", "review")])
def test_pg_serialized_h3_commands_and_atomic_audits(pg_engine, first, second):
    from app.core.database import Base
    Base.metadata.create_all(pg_engine)
    factory = sessionmaker(bind=pg_engine)
    with factory() as db:
        db.add(User(id="h3-owner", email="h3-owner@synthetic.test", full_name="Synthetic",
                    hashed_password="test-only", role="patient",
                    safety_accepted=first != "accept", safety_policy_version="1.0" if first != "accept" else None,
                    safety_accepted_at=datetime(2026, 1, 2, tzinfo=timezone.utc) if first != "accept" else None))
        db.commit()

    with factory() as blocker:
        blocker.query(User).filter_by(id="h3-owner").with_for_update().one()

        def execute(command):
            with factory() as db:
                user = db.get(User, "h3-owner")
                if command == "accept":
                    accept_policy(db, user, AcceptSafetyRequest())
                    return consent_snapshot(user)["state"]
                complete_review(db, user)
                return review_snapshot(user)["review_state"]

        with ThreadPoolExecutor(1) as pool:
            pending = pool.submit(execute, first)
            observe_lock_wait(pg_engine)
            blocker.commit()
            assert pending.result(timeout=8) in {"current", "reviewed"}
    assert execute(second) in {"current", "reviewed"}
    with factory() as db:
        user = db.get(User, "h3-owner")
        assert consent_snapshot(user)["state"] == "current"
        expected_review = first == "review" or second == "review"
        assert (review_snapshot(user)["review_state"] == "reviewed") == expected_review
        assert db.query(AuditLog).filter_by(actor_id="h3-owner", action="SAFETY_TERMS_ACCEPTED").count() == (1 if first == "accept" else 0)
        assert db.query(AuditLog).filter_by(actor_id="h3-owner", action="PROFILE_REVIEW_COMPLETED").count() == (1 if expected_review else 0)
