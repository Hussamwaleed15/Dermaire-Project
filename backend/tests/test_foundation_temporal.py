from datetime import datetime, date, timezone
from zoneinfo import ZoneInfo
import pytest
from app.services.temporal import utc_day
from app.models import User
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create, report
from app.core.security import create_access_token


@pytest.mark.parametrize("at", ["2026-03-08T06:59:00+00:00", "2026-03-08T07:00:00+00:00",
    "2026-11-01T05:30:00+00:00", "2026-11-01T06:30:00+00:00",
    "2026-10-14T23:59:59+00:00", "2026-10-15T00:00:00+00:00"])
def test_dst_gap_overlap_and_midnight_keep_server_day(at):
    instant = datetime.fromisoformat(at)
    for zone in ("America/New_York", "Africa/Cairo", "Pacific/Auckland"):
        assert utc_day(instant.astimezone(ZoneInfo(zone))) == instant.date()


def test_source_backed_configuration_day_and_frozen_legacy(deletion_context):
    client, db, auth = deletion_context
    entry = create(client, auth).json()
    provenance = entry['day_provenance']
    assert provenance['calendar_zone'] == 'UTC'
    assert provenance['zone_source'] == 'server_utc_contract'
    assert provenance['slot_semantics'] == 'user_reported_not_wall_clock'
    assert provenance['earliest_report_date'] == max(entry['start_date'], entry['updated_at'][:10])
    saved = report(client, auth, entry).json()
    assert saved['configuration_snapshot']['day_provenance'] == provenance
    path = '/api/v1/routine/entries/' + entry['id']
    assert client.patch(path, headers={**auth, 'If-Match':'"1"'}, json={'instructions':'Changed'}).status_code == 200
    assert client.get('/api/v1/routine/adherence', headers=auth).json() == [saved]
    other={'Authorization':'Bearer '+create_access_token('delete-doctor', 'doctor', hashed_password='unused')}
    assert client.get(path, headers=other).status_code == 404
    assert client.get('/api/v1/routine/entries', headers=other).json() == []
    assert client.patch(path, headers=auth, json={'instructions':'Old'}).status_code == 428


from tests.test_postgres_gate import pg_engine, seed


def test_pg_temporal_provenance_configuration_and_owner(pg_engine):
    from app.models import Product, RoutineEntry
    from app.schemas.routine import RoutineOut
    from app.services.routine import owned_entry
    from fastapi import HTTPException
    factory = seed(pg_engine)
    with factory() as db:
        db.add(Product(id='p', user_id='owner', name='Synthetic')); db.commit()
        db.add(RoutineEntry(id='entry', user_id='owner', product_id='p', schedule='BOTH',
            frequency='daily', start_date=date(2026,3,1),
            updated_at=datetime(2026,3,8,7,0), created_at=datetime(2026,3,1)))
        db.commit()
        entry=owned_entry(db, db.get(User,'owner'), 'entry')
        out=RoutineOut.model_validate(entry)
        assert out.day_provenance.earliest_report_date == date(2026,3,8)
        assert out.day_provenance.configuration_recorded_at.tzinfo == timezone.utc
        assert out.day_provenance.slot_semantics == 'user_reported_not_wall_clock'
        with pytest.raises(HTTPException) as denied:
            owned_entry(db, db.get(User,'doctor0'), 'entry')
        assert denied.value.status_code == 404
