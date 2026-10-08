from datetime import datetime, timedelta, timezone

import pytest

from app.core.operational_targets import (
    journal_expiration_eligible, validate_recovery_horizon,
)


@pytest.mark.parametrize("backup,quarantine", [(35, 7), (7, 7), (0, 0)])
def test_accepted_recovery_horizon(backup, quarantine):
    validate_recovery_horizon(backup, quarantine)


@pytest.mark.parametrize("backup,quarantine", [(36, 0), (35, 8), (-1, 7), (35, -1),
                                                   (True, 7), (35.0, 7)])
def test_longer_or_invalid_horizon_requires_indefinite_retention(backup, quarantine):
    with pytest.raises(ValueError):
        validate_recovery_horizon(backup, quarantine)


def test_expiration_waits_for_age_and_every_recoverable_copy():
    modified = datetime(2026, 1, 1, tzinfo=timezone.utc)
    now = modified + timedelta(days=42)
    args = dict(last_modified=modified, now=now, inventory_complete=True)
    assert journal_expiration_eligible(**args, recoverable_until=[now])
    assert not journal_expiration_eligible(**args, recoverable_until=[now, now + timedelta(seconds=1)])
    assert not journal_expiration_eligible(**{**args, "now": now - timedelta(seconds=1)},
                                           recoverable_until=[])
    # A later export/restored target can outlive the normal 35-day backup horizon.
    assert not journal_expiration_eligible(**args, recoverable_until=[now + timedelta(days=90)])


def test_unknown_inventory_hold_and_naive_dates_fail_closed():
    modified = datetime(2026, 1, 1, tzinfo=timezone.utc)
    args = dict(last_modified=modified, now=modified + timedelta(days=100),
                recoverable_until=[], inventory_complete=True)
    assert not journal_expiration_eligible(**{**args, "inventory_complete": False})
    assert not journal_expiration_eligible(**args, legal_hold=True)
    assert not journal_expiration_eligible(**{**args, "last_modified": modified.replace(tzinfo=None)})
