from unittest.mock import Mock
from app.models import User, AuditLog
from app.core.security import create_access_token
from app.services.azure_blob import azure_blob_service
from tests.test_account_deletion import deletion_context

URL = '/api/v1/users/skin-profile'

def test_profile_roundtrip_partial_privacy_and_deletion(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    old = client.get('/api/v1/users/me', headers=auth).json()
    assert old['profile_context'] is None
    fields = {'age_band':'25_34', 'sex':'prefer_not_to_say', 'sensitivities_allergies':['عطر'],
              'dermatologist_care':'current', 'medications_treatments':['Retinoid'],
              'primary_goals':['Comfort'], 'hormonal_disclosure':'disclosed',
              'hormonal_context':['hormone_therapy'], 'menstrual_context':'prefer_not_to_say'}
    result = client.patch(URL, headers=auth, json={'profile_context':fields}).json()
    assert result['skin_concerns'] == old['skin_concerns']
    assert result['profile_context'] == fields
    result = client.patch(URL, headers=auth, json={'profile_context':{'age_band':None}}).json()
    assert result['profile_context']['age_band'] is None
    assert result['profile_context']['medications_treatments'] == ['Retinoid']
    result = client.patch(URL, headers=auth, json={'profile_context':{'hormonal_disclosure':'prefer_not_to_say'}}).json()
    assert result['profile_context']['hormonal_context'] is None
    assert client.get('/api/v1/users/me', headers=auth).json() == result
    assert client.patch(URL, headers=auth, json={}).json() == result
    assert client.patch(URL, json={'skin_type':'dry'}).status_code == 401
    other = {'Authorization':'Bearer '+create_access_token('delete-doctor','doctor',hashed_password='unused')}
    assert client.get('/api/v1/users/me', headers=other).json()['profile_context'] is None
    assert client.patch(URL, headers=auth, json={'profile_context':{'sex':'inferred'}}).status_code == 422
    assert client.patch(URL, headers=auth, json={'profile_context':{'hormonal_context':['pregnancy']}}).status_code == 422
    assert all('Retinoid' not in str(a.details) for a in db.query(AuditLog))
    monkeypatch.setattr(azure_blob_service, 'delete_image', Mock())
    monkeypatch.setattr(azure_blob_service, 'delete_owned_images', Mock())
    assert client.delete('/api/v1/users/me', headers=auth).status_code == 204
    assert db.get(User, 'delete-patient') is None
    assert client.get('/api/v1/users/me', headers=auth).status_code == 401

def test_clear_and_legacy_concerns(deletion_context):
    client, db, auth = deletion_context
    user = db.get(User, 'delete-patient'); user.skin_concerns = ['Legacy custom']; db.commit()
    result = client.patch(URL, headers=auth, json={'profile_context':{'menstrual_context':'not_applicable'}}).json()
    assert result['skin_concerns'] == ['Legacy custom']
    assert result['profile_context']['sex'] is None
    assert client.patch(URL, headers=auth, json={'profile_context':None}).json()['profile_context'] is None
    assert client.patch(URL, headers=auth, json={'skin_type':None, 'skin_concerns':None, 'selected_goal':None}).json()['skin_concerns'] == []

def test_registration_without_sensitive_fields(client):
    response = client.post('/api/v1/auth/register', json={'email':'profile-v2@example.com','password':'Profile-password-123','full_name':'Profile Patient','accept_safety':True})
    assert response.status_code == 201
    auth = {'Authorization':'Bearer '+response.json()['access_token']}
    profile = client.get('/api/v1/users/me', headers=auth).json()
    assert profile['profile_context'] is None
    assert profile['skin_concerns'] == []
    assert profile['selected_goal'] is None

def test_failed_update_rolls_back(deletion_context, monkeypatch):
    client, db, auth = deletion_context
    old = client.get('/api/v1/users/me', headers=auth).json()
    monkeypatch.setattr(db, 'commit', Mock(side_effect=RuntimeError('Unavailable')))
    assert client.patch(URL, headers=auth, json={'profile_context':{'sex':'female'}, 'skin_concerns':['New']}).status_code == 503
    assert client.get('/api/v1/users/me', headers=auth).json() == old

def test_legacy_null_concerns_and_other_user_updates(deletion_context):
    client, db, auth = deletion_context
    patient = db.get(User, 'delete-patient'); patient.skin_concerns = None; db.commit()
    assert client.get('/api/v1/users/me', headers=auth).json()['skin_concerns'] == []
    other = {'Authorization':'Bearer '+create_access_token('delete-doctor','doctor',hashed_password='unused')}
    assert client.patch(URL, headers=other, json={'skin_concerns':['Other'], 'profile_context':{'sex':'male'}}).status_code == 200
    own = client.get('/api/v1/users/me', headers=auth).json()
    assert own['profile_context'] is None and own['skin_concerns'] == []
