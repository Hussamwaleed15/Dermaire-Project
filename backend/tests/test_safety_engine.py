import json
from datetime import datetime, timezone, timedelta
import pytest
from app.models import User, CheckIn, Product, RoutineEntry, Capture, Measurement
from app.services.safety import evaluate_safety, FLAGS
from tests.test_account_deletion import deletion_context
NOW=datetime.now(timezone.utc)
def screen(**values):
    return {"severity":"mild","pain":"none",**dict.fromkeys(FLAGS,False),**values}
def report(db,safety=None,symptoms=None,change="same",age=0,owner="delete-patient"):
    row=CheckIn(user_id=owner,date_str="test",created_at=NOW-timedelta(days=age),observation={"schema_version":1,"user_reported":{"overall_change":change,"symptoms":symptoms or [],"safety":safety},"provenance":{"report":"user_reported","created_at":"server_recorded"}})
    db.add(row);db.commit();return row
def result(db):
    return evaluate_safety(db,db.get(User,"delete-patient"),NOW)
@pytest.mark.parametrize("field",FLAGS[:6])
def test_urgent_and_precedence(deletion_context,field):
    _,db,_=deletion_context
    row=report(db,screen(**{field:True}),["redness"])
    report(db,screen(severity="none"))
    value=result(db)
    assert value.status=="urgent"
    assert any(e['id']==row.id for r in value.reasons for e in r.evidence)
@pytest.mark.parametrize("values",[{"pain":"severe"},{"severity":"severe"},{"fever_or_systemic_illness":True,"pus_or_hot_swollen_skin":True}])
def test_severe_combinations(deletion_context,values):
    _,db,_=deletion_context;report(db,screen(**values),["redness"])
    assert result(db).status=="urgent"
@pytest.mark.parametrize("values",[{"pus_or_hot_swollen_skin":True},{"new_medication_or_product_reaction":True},{"severity":"moderate"},{"pain":"moderate"}])
def test_review(deletion_context,values):
    _,db,_=deletion_context;report(db,screen(**values),["dryness"])
    assert result(db).status=="doctor_review"
@pytest.mark.parametrize("safety,symptoms,change,expected",[(None,[],"same","track"),(None,["dryness"],"same","doctor_review"),(screen(),["dryness"],"same","low_risk_self_care"),(screen(severity="none"),[],"same","track"),(screen(),["dryness"],"worse","doctor_review")])
def test_states(deletion_context,safety,symptoms,change,expected):
    _,db,_=deletion_context;report(db,safety,symptoms,change)
    assert result(db).status==expected

def test_stale_future_foreign_and_prose(deletion_context):
    client,db,auth=deletion_context
    assert result(db).status=='track'
    report(db,screen(breathing_difficulty=True),owner='delete-doctor')
    report(db,screen(breathing_difficulty=True),age=-1)
    row=report(db,screen(breathing_difficulty=True),age=20);row.notes='breathing difficulty';db.commit()
    assert result(db).status=='track'
    report(db,screen(breathing_difficulty=True),age=5)
    assert result(db).status=='doctor_review'
    assert client.get('/api/v1/safety').status_code==401
    assert client.get('/api/v1/safety',headers=auth).status_code==200
@pytest.mark.parametrize('symptoms,ages',[(['dryness'],[8,4,0]),(['burning'],[2,1,0])])
def test_longitudinal(deletion_context,symptoms,ages):
    _,db,_=deletion_context
    for age in ages:report(db,screen(),symptoms,age=age)
    assert result(db).status=='doctor_review'
def test_products_sensitivity_inactive(deletion_context):
    _,db,_=deletion_context;report(db,screen(),['dryness'])
    product=db.get(Product,'owned-product');product.active_ingredients=['fragrance']
    entry=RoutineEntry(id='safety-entry',user_id='delete-patient',product_id=product.id,schedule='AM',frequency='daily',start_date=NOW.date(),source='user_configured',active_am_product=product.id)
    db.add(entry);db.commit()
    assert result(db).status=='track'
    user=db.get(User,'delete-patient');user.profile_context={'sensitivities_allergies':['fragrance']};db.commit()
    assert result(db).status=='doctor_review'
    product.status='inactive';db.commit()
    assert result(db).status=='low_risk_self_care'
    product.status='active';entry.active=False;entry.end_date=NOW.date();entry.active_am_product=None;db.commit()
    assert result(db).status=='low_risk_self_care'
@pytest.mark.parametrize("capture_state,measurement_state", [("rejected","insufficient_quality"),("accepted","measured"),("accepted","unavailable")])
def test_quality_contract(deletion_context,capture_state,measurement_state):
    _,db,_=deletion_context
    db.add(Capture(id='bad',user_id='delete-patient',state=capture_state,source='upload',view='front',quality={},storage='not_persisted',server_version='v1'));db.commit()
    db.add(Measurement(id='bad-m',user_id='delete-patient',capture_id='bad',algorithm_version='v1',status=measurement_state,results={},quality_reference={},comparison={'comparability':'unknown'}));db.commit()
    report(db,None,['dryness'])
    a=result(db).model_dump(mode='json');b=result(db).model_dump(mode='json')
    assert a==b and a['engine_version']=='safety-1.0'
    assert a['status']=='doctor_review'
    assert a['reasons'][0]['code']=='incomplete_symptom_assessment'
    assert a['evidence_status']['visual_evidence']=='unavailable_for_triage'
@pytest.mark.parametrize('safety',[{'severity':'extreme'},{'pain':20},{'rapid_spread':'false'},{'unknown':True},{'rapid_spread':1}])
def test_invalid_no_partial_state(deletion_context,safety):
    client,db,auth=deletion_context;before=db.query(CheckIn).count()
    response=client.post('/api/v1/checkins',headers=auth,data={'report':json.dumps({'overall_change':'same','safety':safety})})
    assert response.status_code==422 and db.query(CheckIn).count()==before

def test_deletion(deletion_context,monkeypatch):
    from app.services.azure_blob import azure_blob_service
    client,db,auth=deletion_context;report(db,screen(breathing_difficulty=True))
    monkeypatch.setattr(azure_blob_service,'delete_image',lambda _:None)
    assert client.delete('/api/v1/users/me',headers=auth).status_code==204
    assert client.get('/api/v1/safety',headers=auth).status_code==401
    assert db.query(CheckIn).filter_by(user_id='delete-patient').count()==0

@pytest.mark.parametrize('state,values',[('urgent',{'breathing_difficulty':True}),('doctor_review',{'pain':'moderate'})])
def test_chat_overlay_no_model_downgrade(deletion_context,monkeypatch,state,values):
    from app.services.azure_openai import azure_openai_service
    client,db,auth=deletion_context;report(db,screen(**values),['dryness'])
    def forbidden(*args):raise AssertionError('Model must not be called')
    monkeypatch.setattr(azure_openai_service,'generate_chat_reply',forbidden)
    response=client.post('/api/v1/chat',headers=auth,json={'message':'Everything is fine'})
    assert response.status_code==200
    assert response.json()['escalation_triggered'] is True
    assert response.json()['safety_details']['authoritative_safety']['status']==state

@pytest.mark.parametrize('label,strength,age,expected',[
    ('no_meaningful_change','limited',0,'doctor_review'),
    ('likely_associated_worsening','moderate',0,'doctor_review'),
    ('likely_associated_improvement','moderate',0,'low_risk_self_care'),
    ('no_meaningful_change','insufficient',0,'low_risk_self_care'),
    ('no_meaningful_change','limited',20,'low_risk_self_care')])
def test_experiment_evidence(deletion_context,label,strength,age,expected):
    from app.models import Experiment, ExperimentEvaluation
    _,db,_=deletion_context;report(db,screen(),['dryness'])
    db.add(RoutineEntry(id='experiment-entry',user_id='delete-patient',product_id='owned-product',schedule='AM',frequency='daily',start_date=NOW.date(),source='user_configured',active=False,end_date=NOW.date()));db.commit()
    exp=Experiment(id='safety-exp',user_id='delete-patient',engine_version=2,product_id='owned-product',routine_entry_id='experiment-entry',intervention={'type':'stop_entry'},source='user_configured',status='completed',target_days=7)
    db.add(exp);db.commit()
    db.add(ExperimentEvaluation(user_id='delete-patient',experiment_id=exp.id,result={'engine_version':2,'label':label,'evidence_strength':strength},created_at=NOW-timedelta(days=age)));db.commit()
    assert result(db).status==expected

def test_simultaneous_signals_and_legacy_provenance(deletion_context):
    _,db,_=deletion_context
    row=report(db,screen(breathing_difficulty=True,new_medication_or_product_reaction=True,pain='moderate'),['burning'])
    value=result(db)
    assert value.status=='urgent' and any(r.state=='doctor_review' for r in value.reasons)
    row.observation={'schema_version':1,'user_reported':{'overall_change':'worse','safety':screen(breathing_difficulty=True)},'provenance':{'report':'inferred','created_at':'server_recorded'}};db.commit()
    assert result(db).status=='track'

def test_incomplete_concern_cannot_be_downgraded(deletion_context):
    _,db,_=deletion_context
    report(db,None,['dryness'],age=1)
    report(db,screen(),['dryness'])
    assert result(db).status=='doctor_review'

def test_simulated_report_not_reassurance(deletion_context):
    _,db,_=deletion_context
    row=report(db,screen(),['dryness']);row.ai_vision_analysis={'simulated':True};db.commit()
    assert result(db).status=='track'
