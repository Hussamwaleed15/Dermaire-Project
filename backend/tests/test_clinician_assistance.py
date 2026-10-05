from unittest.mock import Mock

import pytest

from app.models import DoctorPatientAccess, DoctorReviewAction
from app.services.contextual_ai import assist
from tests.test_account_deletion import deletion_context
from tests.test_contextual_ai import configured, plan, request, user
from tests.test_safety_engine import report


def decision(db, recommendation, *, sequence=1, visible=True):
    grant = db.query(DoctorPatientAccess).filter_by(patient_id='delete-patient').one()
    row = DoctorReviewAction(patient_id='delete-patient', doctor_id='delete-doctor',
        access_id=grant.id, sequence=sequence, state='reviewed',
        recommendation=recommendation, rationale='Private clinician rationale',
        patient_visible=visible, safety_snapshot={})
    db.add(row)
    db.commit()
    return row


@pytest.mark.parametrize('recommendation,screen', [
    ('doctor_review', None), ('urgent', None), ('urgent', {'pain': 'moderate'}),
])
def test_visible_clinician_guard_precedes_provider(deletion_context, configured, recommendation, screen):
    _, db, _ = deletion_context
    if screen:
        report(db, screen)
    row = decision(db, recommendation)
    provider = Mock()
    provider.generate.side_effect = AssertionError('Must not invoke provider')
    result = assist(db, user(db), request(), provider=provider)
    assert result.escalation == recommendation
    assert result.metadata.reason == 'clinician_precedence'
    assert result.metadata.mode == 'safety_guard' and not result.metadata.invoked
    assert result.authoritative_safety.status == ('doctor_review' if screen else 'track')
    assert result.authoritative_clinician.id == row.id
    assert result.authoritative_clinician.provenance == 'clinician_authored'
    assert 'Private clinician rationale' not in result.model_dump_json()
    provider.generate.assert_not_called()


@pytest.mark.parametrize('latest,visible', [(None, False), ('track', True), ('urgent', False)])
def test_current_review_does_not_resurrect_superseded_or_private_decisions(deletion_context, configured, latest, visible):
    _, db, _ = deletion_context
    decision(db, 'urgent')
    decision(db, latest, sequence=2, visible=visible)
    provider = Mock()
    provider.generate.side_effect = plan
    result = assist(db, user(db), request(), provider=provider)
    assert result.escalation == 'track' and result.authoritative_clinician is None
    assert result.metadata.mode == 'grounded_ai'
    assert 'Private clinician rationale' not in result.model_dump_json()
    provider.generate.assert_called_once()


@pytest.mark.parametrize('recommendation', ['track', 'doctor_review'])
def test_clinician_cannot_downgrade_urgent_engine(deletion_context, configured, recommendation):
    _, db, _ = deletion_context
    report(db, {'breathing_difficulty': True})
    decision(db, recommendation)
    provider = Mock()
    result = assist(db, user(db), request(), provider=provider)
    assert result.escalation == result.authoritative_safety.status == 'urgent'
    assert result.metadata.reason == 'safety_precedence'
    provider.generate.assert_not_called()


def test_clinician_guard_is_attributed_in_both_api_routes(deletion_context, configured):
    client, db, headers = deletion_context
    decision(db, 'urgent')
    response = client.post('/api/v1/assistance', headers=headers,
                           json={'message': 'What should I keep tracking?', 'task': 'tracking'})
    assert response.status_code == 200
    assert response.json()['authoritative_clinician']['recommendation'] == 'urgent'
    chat = client.post('/api/v1/chat', headers=headers,
                       json={'message': 'What should I keep tracking?', 'task': 'tracking'})
    assert chat.status_code == 200
    assert chat.json()['azure_model_used'] == 'Clinician review'
    assert chat.json()['escalation_triggered'] is True
