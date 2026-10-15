from datetime import datetime, timezone
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from alembic import command
from alembic.config import Config
from tests.test_postgres_gate import pg_engine
from app.models import User, AuditLog
from app.core.database import Base
from app.core.config import settings
from app.core.security import create_access_token
from app.services.onboarding import complete_review

@pytest.mark.parametrize("populated", [False, True])
def test_explicit_review_empty_populated_and_readback(client, db_session, populated):
    u=User(id="review-"+str(populated),email="review-"+str(populated)+"@example.com",full_name="Synthetic",hashed_password="unused",
           safety_accepted=True,safety_policy_version="1.0",safety_accepted_at=datetime.now(timezone.utc),
           skin_type="dry" if populated else None)
    db_session.add(u); db_session.commit()
    auth={"Authorization":"Bearer "+create_access_token(u.id,"patient",hashed_password="unused")}
    assert client.get("/api/v1/users/me",headers=auth).json()["onboarding"]["review_state"]=="never_reviewed"
    assert client.patch("/api/v1/users/skin-profile",headers=auth,json={}).json()["onboarding"]["review_state"]=="never_reviewed"
    result=client.post("/api/v1/users/profile-review",headers=auth,json={"reviewed":True})
    assert result.status_code==200
    state=result.json()["onboarding"]
    assert state["review_state"]=="reviewed" and state["optional_data_present"]==populated
    assert state["reviewed_at"].endswith("Z")
    assert client.post("/api/v1/users/profile-review",headers=auth,json={"reviewed":True}).json()["onboarding"]==state
    # A new valid session sees persisted authority; no client-memory completion.
    auth2={"Authorization":"Bearer "+create_access_token(u.id,"patient",hashed_password="unused")}
    assert client.get("/api/v1/users/me",headers=auth2).json()["onboarding"]==state
    assert db_session.query(AuditLog).filter_by(actor_id=u.id,action="PROFILE_REVIEW_COMPLETED").count()==1
    for body in ({"reviewed":False},{},{"reviewed":True,"user_id":"foreign"}):
        assert client.post("/api/v1/users/profile-review",headers=auth,json=body).status_code==422
    assert client.post("/api/v1/users/profile-review",json={"reviewed":True}).status_code==401
    assert client.post("/api/v1/auth/logout",headers=auth).status_code==204
    assert client.post("/api/v1/users/profile-review",headers=auth,json={"reviewed":True}).status_code==401

@pytest.mark.parametrize("role", ["patient","doctor"])
def test_missing_safety_doctor_exemption_and_isolation(client,db_session,role):
    u=User(id="review-isolate-"+role,email="review-isolate-"+role+"@example.com",full_name="Synthetic",hashed_password="unused",role=role)
    db_session.add(u);db_session.commit()
    auth={"Authorization":"Bearer "+create_access_token(u.id,role,hashed_password="unused")}
    assert client.post("/api/v1/users/profile-review",headers=auth,json={"reviewed":True}).status_code==403
    assert client.get("/api/v1/users/me",headers=auth).json()["onboarding"]["review_state"] == ("never_reviewed" if role=="patient" else "not_applicable")
    assert db_session.get(User,u.id).profile_reviewed_at is None


def test_review_transaction_rollback(client,db_session,monkeypatch):
    from unittest.mock import Mock
    u=User(id="review-rollback",email="review-rollback@example.com",full_name="Synthetic",hashed_password="unused",safety_accepted=True,safety_policy_version="1.0",safety_accepted_at=datetime.now(timezone.utc))
    db_session.add(u);db_session.commit()
    auth={"Authorization":"Bearer "+create_access_token(u.id,"patient",hashed_password="unused")}
    monkeypatch.setattr(db_session,"commit",Mock(side_effect=RuntimeError("test-only")))
    assert client.post("/api/v1/users/profile-review",headers=auth,json={"reviewed":True}).status_code==503
    assert client.get("/api/v1/users/me",headers=auth).json()["onboarding"]["review_state"]=="never_reviewed"


def test_pg_concurrent_review(pg_engine):
    Base.metadata.create_all(pg_engine); factory=sessionmaker(bind=pg_engine)
    with factory() as db:
        db.add(User(id="review",email="review@example.com",full_name="Synthetic",hashed_password="unused",safety_accepted=True,safety_policy_version="1.0",safety_accepted_at=datetime.now(timezone.utc)));db.commit()
    def submit(_):
        with factory() as db:
            u=db.query(User).filter_by(id="review").with_for_update().one()
            complete_review(db,u)
            return u.onboarding
    with ThreadPoolExecutor(max_workers=2) as pool: receipts=list(pool.map(submit,range(2)))
    assert receipts[0]==receipts[1]
    with factory() as db: assert db.query(AuditLog).filter_by(action="PROFILE_REVIEW_COMPLETED").count()==1


def migrate(engine,monkeypatch):
    monkeypatch.setattr(settings,"DATABASE_URL",engine.url.render_as_string(hide_password=False))
    cfg=Config(str(Path(__file__).parents[1]/"alembic.ini"))
    command.upgrade(cfg,"20261014_04")
    with engine.begin() as c:
        c.execute(text("INSERT INTO users(id,email,hashed_password,full_name,role,reset_token_attempts,skin_type,safety_accepted,safety_policy_version,safety_accepted_at) VALUES ('legacy','legacy@example.com','unused','Synthetic','patient',0,'dry',true,'1.0','2026-01-01')"))
    command.upgrade(cfg,"head"); command.check(cfg)
    with engine.connect() as c:
        assert c.execute(text("SELECT skin_type,safety_policy_version,profile_reviewed_at FROM users")).one()==("dry","1.0",None)
    command.downgrade(cfg,"20261014_04"); command.upgrade(cfg,"head")
    with engine.begin() as c:c.execute(text("UPDATE users SET profile_reviewed_at='2026-01-02'"))
    with pytest.raises(RuntimeError,match="recorded profile review"):command.downgrade(cfg,"20261014_04")


def test_sqlite_review_migration(tmp_path,monkeypatch):
    engine=create_engine("sqlite:///"+(tmp_path/"review.db").as_posix())
    try:migrate(engine,monkeypatch)
    finally:engine.dispose()


def test_pg_review_migration(pg_engine,monkeypatch):migrate(pg_engine,monkeypatch)
