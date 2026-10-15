from sqlalchemy import Column,String,Integer,DateTime,JSON,Text,ForeignKey,CheckConstraint
from app.core.database import Base
from app.models import gen_uuid,utc_now


class AgentSession(Base):
    __tablename__="agent_sessions"
    id=Column(String(36),primary_key=True,default=gen_uuid)
    user_id=Column(String(36),ForeignKey("users.id"),nullable=False,index=True)
    auth_session_id=Column(String(100),nullable=False)
    credential=Column(String(64),nullable=False)
    expires_at=Column(DateTime,nullable=False)
    revoked_at=Column(DateTime,nullable=True)
    revision=Column(Integer,nullable=False,default=1)
    scopes=Column(JSON,nullable=False)
    context=Column(JSON,nullable=True)
    context_digest=Column(String(64),nullable=False)
    context_at=Column(DateTime,nullable=False)
    tool_calls=Column(Integer,nullable=False,default=0)


class AgentTurn(Base):
    __tablename__="agent_turns"
    id=Column(String(36),primary_key=True)
    session_id=Column(String(36),ForeignKey("agent_sessions.id"),nullable=False,index=True)
    body=Column(Text,nullable=False)
    created_at=Column(DateTime,nullable=False,default=utc_now)


class AgentAction(Base):
    __tablename__="agent_actions"
    __table_args__=(CheckConstraint("state IN ('preview','confirmed','revoked')",name="ck_agent_action_state"),)
    id=Column(String(36),primary_key=True)
    session_id=Column(String(36),ForeignKey("agent_sessions.id"),nullable=False,index=True)
    user_id=Column(String(36),ForeignKey("users.id"),nullable=False,index=True)
    kind=Column(String(40),nullable=False)
    state=Column(String(20),nullable=False)
    revision=Column(Integer,nullable=False)
    payload=Column(JSON,nullable=False)
    payload_hash=Column(String(64),nullable=False)
    context_digest=Column(String(64),nullable=False)
    previewed_at=Column(DateTime,nullable=False)
    confirmed_at=Column(DateTime,nullable=True)
    result=Column(JSON,nullable=True)
