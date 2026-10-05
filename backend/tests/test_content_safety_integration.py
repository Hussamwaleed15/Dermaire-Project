from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from app.services.azure_safety import azure_safety_service
from app.services.contextual_ai import assist
from tests.test_account_deletion import deletion_context
from tests.test_contextual_ai import configured, plan, request, user
from tests.test_clinician_assistance import decision
from tests.test_safety_engine import report

@pytest.fixture
def moderation(monkeypatch):
    monkeypatch.setattr(azure_safety_service,'is_live',True)
    client=Mock()
    client.analyze_text.return_value=SimpleNamespace(categories_analysis=[SimpleNamespace(severity=0)])
    monkeypatch.setattr(azure_safety_service,'client',client,raising=False)
    return client

@pytest.mark.parametrize('path',['/api/v1/assistance','/api/v1/chat'])
@pytest.mark.parametrize('mode',['success','invalid_key','flagged','malformed'])
def test_active_routes(deletion_context,configured,moderation,monkeypatch,path,mode):
    import app.services.contextual_ai as service
    client,db,headers=deletion_context
    ai=Mock();ai.generate.side_effect=plan
    monkeypatch.setattr(service,'get_contextual_provider',lambda:ai)
    if mode=='invalid_key': moderation.analyze_text.side_effect=RuntimeError('401 invalid SECRET KEY')
    if mode=='malformed': moderation.analyze_text.return_value=object()
    if mode=='flagged': moderation.analyze_text.return_value=SimpleNamespace(categories_analysis=[SimpleNamespace(severity=4)])
    response=client.post(path,headers=headers,json={'message':'What should I track?','task':'tracking'})
    assert response.status_code==200
    data=response.json() if path.endswith('assistance') else response.json()['safety_details']['contextual_assistance']
    moderation.analyze_text.assert_called_once()
    assert moderation.analyze_text.call_args.args[0].text=='What should I track?'
    assert data['moderation']=={'provider':'azure_content_safety','configured':True,'invoked':True,'state':'degraded' if mode in ('invalid_key','malformed') else 'available','flagged':mode=='flagged'}
    assert data['escalation']==data['authoritative_safety']['status']=='track'
    assert 'SECRET' not in response.text
    if mode=='flagged':
        ai.generate.assert_not_called()
        assert data['metadata']['reason']=='content_policy' and data['grounded_facts_used']==[]
    else:
        ai.generate.assert_called_once()
        assert data['metadata']['mode']=='grounded_ai'

@pytest.mark.parametrize('guard',['urgent','doctor_review','clinician','red_flag'])
@pytest.mark.parametrize('path',['/api/v1/assistance','/api/v1/chat'])
def test_guards_skip_both_providers(deletion_context,configured,moderation,monkeypatch,guard,path):
    import app.services.contextual_ai as service
    client,db,headers=deletion_context
    ai=Mock();monkeypatch.setattr(service,'get_contextual_provider',ai)
    if guard=='urgent':
        report(db,{'breathing_difficulty':True});decision(db,'doctor_review')
    if guard=='doctor_review': report(db,{'pain':'moderate'})
    if guard=='clinician': decision(db,'urgent')
    response=client.post(path,headers=headers,json={'message':'difficulty breathing' if guard=='red_flag' else 'What should I track?','task':'tracking'})
    assert response.status_code==200
    data=response.json() if path.endswith('assistance') else response.json()['safety_details']['contextual_assistance']
    assert not data['moderation']['invoked'] and not data['metadata']['invoked']
    assert data['escalation']==('track' if guard=='red_flag' else 'doctor_review' if guard=='doctor_review' else 'urgent')
    moderation.analyze_text.assert_not_called();ai.assert_not_called()

def test_adapter_exception_is_safe(deletion_context,configured,moderation,monkeypatch):
    monkeypatch.setattr(azure_safety_service,'analyze_message_safety',Mock(side_effect=RuntimeError('secret')))
    _,db,_=deletion_context
    ai=Mock();ai.generate.side_effect=plan
    result=assist(db,user(db),request(),provider=ai)
    assert result.moderation.state=='degraded' and result.metadata.mode=='grounded_ai'
    assert 'secret' not in result.model_dump_json()

@pytest.mark.parametrize('live',[True,False])
def test_moderation_independent_of_generation(deletion_context,moderation,monkeypatch,live):
    from app.core.config import settings
    monkeypatch.setattr(settings,'CONTEXTUAL_AI_ENABLED',False)
    monkeypatch.setattr(azure_safety_service,'is_live',live)
    _,db,_=deletion_context
    ai=Mock()
    result=assist(db,user(db),request(),provider=ai)
    assert result.moderation.configured==live and result.moderation.invoked==live
    assert result.moderation.state==('available' if live else 'not_invoked')
    assert result.metadata.mode=='degraded'
    assert result.escalation==result.authoritative_safety.status=='track'
    assert moderation.analyze_text.call_count==int(live)
    ai.generate.assert_not_called()
