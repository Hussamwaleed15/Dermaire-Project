from datetime import datetime, date, timezone, timedelta
import pytest
from app.services.temporal import utc_day
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create, report


@pytest.mark.parametrize("instant,expected", [
    (datetime(2026, 10, 30, 0, 30, tzinfo=timezone(timedelta(hours=3))), date(2026, 10, 29)),
    (datetime(2026, 10, 30, 0, 30, tzinfo=timezone(timedelta(hours=2))), date(2026, 10, 29)),
    (datetime(2026, 3, 8, 23, 30, tzinfo=timezone(timedelta(hours=-4))), date(2026, 3, 9)),
    (datetime(2026, 3, 8, 23, 30), date(2026, 3, 8)),
])
def test_utc_day_across_offset_and_dst_boundaries(instant, expected):
    assert utc_day(instant) == expected


def test_explicit_temporal_contract_and_frozen_adherence(deletion_context):
    client, _, auth = deletion_context
    entry = create(client, auth).json()
    assert entry['day_basis'] == 'UTC'
    assert entry['configuration_history'] == 'current_with_adherence_snapshots'
    saved = report(client, auth, entry).json()
    assert saved['day_basis'] == saved['configuration_snapshot']['day_basis'] == 'UTC'
    assert saved['configuration_snapshot']['revision'] == entry['revision']
    path = '/api/v1/routine/entries/' + entry['id']
    assert client.patch(path, headers={**auth, 'If-Match': '"1"'}, json={'instructions': 'New'}).status_code == 200
    assert client.get('/api/v1/routine/adherence', headers=auth).json() == [saved]
    assert client.patch(path, headers=auth, json={'instructions': 'Old client'}).status_code == 428
