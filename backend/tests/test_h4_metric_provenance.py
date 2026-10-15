from copy import deepcopy
from app.models import ExperimentEvaluation, CheckIn
from app.schemas.experiments import EvaluationResult
from tests.test_experiment_engine_v2 import context, active, collect, result
from tests.test_account_deletion import deletion_context


def test_metric_contract_is_frozen_and_legacy_is_unknown(context, monkeypatch):
    client, db, auth, _ = context
    row = active(context)
    collect(context, row, monkeypatch)
    saved = result(context, row)
    contract = saved['metric_contract']
    assert contract['unit'] == 'score_0_to_100' and contract['delta_unit'] == 'score_points'
    assert contract['source'] == 'manual' and contract['direction'] == 'higher_is_better'
    assert contract['measurement_algorithm_versions'] == []
    assert contract['measurement_algorithm_provenance'] == 'missing'
    for check in db.query(CheckIn).filter_by(user_id='delete-patient'):
        check.ai_vision_analysis = {'measurement_source': 'manual', 'measurement_algorithm_version': 'later'}
    db.commit()
    stored = db.query(ExperimentEvaluation).filter_by(experiment_id=row['id']).one()
    assert stored.result == saved
    legacy = deepcopy(saved); legacy.pop('metric_contract')
    assert EvaluationResult.model_validate(legacy).metric_contract is None
    assert client.get('/api/v1/experiments/'+row['id']+'/results', headers=auth).json()[0]['result'] == saved


def test_mixed_image_versions_cannot_support_directional_label(context, monkeypatch):
    _, db, _, _ = context
    for check in db.query(CheckIn).filter_by(user_id='delete-patient'):
        check.ai_vision_analysis = {'measurement_source': 'image_proxy', 'measurement_algorithm_version': 'old'}
    db.commit()
    row = active(context)
    collect(context, row, monkeypatch, score=70, source='image_proxy')
    for check in db.query(CheckIn).filter_by(user_id='delete-patient'):
        if check.ai_vision_analysis.get('measurement_source') == 'image_proxy':
            check.ai_vision_analysis = {'measurement_source': 'image_proxy', 'measurement_algorithm_version': 'new'}
    db.commit()
    saved = result(context, row)
    assert saved['metric_contract']['measurement_algorithm_provenance'] == 'mixed'
    assert saved['metric_contract']['measurement_algorithm_versions'] == ['new', 'old']
    assert saved['label'] == 'insufficient_evidence'
