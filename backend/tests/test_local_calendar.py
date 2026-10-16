from datetime import datetime, timezone
import pytest
from tests.test_account_deletion import deletion_context
from app.models.routine_history import UserCalendarPolicy
from app.services import local_calendar
from tests.test_postgres_gate import pg_engine


def test_calendar_travel_cas_and_forward_only(deletion_context):
    client, db, auth = deletion_context
    route = '/api/v1/routine/calendar-policy'
    assert client.get(route, headers=auth).json()['revision'] == 0
    first = client.put(route, headers=auth, json={'timezone': 'Asia/Tokyo', 'expected_revision': 0})
    assert first.status_code == 200
    assert first.json()['adherence_day_basis'] == 'UTC'
    assert first.json()['historical_reinterpretation'] is False
    assert client.put(route, headers=auth, json={'timezone': 'America/New_York', 'expected_revision': 0}).status_code == 412
    changed = client.put(route, headers=auth, json={'timezone': 'America/New_York', 'expected_revision': 1})
    assert changed.status_code == 200 and changed.json()['revision'] == 2
    assert len(db.query(UserCalendarPolicy).all()) == 2
    assert first.json()['effective_at'] <= changed.json()['effective_at']
    assert client.put(route, headers=auth, json={'timezone': 'America/New_York', 'expected_revision': 2}).json()['revision'] == 2
    assert client.put(route, headers=auth, json={'timezone': 'Bad/Zone', 'expected_revision': 2}).status_code == 422
    assert client.put(route, headers=auth, json={'timezone': 'UTC', 'expected_revision': 2, 'effective_at': '2000-01-01'}).status_code == 422
    assert client.get(route).status_code == 401


@pytest.mark.parametrize('zone,instant,label', [
    ('Asia/Tokyo', '2026-10-15T15:00:00+00:00', '2026-10-16'),
    ('America/New_York', '2026-03-08T06:59:00+00:00', '2026-03-08'),
    ('America/New_York', '2026-03-08T07:00:00+00:00', '2026-03-08'),
    ('America/New_York', '2026-11-01T05:30:00+00:00', '2026-11-01'),
    ('America/New_York', '2026-11-01T06:30:00+00:00', '2026-11-01'),
    ('Pacific/Honolulu', '2026-10-15T05:00:00+00:00', '2026-10-14'),
])
def test_calendar_instant_labels_midnight_gap_fold_travel(zone, instant, label):
    row = UserCalendarPolicy(timezone_name=zone, revision=1, effective_at=datetime.now(timezone.utc))
    value = local_calendar.view(row, datetime.fromisoformat(instant))
    assert value['local_today'].isoformat() == label
    assert value['adherence_day_basis'] == 'UTC'


def test_pg_calendar_concurrent_cas(pg_engine):
    from tests.test_postgres_gate import seed
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier
    from fastapi import HTTPException
    from app.models import User
    factory = seed(pg_engine)
    barrier = Barrier(2)
    def mutate(zone):
        with factory() as db:
            user = db.get(User, 'owner')
            barrier.wait(timeout=5)
            try:
                local_calendar.change(db, user, zone, 0)
                return 200
            except HTTPException as exc:
                db.rollback()
                return exc.status_code
    with ThreadPoolExecutor(2) as pool:
        assert sorted(pool.map(mutate, ['Asia/Tokyo', 'America/New_York'])) == [200, 412]
    with factory() as db:
        assert db.query(UserCalendarPolicy).count() == 1
