from datetime import datetime, timedelta, timezone
from unittest.mock import Mock
import pytest
from fastapi.testclient import TestClient
from app.main import app
from app.models import CheckIn, DailyContext, User
from app.core.security import create_access_token, create_refresh_token
from app.services.azure_blob import azure_blob_service
from app.services.personal_skin_model import personal_skin_model
from tests.test_account_deletion import deletion_context

NOW = datetime.now(timezone.utc)

def add(db, day, score=None, change=None, source='manual'):
    when = NOW - timedelta(days=day)
    obs = {'schema_version': 1, 'provenance': {'report': 'user_reported', 'created_at': 'server_recorded'}, 'user_reported': {'overall_change': change, 'symptoms': ['dryness'] if change == 'worse' else []}} if change else None
    row = CheckIn(user_id='delete-patient', date_str=when.date().isoformat(), created_at=when, hydration_score=score, texture_score=score, redness_score=score, ai_vision_analysis={'measurement_source': source}, observation=obs)
    db.add(row); db.commit()
    return row

def model(db):
    return personal_skin_model(db, db.get(User, 'delete-patient'), NOW).model_dump(mode='json')

def measured(db, score=50, source='manual'):
    return [add(db, d, 50, source=source) for d in range(12,7,-1)] + [add(db,d,score,source=source) for d in [3,2,1]]

def test_no_data(deletion_context):
    client, db, auth = deletion_context
    view = model(db)
    assert view['status'] == 'no_data' and view['strength'] == 'none'
    assert view['products'][0]['id'] == 'owned-product'
    assert view['sufficiency']['excluded_checkins'] == 1
    assert client.get('/api/v1/personal-skin-model', headers=auth).status_code == 200

def test_insufficient_duplicates(deletion_context):
    _,db,_ = deletion_context
    for _ in range(8): add(db,1,50,'worse')
    view = model(db)
    assert view['status'] == 'insufficient_data' and view['sufficiency']['confirmed_days'] == 1

@pytest.mark.parametrize('score,status,direction', [(50,'no_meaningful_change','stable'), (70,'meaningful_change','increased'), (30,'meaningful_change','decreased')])
def test_measurements(deletion_context, score,status,direction):
    _,db,_ = deletion_context
    rows = measured(db,score)
    view = model(db)
    findings = view['stable'] + view['changing']
    assert view['status'] == status and len(findings) == 3
    assert all(f['direction'] == direction and f['threshold'] == 10 for f in findings)
    assert {e['id'] for e in findings[0]['evidence']} == {r.id for r in rows}

@pytest.mark.parametrize('mixed', [True,False])
def test_source_provenance(deletion_context,mixed):
    _,db,_ = deletion_context
    rows = measured(db,70,'image_proxy')
    if mixed:
        rows[0].ai_vision_analysis={'measurement_source':'manual'}; db.commit()
        assert model(db)['status']=='insufficient_data'
    else:
        assert all(e['kind']=='image_proxy' for e in model(db)['changing'][0]['evidence'])

def test_association(deletion_context):
    _,db,_=deletion_context
    for day in range(6,0,-1):
        row=add(db,day,change='same' if day>3 else 'worse')
        db.add(DailyContext(user_id=row.user_id,date=row.created_at.date(),unusual_conditions=day<=3, updated_at=row.created_at))
    db.commit()
    view=model(db)
    assert view['status']=='meaningful_change'
    assert any(f['subject']=='dryness' for f in view['changing'])
    f=view['associations'][0]
    assert 'does not establish cause' in f['statement'] and len(f['evidence'])==12
    assert {e['source'] for e in f['evidence']}=={'checkin','daily_context'}

def test_report_no_change(deletion_context):
    _,db,_=deletion_context
    for day in range(6): add(db,day,change='same')
    assert model(db)['status']=='no_meaningful_change'

def test_sensitive_omission(deletion_context):
    _,db,_=deletion_context
    user=db.get(User,'delete-patient')
    user.profile_context={'primary_goals':['Track dryness'],'sex':'female','hormonal_context':['pregnancy'],'medications_treatments':['private-medication']}
    db.add(DailyContext(user_id=user.id,date=NOW.date(),cycle_day=12)); db.commit()
    view=model(db)
    assert view['profile']['primary_goals']==['Track dryness']
    assert view['profile']['evidence'][0]['fields']==['profile_context.primary_goals']
    assert all(s not in str(view) for s in ['pregnancy','female','private-medication'])
    assert not view['associations']

@pytest.mark.parametrize('analysis',[{'measurement_source':'manual','azure_vision_status':'FALLBACK_SIMULATED'}, {}, {'measurement_source':'simulated'}, {'measurement_source':'manual','simulated':True}, {'measurement_source':'manual','azure_vision_status':'SIMULATED_SUCCESS'}])
def test_fake_excluded(deletion_context,analysis):
    _,db,_=deletion_context
    row=add(db,0,80); row.ai_vision_analysis=analysis; db.commit()
    assert model(db)['status']=='no_data'

def test_report_provenance(deletion_context):
    _,db,_=deletion_context
    row=add(db,0,change='worse'); row.observation={'schema_version':1,'user_reported':{'overall_change':'worse'}}; db.commit()
    assert model(db)['status']=='no_data'

def test_stale_future(deletion_context):
    _,db,_=deletion_context
    add(db,15,change='same'); add(db,-1,change='worse')
    view=model(db)
    assert view['status']=='stale' and view['sufficiency']['age_days']==15
    assert not view['changing'] and not view['stable'] and view['strength']=='none'

def test_auth_deletion(deletion_context,monkeypatch):
    client,db,auth=deletion_context
    measured(db)
    other={'Authorization':'Bearer '+create_access_token('delete-doctor','doctor',hashed_password='unused')}
    assert client.get('/api/v1/personal-skin-model',headers=other).json()['status']=='no_data'
    assert client.get('/api/v1/personal-skin-model').status_code==401
    assert client.get('/api/v1/personal-skin-model',headers={'Authorization':'Bearer '+create_refresh_token('delete-patient')}).status_code==401
    monkeypatch.setattr(azure_blob_service,'delete_image',Mock())
    assert client.delete('/api/v1/users/me',headers=auth).status_code==204
    assert client.get('/api/v1/personal-skin-model',headers=auth).status_code==401
    assert db.query(CheckIn).count()==0

def test_read_failure(deletion_context,monkeypatch):
    _,db,auth=deletion_context
    query=db.query
    def fail(cls):
        if cls is CheckIn: raise RuntimeError('Unavailable')
        return query(cls)
    monkeypatch.setattr(db,'query',fail)
    with TestClient(app,raise_server_exceptions=False) as client:
        assert client.get('/api/v1/personal-skin-model',headers=auth).status_code==500

def test_same_baseline_day_not_recent(deletion_context):
    _,db,_=deletion_context
    for day in range(5,0,-1): add(db,day,50)
    add(db,1,90); add(db,0,90)
    assert model(db)['status']=='insufficient_data'

def test_old_reports_not_refreshed_by_new_measurement(deletion_context):
    _,db,_=deletion_context
    for day in range(25,19,-1): add(db,day,change='worse')
    add(db,0,50)
    assert model(db)['status']=='insufficient_data'

def test_inconsistent_measurements_are_unknown(deletion_context):
    _,db,_=deletion_context
    rows=measured(db)
    for row,score in zip(rows[-3:],[100,40,40]):
        row.hydration_score=score; row.texture_score=score; row.redness_score=score
    db.commit()
    view=model(db)
    assert view['status']=='insufficient_data' and not view['stable']

def test_context_unknown_not_false_and_owner_isolated(deletion_context):
    _,db,_=deletion_context
    for day in range(6,0,-1):
        row=add(db,day,change='worse' if day<=3 else 'same')
        db.add(DailyContext(user_id='delete-doctor',date=row.created_at.date(),unusual_conditions=day<=3, updated_at=row.created_at))
        db.add(DailyContext(user_id=row.user_id,date=row.created_at.date(),unusual_conditions=True if day<=3 else None, updated_at=row.created_at))
    db.commit()
    assert not model(db)['associations']

def test_threshold_uses_personal_variability(deletion_context):
    _,db,_=deletion_context
    for day,score in zip(range(12,7,-1),[20,80,20,80,50]): add(db,day,score)
    for day in [3,2,1]: add(db,day,70)
    view=model(db)
    assert view['status']=='no_meaningful_change'
    assert view['stable'][0]['threshold']>50


def test_simulated_reports_never_count(deletion_context):
    _,db,_=deletion_context
    row=add(db,0,change='worse')
    row.ai_vision_analysis={'measurement_source':'simulated'}; db.commit()
    assert model(db)['status']=='no_data'
