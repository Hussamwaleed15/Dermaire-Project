from sqlalchemy import Column, String, Integer, DateTime, JSON, ForeignKey, CheckConstraint, UniqueConstraint
from app.core.database import Base
from app.models import utc_now, gen_uuid


class ClinicalPlan(Base):
    __tablename__="clinical_plans"
    __table_args__=(CheckConstraint("kind IN ('follow_up','comparison')",name="ck_clinical_plan_kind"),
        CheckConstraint("state IN ('proposed','scheduled','captured','reviewed','cancelled')",name="ck_clinical_plan_state"))
    id=Column(String(36),primary_key=True)
    user_id=Column(String(36),ForeignKey("users.id"),nullable=False,index=True)
    doctor_id=Column(String(36),ForeignKey("users.id"),nullable=False,index=True)
    access_id=Column(String(36),ForeignKey("doctor_patient_access.id"),nullable=False)
    kind=Column(String(20),nullable=False)
    revision=Column(Integer,nullable=False)
    state=Column(String(20),nullable=False)
    purpose=Column(String(1000),nullable=False)
    due_at=Column(DateTime,nullable=False)
    schedule_provenance=Column(JSON,nullable=False)
    source_snapshot=Column(JSON,nullable=False)
    baseline_capture_id=Column(String(36),nullable=True)
    followup_capture_id=Column(String(36),nullable=True)
    acknowledged_at=Column(DateTime,nullable=True)
    created_at=Column(DateTime,nullable=False,default=utc_now)


class ClinicalPlanEvent(Base):
    __tablename__="clinical_plan_events"
    __table_args__=(UniqueConstraint("plan_id","revision",name="uq_clinical_plan_event_revision"),)
    id=Column(String(36),primary_key=True,default=gen_uuid)
    plan_id=Column(String(36),ForeignKey("clinical_plans.id"),nullable=False,index=True)
    actor_id=Column(String(36),ForeignKey("users.id"),nullable=False)
    revision=Column(Integer,nullable=False)
    operation=Column(String(20),nullable=False)
    recorded_at=Column(DateTime,nullable=False,default=utc_now)
    snapshot=Column(JSON,nullable=False)


class ClinicalPlanAttempt(Base):
    __tablename__="clinical_plan_attempts"
    id=Column(String(36),primary_key=True)
    plan_id=Column(String(36),ForeignKey("clinical_plans.id"),nullable=False,index=True)
    user_id=Column(String(36),ForeignKey("users.id"),nullable=False)
    actor_id=Column(String(36),ForeignKey("users.id"),nullable=False)
    operation=Column(String(20),nullable=False)
    payload_hash=Column(String(64),nullable=False)
    result=Column(JSON,nullable=False)
    recorded_at=Column(DateTime,nullable=False,default=utc_now)
