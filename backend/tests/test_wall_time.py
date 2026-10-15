from datetime import datetime, timezone
import pytest
from app.services.wall_time import resolve_due, quiet_at


def test_dst_gap_overlap_and_fixed_instant():
    with pytest.raises(ValueError, match="Nonexistent"):
        resolve_due(datetime(2026, 3, 8, 2, 30), "America/New_York")
    local = datetime(2026, 11, 1, 1, 30)
    with pytest.raises(ValueError, match="Ambiguous"):
        resolve_due(local, "America/New_York")
    first = resolve_due(local, "America/New_York", 0)
    second = resolve_due(local, "America/New_York", 1)
    assert first["due_at_utc"] == "2026-11-01T05:30:00+00:00"
    assert second["due_at_utc"] == "2026-11-01T06:30:00+00:00"
    assert first["policy"] == "fixed_utc_explicit_reschedule_v1"


@pytest.mark.parametrize("zone", ["UTC", "Africa/Cairo", "Asia/Kathmandu"])
def test_round_trip(zone):
    value = resolve_due(datetime(2026, 1, 10, 12, 15), zone)
    assert value["local_time"] == "2026-01-10T12:15:00"
    assert value["timezone"] == zone


@pytest.mark.parametrize("local,zone,fold", [
    (datetime.now(timezone.utc), "UTC", None),
    (datetime(2026,1,1), "invalid/zone", None),
    (datetime(2026,1,1), "UTC", 1),
    (datetime(2026,1,1), "UTC", True),
    (datetime(2026,1,1), "UTC", 2),
])
def test_invalid_wall_time(local, zone, fold):
    with pytest.raises(ValueError): resolve_due(local, zone, fold)


@pytest.mark.parametrize("hour,expected", [(21,False),(22,True),(23,True),(0,True),(6,True),(7,False)])
def test_overnight_quiet_hours(hour, expected):
    assert quiet_at(datetime(2026,1,1,hour,tzinfo=timezone.utc), "UTC", 1320, 420) is expected


def test_quiet_repeated_hour_and_boundaries():
    for hour in (5,6):
        assert quiet_at(datetime(2026,11,1,hour,30,tzinfo=timezone.utc), "America/New_York", 60,120)
    now = datetime.now(timezone.utc)
    assert not quiet_at(now, "UTC", 0, 0)
    with pytest.raises(ValueError): quiet_at(now.replace(tzinfo=None), "UTC", 0, 60)
    with pytest.raises(ValueError): quiet_at(now, "UTC", -1, 60)
