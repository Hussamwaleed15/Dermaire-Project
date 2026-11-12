from datetime import datetime, timezone, timedelta
from concurrent.futures import ThreadPoolExecutor
import pytest
from tests.test_postgres_gate import pg_engine
from app.models import User, AuditLog
from app.core.config import settings
from app.core.security import create_access_token
from app.services.policy_consent import consent_snapshot, accept_policy
from app.schemas import AcceptSafetyRequest
from app.core.config import Settings

@pytest.mark.parametrize("accepted,version,stamp,state", [
    (False,"1.0",None,"missing"), (True,"1.0",None,"unknown"),
    (True,"bad",True,"unknown"), (True,None,True,"unknown"),
    (True,"0.9",True,"outdated"), (True,"1.0",True,"current"),
])
def test_historical_state(accepted, version, stamp, state):
    user=User(safety_accepted=accepted,safety_policy_version=version,
              safety_accepted_at=datetime.now(timezone.utc)-timedelta(seconds=1) if stamp else None)
    assert consent_snapshot(user)["state"] == state

@pytest.mark.parametrize("role", ["patient", "doctor"])
def test_accept_readback_roles_and_version_change(client, db_session, monkeypatch, role):
    user=User(id="consent-"+role,email=role+"@example.com",full_name="Synthetic",hashed_password="test",role=role)
    db_session.add(user); db_session.commit()
    auth={"Authorization":"Bearer "+create_access_token(user.id,role,hashed_password="test")}
    url="/api/v1/auth/accept-safety"
    result=client.post(url,headers=auth,json={}).json()
    assert result["safety_consent"]["state"] == "current"
    assert client.post(url,headers=auth,json={}).json()["safety_consent"] == result["safety_consent"]
    assert db_session.query(AuditLog).filter_by(actor_id=user.id,action="SAFETY_TERMS_ACCEPTED").count()==1
    assert client.get("/api/v1/users/me",headers=auth).json()["safety_consent"]==result["safety_consent"]
    monkeypatch.setattr(settings,"SAFETY_POLICY_REQUIRED_VERSION","2.0")
    monkeypatch.setattr(settings,"SAFETY_POLICY_ENFORCE",True)
    assert client.get("/api/v1/users/me",headers=auth).json()["safety_consent"]["state"]=="outdated"
    assert client.patch("/api/v1/users/skin-profile",headers=auth,json={}).status_code==403
    assert client.post(url,headers=auth,json={}).status_code==409
    assert client.post(url,headers=auth,json={"policy_version":"2.0"}).json()["safety_consent"]["state"]=="current"
    assert client.patch("/api/v1/users/skin-profile",headers=auth,json={}).status_code==200
    assert client.post(url,headers=auth,json={"accepted":False}).status_code==422
    assert client.post(url,headers=auth,json={"policy_version":"broken"}).status_code==422
    assert client.post(url,json={}).status_code==401
    other=User(id="consent-other-"+role,email="other-"+role+"@example.com",full_name="Other",hashed_password="test",role=role)
    db_session.add(other); db_session.commit()
    other_auth={"Authorization":"Bearer "+create_access_token(other.id,role,hashed_password="test")}
    assert client.get("/api/v1/users/me",headers=other_auth).json()["safety_consent"]["state"]=="missing"
    assert client.post("/api/v1/auth/logout",headers=auth).status_code==204
    assert client.post(url,headers=auth,json={"policy_version":"2.0"}).status_code==401


def test_registration_cannot_implicitly_accept_changed_policy(client, monkeypatch):
    monkeypatch.setattr(settings,"SAFETY_POLICY_REQUIRED_VERSION","2.0")
    body=dict(email="new-policy@example.com",password="Synthetic-password-123",full_name="Synthetic",accept_safety=True)
    assert client.post("/api/v1/auth/register",json=body).status_code==409
    assert client.post("/api/v1/auth/register",json={**body,"policy_version":"2.0"}).status_code==201


def test_public_policy_contract_fails_closed_until_approved_document_exists(client, monkeypatch):
    monkeypatch.setattr(settings, "SAFETY_POLICY_REQUIRED_VERSION", "2.0")
    monkeypatch.setattr(settings, "SAFETY_POLICY_DOCUMENT_URL", "")
    monkeypatch.setattr(settings, "SAFETY_POLICY_DOCUMENT_SHA256", "")
    response = client.get("/api/v1/auth/safety-policy")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "no-store"
    assert response.json() == {
        "schema_version": 1,
        "required_version": "2.0",
        "enforcement_enabled": False,
        "document_status": "unavailable",
        "document": None,
        "acceptance_ready": False,
    }

    monkeypatch.setattr(settings, "SAFETY_POLICY_DOCUMENT_URL", "https://policy.example.test/safety/2.0")
    monkeypatch.setattr(settings, "SAFETY_POLICY_DOCUMENT_SHA256", "a" * 64)
    approved = client.get("/api/v1/auth/safety-policy").json()
    assert approved["document_status"] == "approved"
    assert approved["acceptance_ready"] is True
    assert approved["document"] == {
        "url": "https://policy.example.test/safety/2.0",
        "sha256": "a" * 64,
    }


@pytest.mark.parametrize("overrides", [
    {"SAFETY_POLICY_DOCUMENT_URL": "https://policy.example.test/safety/1.0"},
    {"SAFETY_POLICY_DOCUMENT_SHA256": "a" * 64},
    {
        "SAFETY_POLICY_DOCUMENT_URL": "http://policy.example.test/safety/1.0",
        "SAFETY_POLICY_DOCUMENT_SHA256": "a" * 64,
    },
    {
        "SAFETY_POLICY_DOCUMENT_URL": "https://policy.example.test/safety/1.0",
        "SAFETY_POLICY_DOCUMENT_SHA256": "not-a-digest",
    },
    {"SAFETY_POLICY_ENFORCE": True},
])
def test_policy_document_configuration_fails_closed(overrides):
    with pytest.raises(ValueError):
        Settings(_env_file=None, **overrides)


def test_enforcement_allows_account_erasure_after_policy_change(client, db_session, monkeypatch):
    user = User(
        id="policy-delete", email="policy-delete@example.com", full_name="Synthetic",
        hashed_password="test", role="patient", safety_accepted=True,
        safety_policy_version="1.0", safety_accepted_at=datetime.now(timezone.utc),
    )
    db_session.add(user); db_session.commit()
    user_id = user.id
    auth = {"Authorization": "Bearer " + create_access_token(user.id, user.role, hashed_password="test")}
    monkeypatch.setattr(settings, "SAFETY_POLICY_REQUIRED_VERSION", "2.0")
    monkeypatch.setattr(settings, "SAFETY_POLICY_ENFORCE", True)
    assert client.patch("/api/v1/users/skin-profile", headers=auth, json={}).status_code == 403
    assert client.delete("/api/v1/users/me", headers=auth).status_code == 204
    assert db_session.query(User).filter_by(id=user_id).first() is None


def test_pg_concurrent_consent(pg_engine):
    from sqlalchemy.orm import sessionmaker
    from app.core.database import Base
    Base.metadata.create_all(pg_engine)
    factory=sessionmaker(bind=pg_engine)
    with factory() as db:
        db.add(User(id="consent",email="consent@example.com",full_name="Synthetic",hashed_password="test")); db.commit()
    def submit(_):
        with factory() as db:
            user=db.query(User).filter_by(id="consent").with_for_update().one()
            return consent_snapshot(accept_policy(db,user,AcceptSafetyRequest()))
    with ThreadPoolExecutor(max_workers=2) as pool:
        receipts=list(pool.map(submit,range(2)))
    assert receipts[0]==receipts[1]
    with factory() as db:
        assert db.query(AuditLog).filter_by(action="SAFETY_TERMS_ACCEPTED").count()==1

