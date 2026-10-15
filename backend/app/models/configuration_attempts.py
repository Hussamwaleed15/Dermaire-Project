from sqlalchemy import Column,String,Integer,DateTime,ForeignKey,JSON,CheckConstraint
from app.core.database import Base


class ConfigurationAttempt(Base):
    """Owner-authored routine/experiment SQL outcomes only; no external effects."""
    __tablename__="configuration_attempts"
    __table_args__=(CheckConstraint("domain IN ('routine','experiment')",name="ck_configuration_attempt_domain"),)
    id=Column(String(36),primary_key=True)
    user_id=Column(String(36),ForeignKey("users.id"),nullable=False,index=True)
    domain=Column(String(20),nullable=False)
    operation=Column(String(20),nullable=False)
    resource_id=Column(String(36),nullable=False,index=True)
    source_product_id=Column(String(36),nullable=True,index=True)
    resource_revision=Column(Integer,nullable=False)
    payload_hash=Column(String(64),nullable=False)
    result_kind=Column(String(20),nullable=False)
    result_snapshot=Column(JSON(none_as_null=True),nullable=True)
    recorded_at=Column(DateTime,nullable=False)
