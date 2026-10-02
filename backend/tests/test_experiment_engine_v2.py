from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import Mock
import sqlite3
import pytest
from app.models import (Experiment, ExperimentEvaluation, Product, RoutineEntry,
                        RoutineAdherence, CheckIn, DailyContext, User)
from app.core.security import create_access_token
from app.services import experiments as service
from tests.test_account_deletion import deletion_context

ROOT = '/api/v1/experiments'

@pytest.fixture
def context(deletion_context):
    client, db, auth = deletion_context
    db.get(Experiment, 'owned-experiment').status = 'completed'
    db.commit()
    day = service.today()
    for i in range(1, 6):
        db.add(CheckIn(user_id='delete-patient', date_str=(day-timedelta(days=i)).isoformat(),
            created_at=datetime.combine(day-timedelta(days=i), datetime.min.time()),
            hydration_score=50, redness_score=50, texture_score=50,
            ai_vision_analysis={'measurement_source':'manual'}))
    db.commit()
    response = client.post('/api/v1/routine/entries', headers=auth, json={
        'product_id':'owned-product', 'schedule':'AM', 'frequency':'daily', 'start_date':day.isoformat()})
    assert response.status_code == 201
    payload = dict(routine_entry_id=response.json()['id'], start_date=day.isoformat(), target_days=7,
                   primary_concern='texture', goal='Observe my texture score', intervention={'type':'start_entry', 'schedule':'AM'})
    return client, db, auth, payload

def draft(context, **changes):
    client, _, auth, payload = context
    return client.post(ROOT, headers=auth, json={**payload, **changes})

def active(context, **changes):
    client, db, auth, _ = context
    response = draft(context, **changes)
    assert response.status_code == 201, response.text
    identifier = response.json()['id']
    response = client.post(f'{ROOT}/{identifier}/activate', headers=auth)
    assert response.status_code == 200, response.text
    return response.json()

def collect(context, row, monkeypatch, score=50, followed=True, unusual=False, days=7, source='manual', context_known=True):
    _, db, _, _ = context
    exp = db.get(Experiment, row['id'])
    start = exp.start_date.date()
    expected = exp.definition_snapshot['expected']
    for i in range(days):
        day = start + timedelta(days=i)
        timestamp = exp.activated_at + timedelta(days=i, minutes=1)
        db.add(CheckIn(user_id=exp.user_id, date_str=day.isoformat(), created_at=timestamp,
            hydration_score=score, redness_score=score, texture_score=score,
            ai_vision_analysis={'measurement_source':source}, observation={
                'schema_version':1, 'user_reported':{'overall_change':'same', 'routine_status':'followed'}}))
        for slot in ('AM', 'PM') if expected['schedule'] == 'BOTH' else (expected['schedule'],):
            status = 'skipped' if exp.intervention['type'] == 'stop_entry' else 'completed'
            db.add(RoutineAdherence(user_id=exp.user_id, routine_entry_id=exp.routine_entry_id,
                date=day, slot=slot, status=status if followed else ('skipped' if status == 'completed' else 'completed'),
                created_at=timestamp, configuration_snapshot=expected))
        db.add(DailyContext(user_id=exp.user_id, date=day, unusual_conditions=unusual if context_known else None))
    db.commit()
    monkeypatch.setattr(service, 'today', lambda: start + timedelta(days=days))
    monkeypatch.setattr(service, 'now', lambda: datetime.combine(start + timedelta(days=days), datetime.min.time()))

def result(context, row):
    client, _, auth, _ = context
    response = client.post(f"{ROOT}/{row['id']}/evaluate", headers=auth)
    assert response.status_code == 201, response.text
    return response.json()['result']

def test_draft_activation_and_frozen_definition(context):
    client, db, auth, _ = context
    response = draft(context)
    assert response.status_code == 201
    row = response.json()
    assert row['status'] == 'draft' and row['source'] == 'user_configured'
    path = f"{ROOT}/{row['id']}"
    assert client.get(path, headers=auth).json() == row
    assert client.patch(path, headers=auth, json={'notes':'Draft note'}).status_code == 200
    row = client.post(path+'/activate', headers=auth).json()
    assert row['status'] == 'active' and row['definition_snapshot']['before']['schedule'] == 'AM'
    assert len(row['definition_snapshot']['baseline']['checkins']) == 5
    assert client.post(path+'/activate', headers=auth).status_code == 409
    assert client.patch(path, headers=auth, json={'notes':'Rewrite history'}).status_code == 409
    assert client.patch(path, headers=auth, json={'intervention':{'type':'stop_entry'}}).status_code == 422
    assert client.get(path+'/results', headers=auth).json() == []

@pytest.mark.parametrize('change', [
    {'intervention':[{'type':'stop_entry'},{'type':'start_entry','schedule':'AM'}]},
    {'intervention':{'type':'medical_treatment'}}, {'intervention':{'type':'stop_entry','schedule':'AM'}},
    {'intervention':{'type':'start_entry'}}, {'intervention':{'type':'change_schedule','schedule':'PM','secondary':'other'}},
    {'product_id':'owned-product'}, {'routine_entry_id':''}, {'target_days':True}, {'target_days':6},
    {'start_date':'2020-01-01'}, {'goal':''}, {'source':'system'}, {'status':'active'},
])
def test_invalid_definitions_no_partial_persistence(context, change):
    _, db, _, _ = context
    assert draft(context, **change).status_code == 422
    assert db.query(Experiment).filter_by(engine_version=2).count() == 0
    assert db.get(Product, 'owned-product').in_experiment is False

def test_owned_references_and_auth_isolation(context):
    client, db, auth, payload = context
    other = {'Authorization':'Bearer '+create_access_token('delete-doctor','doctor',hashed_password='unused')}
    assert draft(context, routine_entry_id='missing').status_code == 404
    assert client.post(ROOT, headers=other, json=payload).status_code == 404
    row = active(context)
    path = f"{ROOT}/{row['id']}"
    for suffix in ('', '/results'):
        assert client.get(path+suffix, headers=other).status_code == 404
    for suffix in ('/activate','/evaluate','/finish'):
        assert client.post(path+suffix, headers=other, json={'status':'stopped'} if suffix == '/finish' else None).status_code == 404
    assert client.get(ROOT, headers=other).json() == []
    assert client.get(ROOT).status_code == 401
    # Even an inconsistent cross-account routine/product link cannot activate.
    db.add(Product(id='foreign',user_id='delete-doctor',name='Other')); db.commit()
    db.get(RoutineEntry,payload['routine_entry_id']).product_id = 'foreign'; db.commit()
    assert draft(context).status_code == 404

def test_one_active_and_legacy_conflicts(context):
    client, db, auth, _ = context
    row = active(context)
    second = draft(context).json()
    assert client.post(f"{ROOT}/{second['id']}/activate", headers=auth).status_code == 409
    assert db.query(Experiment).filter_by(active_owner='delete-patient').count() == 1
    assert client.post(f"{ROOT}/{row['id']}/finish", headers=auth,json={'status':'stopped'}).status_code == 200
    db.get(Experiment,'owned-experiment').status='paused'; db.commit()
    assert client.post(f"{ROOT}/{second['id']}/activate", headers=auth).status_code == 409

def test_history_and_lifecycle(context):
    client, db, auth, _ = context
    row = active(context)
    path = f"{ROOT}/{row['id']}"
    snapshot = row['definition_snapshot']
    assert client.post(path+'/finish',headers=auth,json={'status':'completed'}).status_code == 409
    assert client.post(path+'/finish',headers=auth,json={'status':'cancelled'}).status_code == 409
    assert client.delete(path,headers=auth).status_code == 200
    stopped = client.get(path,headers=auth).json()
    assert stopped['status']=='stopped' and stopped['definition_snapshot']==snapshot
    assert db.get(Experiment,row['id']).active_owner is None
    assert result(context,row)['label']=='insufficient_evidence'
    planned = draft(context).json()
    assert client.delete(f"{ROOT}/{planned['id']}",headers=auth).json()['status']=='cancelled'
    assert client.post(f"{ROOT}/{planned['id']}/evaluate",headers=auth).status_code == 409

@pytest.mark.parametrize('score,metric,label', [
    (50,'texture','no_meaningful_change'), (65,'texture','likely_associated_improvement'),
    (35,'texture','likely_associated_worsening'), (35,'redness','likely_associated_improvement'),
    (65,'redness','likely_associated_worsening'), (65,'hydration','likely_associated_improvement')])
def test_observation_results_and_provenance(context, monkeypatch, score, metric, label):
    row = active(context, primary_concern=metric)
    collect(context,row,monkeypatch,score=score)
    output = result(context,row)
    assert output['label']==label
    assert output['comparison']['baseline_days']==5 and output['comparison']['experiment_days']==7
    assert output['provenance']['algorithm']=='experiment_v2_rules_1'
    assert len(output['provenance']['experiment_checkins'])==7
    assert len(output['provenance']['adherence'])==7 and len(output['provenance']['contexts'])==7
    assert output['evidence_strength']=='limited' and output['evaluated_at']
    if label.startswith('likely'):
        assert 'not evidence' in output['evidence_summary'] and 'association' in output['evidence_summary']
    client,db,auth,_ = context
    path = f"{ROOT}/{row['id']}"
    assert client.post(path+'/finish',headers=auth,json={'status':'completed'}).status_code==200
    assert client.get(path,headers=auth).json()['result']['result']==output
    db.query(DailyContext).filter_by(user_id='delete-patient').update({'unusual_conditions':True}); db.commit()
    changed = result(context,row)
    assert changed['label']=='confounded_or_low_adherence'
    assert len(client.get(path+'/results',headers=auth).json())==2
    assert client.get(path+'/results',headers=auth).json()[1]['result']==output

@pytest.mark.parametrize('options', [{'days':3},{'source':'image_proxy'},{'days':0}])
def test_insufficient_and_source_consistency(context, monkeypatch, options):
    row=active(context)
    collect(context,row,monkeypatch,score=70,**options)
    assert result(context,row)['label']=='insufficient_evidence'

@pytest.mark.parametrize('options', [{'followed':False},{'unusual':True},{'context_known':False}])
def test_adherence_and_context_gate(context, monkeypatch, options):
    row=active(context)
    collect(context,row,monkeypatch,score=70,**options)
    assert result(context,row)['label']=='confounded_or_low_adherence'

def test_inconsistent_scores_and_reports(context, monkeypatch):
    row=active(context)
    collect(context,row,monkeypatch,score=65)
    _,db,_,_=context
    checks=db.query(CheckIn).filter(CheckIn.created_at>=db.get(Experiment,row['id']).activated_at).all()
    for c in checks[:3]: c.texture_score=20
    db.commit()
    assert result(context,row)['label']=='insufficient_evidence'
    for c in checks: c.texture_score=65
    checks[0].observation={'user_reported':{'overall_change':'worse'}}; db.commit()
    assert result(context,row)['label']=='insufficient_evidence'

def test_schedule_and_stop_adherence_semantics(context, monkeypatch):
    client,db,auth,payload=context
    assert draft(context, intervention={'type':'change_schedule','schedule':'AM'}).status_code==422
    row=active(context, intervention={'type':'change_schedule','schedule':'BOTH'})
    assert db.get(RoutineEntry,payload['routine_entry_id']).schedule=='BOTH'
    collect(context,row,monkeypatch,score=65)
    assert result(context,row)['adherence']['expected_slots']==14

def test_stop_accepts_only_explicit_skipped_use(context, monkeypatch):
    client,db,auth,payload=context
    row=active(context,intervention={'type':'stop_entry'})
    assert not db.get(RoutineEntry,payload['routine_entry_id']).active
    report=dict(routine_entry_id=payload['routine_entry_id'],date=payload['start_date'],slot='AM',status='completed')
    assert client.post('/api/v1/routine/adherence',headers=auth,json=report).status_code==409
    report['status']='skipped'
    assert client.post('/api/v1/routine/adherence',headers=auth,json=report).status_code==201
    # Use the real accepted report rather than duplicate it in the fixture.
    db.query(RoutineAdherence).delete(); db.commit()
    collect(context,row,monkeypatch,score=65)
    output=result(context,row)
    assert output['label']=='likely_associated_improvement' and output['adherence']['expected_status']=='skipped'

def test_guarded_configuration_and_reference_history(context):
    client,db,auth,payload=context
    row=active(context)
    path='/api/v1/routine/entries/'+payload['routine_entry_id']
    assert client.patch(path,headers=auth,json={'instructions':'new'}).status_code==409
    assert client.delete(path,headers=auth).status_code==409
    assert client.patch('/api/v1/products/owned-product',headers=auth,json={'status':'archived'}).status_code==409
    assert client.delete('/api/v1/products/owned-product',headers=auth).status_code==409
    client.post(f"{ROOT}/{row['id']}/finish",headers=auth,json={'status':'stopped'})
    assert client.patch('/api/v1/products/owned-product',headers=auth,json={'status':'archived'}).status_code==200
    assert client.get(f"{ROOT}/{row['id']}",headers=auth).json()['definition_snapshot']==row['definition_snapshot']

def test_account_deletion_and_session_cleanup(context, monkeypatch):
    client,db,auth,_=context
    row=active(context)
    result(context,row)
    from app.services.azure_blob import azure_blob_service
    monkeypatch.setattr(azure_blob_service,'delete_image',Mock())
    assert client.delete('/api/v1/users/me',headers=auth).status_code==204
    assert db.query(ExperimentEvaluation).count()==0 and db.query(Experiment).count()==0
    assert client.get(ROOT,headers=auth).status_code==401
    assert client.post(f"{ROOT}/{row['id']}/evaluate",headers=auth).status_code==401

def test_failed_writes_rollback_activation_and_evaluation(context, monkeypatch):
    client,db,auth,_=context
    row=draft(context,intervention={'type':'change_schedule','schedule':'PM'}).json()
    original=db.commit
    monkeypatch.setattr(db,'commit',Mock(side_effect=RuntimeError('unavailable')))
    assert client.post(f"{ROOT}/{row['id']}/activate",headers=auth).status_code==503
    assert db.get(Experiment,row['id']).status=='draft'
    assert db.get(RoutineEntry,row['routine_entry_id']).schedule=='AM'
    monkeypatch.setattr(db,'commit',original)
    assert client.post(f"{ROOT}/{row['id']}/activate",headers=auth).status_code==200
    monkeypatch.setattr(db,'commit',Mock(side_effect=RuntimeError('unavailable')))
    assert client.post(f"{ROOT}/{row['id']}/evaluate",headers=auth).status_code==503
    assert db.query(ExperimentEvaluation).count()==0

def test_future_activation_and_draft_replacement(context):
    client,db,auth,payload=context
    future={**payload,'start_date':(service.today()+timedelta(days=1)).isoformat(),
            'intervention':{'type':'change_schedule','schedule':'PM'}}
    row=client.post(ROOT,headers=auth,json=future).json()
    path=f"{ROOT}/{row['id']}"
    assert client.post(path+'/activate',headers=auth).status_code==422
    assert client.patch(path,headers=auth,json={'definition':payload}).status_code==200
    assert client.post(path+'/activate',headers=auth).status_code==200

def test_baseline_values_remain_frozen(context, monkeypatch):
    row=active(context)
    collect(context,row,monkeypatch,score=65)
    _,db,_,_=context
    exp=db.get(Experiment,row['id'])
    db.query(CheckIn).filter(CheckIn.created_at<exp.start_date).update({'texture_score':90}); db.commit()
    output=result(context,row)
    assert output['observed_change']['baseline_mean']==50
    assert output['label']=='likely_associated_improvement'

@pytest.mark.parametrize('reason',['stale_prior','sparse_window','baseline_context'])
def test_additional_quality_gates(context,monkeypatch,reason):
    _,db,_,_=context
    if reason=='stale_prior':
        for c in db.query(CheckIn).filter(CheckIn.hydration_score.is_not(None)):
            c.created_at-=timedelta(days=14)
        db.commit()
    if reason=='baseline_context':
        db.add(DailyContext(user_id='delete-patient',date=service.today()-timedelta(days=1),unusual_conditions=True)); db.commit()
    row=active(context,target_days=28 if reason=='sparse_window' else 7)
    collect(context,row,monkeypatch,score=65,days=28 if reason=='sparse_window' else 7)
    if reason=='sparse_window':
        exp=db.get(Experiment,row['id'])
        db.query(CheckIn).filter(CheckIn.created_at>=exp.activated_at,
            CheckIn.created_at<exp.activated_at+timedelta(days=23)).delete(); db.commit()
    assert result(context,row)['label']==('confounded_or_low_adherence' if reason=='baseline_context' else 'insufficient_evidence')

def test_database_uniqueness_protects_active_owner(context):
    from sqlalchemy.exc import IntegrityError
    _,db,_,_=context
    row=active(context)
    exp=db.get(Experiment,row['id'])
    duplicate=Experiment(user_id=exp.user_id,engine_version=2,status='active',source=exp.source,
        product_id=exp.product_id,routine_entry_id=exp.routine_entry_id,intervention=exp.intervention,
        activated_at=exp.activated_at,definition_snapshot=exp.definition_snapshot,active_owner=exp.user_id)
    db.add(duplicate)
    with pytest.raises(IntegrityError): db.commit()
    db.rollback()
    assert db.query(Experiment).filter_by(active_owner=exp.user_id).count()==1

def test_activation_slot_conflict_rolls_back_entire_change(context):
    client,db,auth,payload=context
    assert client.post('/api/v1/routine/entries',headers=auth,json={
        'product_id':'owned-product','schedule':'PM','frequency':'daily','start_date':payload['start_date']}).status_code==201
    row=draft(context,intervention={'type':'change_schedule','schedule':'BOTH'}).json()
    assert client.post(f"{ROOT}/{row['id']}/activate",headers=auth).status_code==409
    assert db.get(Experiment,row['id']).status=='draft'
    assert db.get(Experiment,row['id']).definition_snapshot is None
    assert db.get(RoutineEntry,payload['routine_entry_id']).schedule=='AM'
    assert db.get(Product,'owned-product').in_experiment is False

def test_sqlite_upgrade_preserves_legacy(tmp_path):
    conn=sqlite3.connect(tmp_path/'upgrade.db')
    conn.executescript('CREATE TABLE users(id VARCHAR(36) PRIMARY KEY); CREATE TABLE routine_entries(id VARCHAR(36) PRIMARY KEY); CREATE TABLE experiments(id VARCHAR(36) PRIMARY KEY, user_id VARCHAR(36), status VARCHAR(50), product_id VARCHAR(36), target_days INTEGER); INSERT INTO users VALUES (\'owner\'); INSERT INTO experiments VALUES (\'legacy\',\'owner\',\'active\',NULL,28);')
    sql=(Path(__file__).parents[2]/'docs/migrations/experiment-engine-v2-sqlite.sql').read_text(encoding='utf-8')
    conn.executescript(sql)
    assert conn.execute('SELECT status,engine_version FROM experiments').fetchone()==('active',None)
    conn.execute("UPDATE experiments SET status='stopped' WHERE id='legacy'")
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute("UPDATE experiments SET engine_version=2 WHERE id='legacy'")
    assert not conn.execute('PRAGMA foreign_key_check').fetchall()
    conn.close()
