"""Focused PSM v2 integration, privacy, unknowns and longitudinal invariants."""
from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import pytest
from app.models import (User, Product, CheckIn, RoutineEntry, RoutineAdherence, Experiment,
                        ExperimentEvaluation, Capture, Measurement, ClinicalNote, DoctorReviewAction, DoctorPatientAccess)
from app.services.personal_skin_model import personal_skin_model
from app.services.measurement import SPECS
from app.services.azure_blob import azure_blob_service
from app.core.security import create_access_token
from tests.test_account_deletion import deletion_context


def view(db, owner='delete-patient'):
    return personal_skin_model(db, db.get(User, owner)).model_dump(mode='json')


def routine(db, owner='delete-patient', product='owned-product', days=10):
    now = datetime.now(timezone.utc)-timedelta(days=days)
    entry = RoutineEntry(user_id=owner, product_id=product, schedule='AM', frequency='daily',
        start_date=now.date(), active=True, created_at=now, updated_at=now)
    db.add(entry); db.commit()
    return entry


def log(db, entry, day, status='completed'):
    when = datetime.now(timezone.utc)-timedelta(days=day)
    row = RoutineAdherence(user_id=entry.user_id, routine_entry_id=entry.id, date=when.date(), slot='AM',
        status=status, created_at=when, configuration_snapshot={'product_id': entry.product_id,
        'schedule': 'AM', 'frequency': 'daily', 'active': True})
    db.add(row); db.commit()
    return row


def report(db, day=0, change='same', safety=None):
    when = datetime.now(timezone.utc)-timedelta(days=day)
    row = CheckIn(user_id='delete-patient', date_str=when.date().isoformat(), created_at=when,
        observation={'schema_version': 1, 'provenance': {'report': 'user_reported', 'created_at': 'server_recorded'},
                     'user_reported': {'overall_change': change, 'symptoms': [], 'safety': safety}})
    db.add(row); db.commit(); return row


def measurement(db, day, owner='delete-patient', quality=None, version='measurement-1.0', status='measured'):
    when = datetime.now(timezone.utc)-timedelta(days=day)
    quality = quality or {'version': 'quality-1.0', 'decision': 'accepted', 'checks': {'yaw': {'status': 'unknown'}}}
    capture = Capture(user_id=owner, received_at=when, state='accepted', source='upload', view='front',
        quality=quality, storage='not_persisted', server_version='quality-1.0')
    db.add(capture); db.flush()
    row = Measurement(user_id=owner, capture_id=capture.id, measured_at=when, status=status,
        algorithm_version=version, quality_reference=quality,
        results={key: {'status': status, 'value': .2, 'unit': spec[0], 'method_version': version} for key, spec in SPECS.items()},
        comparison={'state': 'comparable', 'deltas': {'invented': 99}, 'previous_measurement_id': 'foreign'})
    db.add(row); db.commit(); return row


def test_contract_no_data_and_read_only(deletion_context):
    client, db, auth = deletion_context
    before = {c: db.query(c).count() for c in (CheckIn, ExperimentEvaluation, Measurement)}
    result = client.get('/api/v1/personal-skin-model', headers=auth)
    assert result.status_code == 200
    result = result.json()
    assert result['schema_version'] == 2 and result['contract_version'] == 'personal-skin-model-2.0'
    assert result['status'] == 'no_data'
    assert result['sources']['measurements']['latest'] is None
    assert result['sources']['routine']['adherence']['completed_fraction'] is None
    assert result['sources']['safety']['status'] == 'track'
    assert result['unknowns'] and result['assistant_layer']['authoritative'] is False
    assert before == {c: db.query(c).count() for c in before}


def test_configured_vs_reported_and_historical_snapshot(deletion_context):
    _, db, _ = deletion_context
    entry = routine(db)
    log(db, entry, 2); log(db, entry, 1, 'skipped')
    data = view(db)['sources']['routine']
    assert len(data['configured']) == 1
    assert data['adherence']['expected_known_slots'] == 9
    assert data['adherence']['completed_slots'] == 1
    assert data['adherence']['unknown_slots'] == 7
    assert len(data['historical_snapshots']) == 2
    entry.active = False; entry.end_date = datetime.now(timezone.utc).date(); db.commit()
    data = view(db)['sources']['routine']
    assert data['configured'] == [] and len(data['historical_snapshots']) == 2
    assert view(db)['sources']['product_intelligence']['products'] == []


@pytest.mark.parametrize('status', ['inactive', 'archived'])
def test_inactive_products_not_current(deletion_context, status):
    _, db, _ = deletion_context
    entry = routine(db); log(db, entry, 1)
    product = db.get(Product, 'owned-product'); product.status = status; db.commit()
    result = view(db)
    assert result['sources']['routine']['configured'] == []
    assert result['sources']['product_intelligence']['products'] == []
    assert result['sources']['routine']['historical_snapshots']


def test_ingredient_unknown_and_explicit_sensitivity(deletion_context):
    _, db, _ = deletion_context
    routine(db)
    product = db.get(Product, 'owned-product'); product.active_ingredients = ['Retinol', 'Parfum']
    user = db.get(User, 'delete-patient'); user.profile_context = {'sensitivities_allergies': ['fragrance']}
    db.commit()
    result = view(db)
    pi = result['sources']['product_intelligence']
    assert pi['data_completeness'] == 'incomplete'
    assert all(i['concentration_state'] == 'unknown' for i in pi['products'][0]['ingredients'])
    assert all(i['category'] == 'patient_reported' for i in pi['products'][0]['ingredients'])
    assert any(w['key'] == 'disclosed_sensitivity_match' for w in pi['warnings'])
    assert result['sources']['safety']['status'] == 'doctor_review'


@pytest.mark.parametrize('profile', [None, {'sex': 'prefer_not_to_say', 'menstrual_context': 'prefer_not_to_say'},
    {'sex': 'female', 'hormonal_disclosure': 'disclosed', 'hormonal_context': ['private-hormone'], 'medications_treatments': ['secret-medication']}])
def test_sensitive_profile_omission(deletion_context, profile):
    _, db, _ = deletion_context
    user = db.get(User, 'delete-patient'); user.profile_context = profile; db.commit()
    result = str(view(db))
    assert all(word not in result for word in ('prefer_not_to_say', 'female', 'private-hormone', 'secret-medication'))


@pytest.mark.parametrize('status', ['measured', 'failed', 'unavailable', 'insufficient_quality'])
def test_unknown_measurement_dimensions_never_delta(deletion_context, status):
    _, db, _ = deletion_context
    measurement(db, 2); latest = measurement(db, 1, status=status)
    data = view(db)['sources']['measurements']
    assert data['latest']['id'] == latest.id
    assert data['trend_status'] == 'not_comparable'
    assert data['latest']['comparison']['deltas'] is None
    assert 'foreign' not in str(data) and 'invented' not in str(data)


def test_measurement_algorithm_and_owner_isolation(deletion_context):
    _, db, _ = deletion_context
    measurement(db, 2, owner='delete-doctor')
    current = measurement(db, 1, version='measurement-2.0')
    data = view(db)['sources']['measurements']['latest']
    assert data['algorithm_version'] == current.algorithm_version
    assert data['comparison']['previous_measurement_id'] is None


def test_stale_inputs_have_separate_freshness(deletion_context):
    _, db, _ = deletion_context
    entry = routine(db, days=30); log(db, entry, 20)
    measurement(db, 20); report(db, 20)
    data = view(db)
    assert data['status'] == 'stale'
    assert data['sources']['routine']['configured'][0]['freshness']['state'] == 'stale'
    assert data['sources']['routine']['adherence']['freshness']['state'] == 'stale'
    assert data['sources']['measurements']['trend_status'] == 'stale'
    assert not data['changing'] and not data['associations']


def test_urgent_safety_survives_lower_clinician_decision_and_internal_privacy(deletion_context):
    _, db, _ = deletion_context
    report(db, safety={'breathing_difficulty': True})
    grant = db.query(DoctorPatientAccess).first()
    row = DoctorReviewAction(patient_id='delete-patient', doctor_id='delete-doctor', access_id=grant.id,
        sequence=1, state='reviewed', recommendation='track', rationale='Visible conservative recommendation',
        patient_visible=True, safety_snapshot={})
    db.add(row)
    db.add(ClinicalNote(patient_id='delete-patient', doctor_id='delete-doctor', content='Visible recommendation', patient_visible=True))
    db.commit()
    data = view(db)
    assert data['safety']['status'] == data['sources']['safety']['status'] == data['summaries']['safety_status'] == 'urgent'
    assert data['sources']['doctor']['current_decision']['lower_than_current_safety'] is True
    assert 'Private medical note' not in str(data)
    assert 'Visible recommendation' in str(data)
    db.add(DoctorReviewAction(patient_id='delete-patient', doctor_id='delete-doctor', access_id=grant.id,
        sequence=2, state='follow_up_needed', rationale='INTERNAL-ONLY-RATIONALE', patient_visible=False, safety_snapshot={}))
    db.commit()
    data = view(db)
    assert data['sources']['doctor']['current_decision'] is None
    assert 'INTERNAL-ONLY-RATIONALE' not in str(data)
    assert data['sources']['doctor']['state'] == 'follow_up_needed'


@pytest.mark.parametrize('status', ['active', 'completed', 'stopped'])
def test_experiment_projection_whitelists_private_provenance(deletion_context, status):
    _, db, _ = deletion_context
    entry = routine(db)
    now = datetime.now(timezone.utc)-timedelta(days=1)
    experiment = Experiment(user_id='delete-patient', product_id=entry.product_id, routine_entry_id=entry.id,
        engine_version=2, source='user_configured', status=status, start_date=now, target_days=7,
        activated_at=now, active_owner='delete-patient' if status == 'active' else None,
        intervention={'type': 'start_entry', 'schedule': 'AM'},
        definition_snapshot={'baseline': {'start': '2026-09-01', 'end_exclusive': '2026-09-29'}, 'profile_context': {'private': 'SNAPSHOT-SECRET'}})
    db.add(experiment); db.flush()
    db.add(ExperimentEvaluation(user_id=experiment.user_id, experiment_id=experiment.id, result={
        'engine_version': 2, 'label': 'likely_associated_improvement', 'evidence_strength': 'limited',
        'comparison': {'baseline_days': 5, 'experiment_days': 7}, 'provenance': {'private': 'EVALUATION-SECRET'},
        'confounders': {'cycle_context_days': 8, 'unusual_days': 1}}))
    db.commit()
    data = view(db)
    item = data['sources']['experiments'][0]
    assert item['status'] == status and item['change_type'] == 'start_entry'
    assert item['evaluation']['evidence_count'] == 12
    assert item['evaluation']['label'] == 'likely_associated_improvement'
    assert 'association' in item['evaluation']['statement']
    assert all(s not in str(data) for s in ('SNAPSHOT-SECRET', 'EVALUATION-SECRET', 'cycle_context_days'))


def test_adherence_association_explicit_evidence_and_no_cause(deletion_context):
    _, db, _ = deletion_context
    entry = routine(db)
    for day in range(1, 7):
        log(db, entry, day, 'completed' if day <= 3 else 'skipped')
        report(db, day, 'worse' if day <= 3 else 'same')
    data = view(db)
    finding = next(f for f in data['associations'] if f['code'] == 'adherence_association')
    assert finding['confidence'] == finding['strength'] == 'limited'
    assert finding['evidence_count'] == 12
    assert finding['latest_evidence_at'] and finding['caveats']
    assert {e['source'] for e in finding['evidence']} == {'adherence', 'checkin'}
    assert 'does not establish cause' in finding['statement']


def test_ai_inference_cannot_create_canonical_facts(deletion_context, monkeypatch):
    _, db, _ = deletion_context
    row = db.query(CheckIn).first()
    row.ai_vision_analysis = {'skin_type': 'AI-SECRET', 'overall_change': 'better', 'diagnosis': 'AI-DIAGNOSIS'}
    db.commit()
    # If invoked, this fails: canonical PSM does not request assistant/provider output.
    monkeypatch.setattr('app.services.contextual_ai.assist', Mock(side_effect=AssertionError('AI invoked')))
    data = view(db)
    assert data['status'] == 'no_data'
    assert 'AI-SECRET' not in str(data) and 'AI-DIAGNOSIS' not in str(data)
    assert data['assistant_layer']['included'] is False


def test_integrated_foreign_isolation_and_deleted_session(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    entry = routine(db); log(db, entry, 1); measurement(db, 1)
    db.add(ClinicalNote(patient_id='delete-patient', doctor_id='delete-doctor', content='OWNER-ONLY-VISIBLE', patient_visible=True)); db.commit()
    foreign_auth = {'Authorization': 'Bearer '+create_access_token('delete-doctor', 'doctor', hashed_password='unused')}
    foreign = client.get('/api/v1/personal-skin-model', headers=foreign_auth).json()
    assert foreign['sources']['routine']['configured'] == []
    assert foreign['sources']['measurements']['latest'] is None
    assert 'OWNER-ONLY-VISIBLE' not in str(foreign)
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock())
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    assert client.delete('/api/v1/users/me', headers=auth).status_code == 204
    assert client.get('/api/v1/personal-skin-model', headers=auth).status_code == 401
    assert db.query(RoutineAdherence).count() == db.query(Measurement).count() == 0

def test_future_sources_and_unknown_adherence_cannot_form_association(deletion_context):
    _, db, _ = deletion_context
    entry = routine(db)
    for day in range(1, 7):
        report(db, day, 'worse' if day < 4 else 'same')
    future = log(db, entry, 1)
    future.created_at = datetime.now(timezone.utc)+timedelta(days=1)
    db.commit()
    data = view(db)
    assert not data['associations']
    assert data['sources']['routine']['historical_snapshots'] == []
    assert data['sources']['routine']['adherence']['completed_slots'] == 0


def test_conflicting_reports_do_not_create_directional_finding(deletion_context):
    _, db, _ = deletion_context
    for day in range(1, 7):
        report(db, day, 'worse' if day % 2 else 'better')
    data = view(db)
    assert not data['changing'] and not data['stable']
    assert data['status'] == 'insufficient_data'
    assert data['sources']['safety']['status'] == 'doctor_review'


def test_legacy_ai_and_external_provider_are_not_measurement_evidence(deletion_context):
    _, db, _ = deletion_context
    row = db.query(CheckIn).first()
    row.hydration_score = row.redness_score = row.texture_score = 80
    row.ai_vision_analysis = {'measurement_source': 'external_llm', 'confidence': 1}
    db.commit()
    data = view(db)
    assert data['status'] == 'no_data' and data['sources']['measurements']['latest'] is None


def test_valid_measurement_comparison_and_latest_failure(deletion_context):
    _, db, _ = deletion_context
    checks = {k: {'status': 'pass'} for k in ('yaw', 'pitch', 'occlusion', 'uneven_lighting')}
    for check, values in {'scale': {'face_width_fraction': .5}, 'roll': {'degrees': 0},
        'exposure': {'dark_clipped_fraction': .01, 'bright_clipped_fraction': .01},
        'framing': {'center_offset_x': 0, 'center_offset_y': 0},
        'sharpness': {'laplacian_variance': 100}}.items():
        checks[check] = {'status': 'pass', 'metrics': values}
    quality = {'version': 'future-test-quality', 'decision': 'accepted', 'checks': checks}
    measurement(db, 3, quality=quality)
    current = measurement(db, 2, quality=quality)
    data = view(db)['sources']['measurements']
    assert data['trend_status'] == 'comparable'
    assert all(d['value'] == 0 for d in data['latest']['comparison']['deltas'].values())
    measurement(db, 1, status='failed')
    data = view(db)['sources']['measurements']
    assert data['latest']['status'] == 'failed' and data['latest_measured']['id'] == current.id
    assert data['latest']['comparison']['deltas'] is None


def test_measurement_only_is_evidence_not_no_data(deletion_context):
    _, db, _ = deletion_context
    measurement(db, 1)
    data = view(db)
    assert data['status'] == 'insufficient_data'
    assert data['sufficiency']['proxy_measurement_days'] == 1
    assert data['sufficiency']['latest_proxy_measurement_at'] is not None
    assert data['sources']['measurements']['trend_status'] == 'not_comparable'
    assert data['strength'] == 'none'


def test_stale_experiment_learning_remains_historical(deletion_context):
    _, db, _ = deletion_context
    entry = routine(db, days=30)
    now = datetime.now(timezone.utc)-timedelta(days=20)
    experiment = Experiment(user_id='delete-patient', product_id=entry.product_id, routine_entry_id=entry.id,
        engine_version=2, source='user_configured', status='completed', start_date=now, target_days=7,
        intervention={'type': 'start_entry', 'schedule': 'AM'})
    db.add(experiment); db.flush()
    db.add(ExperimentEvaluation(user_id=experiment.user_id, experiment_id=experiment.id, created_at=now,
        result={'engine_version': 2, 'label': 'no_meaningful_change', 'evidence_strength': 'limited'}))
    db.commit()
    data = view(db)
    assert data['sources']['experiments'][0]['evaluation']['freshness']['state'] == 'stale'
    assert data['sources']['experiments'][0]['evaluation']['evidence_count'] is None
    assert data['summaries']['experiment_learnings'] == []


def test_backfilled_measurement_does_not_refresh_old_capture(deletion_context):
    _, db, _ = deletion_context
    row = measurement(db, 20)
    row.measured_at = datetime.now(timezone.utc)
    db.commit()
    data = view(db)
    assert data['status'] == 'stale'
    assert data['sources']['measurements']['freshness']['state'] == 'stale'
    assert data['sources']['measurements']['latest_measured']['freshness']['state'] == 'stale'
