from datetime import datetime, timedelta, timezone
import jwt
import pytest
from app.core.config import settings
from app.models import User, RoutineAdherence, Product, RoutineEntry
from app.services.personal_skin_model import personal_skin_model
from app.services.adherence_history import page
from tests.test_account_deletion import deletion_context
from tests.test_routine_model import create
from tests.test_h4_history_freshness import history_rows
from tests.test_personal_skin_model import add, measured, NOW
from tests.test_postgres_gate import pg_engine, seed


@pytest.mark.parametrize('extra_seconds,expected', [(0, 'fresh'), (1, 'stale')])
def test_psm_elapsed_freshness_matches_sufficiency(deletion_context, extra_seconds, expected):
    _, db, _ = deletion_context
    row = add(db, 14, score=50)
    row.created_at = NOW - timedelta(days=14, seconds=extra_seconds)
    db.commit()
    model = personal_skin_model(db, db.get(User, 'delete-patient'), NOW)
    assert model.sufficiency.recency == expected
    assert model.sufficiency.freshness.state == expected
    assert model.sufficiency.freshness.as_of == NOW
    assert model.sufficiency.age_days == 14
    assert model.source_read_consistency == 'multiple_reads_not_atomic_snapshot'
    if expected == 'stale':
        assert model.status == 'stale' and not model.changing


def test_finding_reports_reference_range_without_claiming_all_fresh(deletion_context):
    _, db, _ = deletion_context
    measured(db, 70)
    model = personal_skin_model(db, db.get(User, 'delete-patient'), NOW)
    for finding in model.changing:
        assert finding.freshness_basis == 'latest_referenced_evidence'
        assert finding.earliest_evidence_at == min(e.recorded_at for e in finding.evidence)
        assert finding.latest_evidence_at == max(e.recorded_at for e in finding.evidence)


@pytest.mark.parametrize('fault', ['naive_cutoff','naive_position','future_position','extended_expiry','string_expiry'])
def test_signed_malformed_cursor_is_rejected(deletion_context, fault):
    client, db, auth = deletion_context
    entry = create(client, auth).json(); history_rows(db, entry['id'])
    path='/api/v1/routine/adherence/history'
    token=client.get(path, params={'limit':2}, headers=auth).json()['next_cursor']
    state=jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    if fault == 'naive_cutoff': state['as_of']=datetime.fromisoformat(state['as_of']).replace(tzinfo=None).isoformat()
    if fault == 'naive_position': state['before_at']=datetime.fromisoformat(state['before_at']).replace(tzinfo=None).isoformat()
    if fault == 'future_position': state['before_at']=(datetime.fromisoformat(state['as_of'])+timedelta(seconds=1)).isoformat()
    if fault == 'extended_expiry': state['exp']+=60
    if fault == 'string_expiry': state['exp']=str(state['exp'])
    malformed=jwt.encode(state, settings.SECRET_KEY, algorithm=settings.ALGORITHM)
    assert client.get(path, params={'cursor':malformed}, headers=auth).status_code == 422


def test_pg_history_erasure_and_backdated_commit_are_not_snapshot(pg_engine):
    factory=seed(pg_engine)
    with factory() as db:
        db.add(Product(id='p',user_id='owner',name='Synthetic'));db.commit()
        db.add(RoutineEntry(id='entry',user_id='owner',product_id='p',schedule='AM',frequency='daily',start_date=NOW.date()))
        db.commit();history_rows(db,'entry','owner')
        first=page(db,db.get(User,'owner'),2)
        at=db.get(RoutineAdherence,'history-0').created_at
    with factory() as writer:
        writer.query(RoutineAdherence).filter_by(id='history-1').delete()
        writer.add(RoutineAdherence(id='history-15',user_id='owner',routine_entry_id='entry',date=NOW.date()-timedelta(days=9),
            slot='AM',status='completed',created_at=at,configuration_snapshot={}))
        writer.commit()
    with factory() as reader:
        second=page(reader,reader.get(User,'owner'),2,first.next_cursor)
        assert [r.id for r in second.items] == ['history-15','history-0']
        assert second.as_of == first.as_of
        assert second.consistency == 'append_only_keyset_cutoff_not_atomic_snapshot'
