from datetime import datetime, timedelta, timezone

import pytest

from app.core.operational_targets import (
    journal_expiration_eligible, validate_recovery_horizon,
    RecoverableSource, journal_key_expiration_eligible,
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
    args = dict(last_modified=modified, now=now, inventory_complete=True, sources=[], expiration_enabled=True)
    assert journal_expiration_eligible(**args, recoverable_until=[now])
    assert not journal_expiration_eligible(**args, recoverable_until=[now, now + timedelta(seconds=1)])
    assert not journal_expiration_eligible(**{**args, "now": now - timedelta(seconds=1)},
                                           recoverable_until=[])
    # A later export/restored target can outlive the normal 35-day backup horizon.
    assert not journal_expiration_eligible(**args, recoverable_until=[now + timedelta(days=90)])


def test_unknown_inventory_hold_and_naive_dates_fail_closed():
    modified = datetime(2026, 1, 1, tzinfo=timezone.utc)
    args = dict(last_modified=modified, now=modified + timedelta(days=100),
                recoverable_until=[], inventory_complete=True, sources=[], expiration_enabled=True)
    assert not journal_expiration_eligible(**{**args, "inventory_complete": False})
    assert not journal_expiration_eligible(**args, legal_hold=True)
    assert not journal_expiration_eligible(**{**args, "last_modified": modified.replace(tzinfo=None)})


@pytest.mark.parametrize("source", [
    RecoverableSource(),
    RecoverableSource("unknown", 7, 7, False),
    RecoverableSource("production-derived", None, 7, False),
    RecoverableSource("production-derived", 7, None, False),
    RecoverableSource("production-derived", 7, 7, None),
    RecoverableSource("production-derived", 7, 7, True),
    RecoverableSource("production-derived", 36, 0, False),
    RecoverableSource("production-derived", 35, 8, False),
])
def test_any_unsafe_source_blocks_intent_and_key_even_after_century(source):
    modified = datetime(2026, 1, 1, tzinfo=timezone.utc)
    args = dict(last_modified=modified, now=modified + timedelta(days=36500),
                inventory_complete=True, recoverable_until=[], expiration_enabled=True,
                sources=[RecoverableSource("production-derived", 35, 7, False), source])
    assert not journal_expiration_eligible(**args)
    assert not journal_key_expiration_eligible(**args, retained_signed_intents=False)


def test_expiration_disabled_by_default_and_missing_source_evidence_denied():
    modified = datetime(2026, 1, 1, tzinfo=timezone.utc)
    args = dict(last_modified=modified, now=modified + timedelta(days=100),
                inventory_complete=True, recoverable_until=[])
    assert not journal_expiration_eligible(**args, sources=[])
    assert not journal_key_expiration_eligible(**args, sources=[], retained_signed_intents=False)
    assert not journal_expiration_eligible(**args, expiration_enabled=True)
    args.update(expiration_enabled=True, sources=[RecoverableSource("production-derived", 35, 7, False)])
    assert journal_expiration_eligible(**args)
    assert not journal_key_expiration_eligible(**args, retained_signed_intents=True)
    assert not journal_key_expiration_eligible(**args, retained_signed_intents=None)
    assert journal_key_expiration_eligible(**args, retained_signed_intents=False)


def test_committed_legacy_inventory_blocks_even_future_expiry_review():
    import json
    from pathlib import Path
    inventory = json.loads((Path(__file__).resolve().parents[2] /
                            "docs/legacy-recoverable-sources.json").read_text(encoding="utf-8"))
    assert inventory["journal_expiration_enabled"] is False
    assert inventory["key_expiration_enabled"] is False
    sources = [RecoverableSource(r["provenance"], r["retention_days"],
                                 r["quarantine_days"], r["legal_hold"])
               for r in inventory["records"]]
    modified = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert not journal_expiration_eligible(last_modified=modified,
        now=modified + timedelta(days=36500), recoverable_until=[],
        inventory_complete=True, sources=sources, expiration_enabled=True)
