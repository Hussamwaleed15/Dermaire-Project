import uuid
from datetime import datetime, timezone
from sqlalchemy import (
    Column, String, Integer, Float, Boolean, DateTime, Date,
    ForeignKey, Text, JSON, UniqueConstraint, CheckConstraint, Enum as SQLEnum
)
from sqlalchemy.orm import relationship
from app.core.database import Base

def gen_uuid() -> str:
    return str(uuid.uuid4())

def utc_now() -> datetime:
    return datetime.now(timezone.utc)

class Capture(Base):
    __tablename__ = "captures"
    __table_args__ = (
        CheckConstraint("state IN ('accepted','rejected')", name="ck_capture_state"),
        CheckConstraint("source IN ('camera','upload') AND view = 'front'", name="ck_capture_origin"),
        CheckConstraint("(storage = 'not_persisted' AND image_blob_name IS NULL) OR (storage = 'azure_blob' AND image_blob_name IS NOT NULL AND state = 'accepted')", name="ck_capture_storage"),
    )
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    state = Column(String(20), nullable=False)
    source = Column(String(20), nullable=False)
    view = Column(String(20), nullable=False)
    received_at = Column(DateTime, default=utc_now, nullable=False)
    quality = Column(JSON, nullable=False)
    storage = Column(String(20), nullable=False)
    image_blob_name = Column(String(500), nullable=True)
    server_version = Column(String(50), nullable=False)

class Measurement(Base):
    __tablename__ = "measurements"
    __table_args__ = (
        UniqueConstraint("capture_id", "algorithm_version", name="uq_measurement_capture_version"),
        CheckConstraint("status IN ('measured','insufficient_quality','unavailable','failed')", name="ck_measurement_status"),
    )
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    capture_id = Column(String(36), ForeignKey("captures.id"), nullable=False, index=True)
    algorithm_version = Column(String(50), nullable=False)
    status = Column(String(30), nullable=False)
    measured_at = Column(DateTime, default=utc_now, nullable=False)
    results = Column(JSON, nullable=False)
    quality_reference = Column(JSON, nullable=False)
    comparison = Column(JSON, nullable=False)

class User(Base):
    __tablename__ = "users"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    email = Column(String(255), unique=True, index=True, nullable=False)
    hashed_password = Column(String(255), nullable=False)
    full_name = Column(String(255), nullable=False)
    role = Column(String(50), default="patient", nullable=False) # patient, doctor, admin, support

    # Medical Safety acceptance
    safety_accepted = Column(Boolean, default=False)
    safety_accepted_at = Column(DateTime, nullable=True)
    safety_policy_version = Column(String(20), default="1.0")

    # Skin Profile
    skin_type = Column(String(50), nullable=True)
    selected_goal = Column(String(100), nullable=True)
    skin_concerns = Column(JSON, default=list)

    profile_context = Column(JSON, nullable=True) # User-disclosed Profile v2; no inferred defaults

    # Gamification
    tokens_balance = Column(Integer, default=0)
    baseline_checkins_count = Column(Integer, default=0) # Legacy storage; not authoritative

    # Password reset (forgot-password flow)
    reset_token_hash = Column(String(255), nullable=True, index=True)
    reset_token_expires = Column(DateTime, nullable=True)
    reset_token_attempts = Column(Integer, default=0, nullable=False)
    created_at = Column(DateTime, default=utc_now)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)

    products = relationship("Product", back_populates="user", cascade="all, delete-orphan")
    experiments = relationship("Experiment", back_populates="user", cascade="all, delete-orphan")
    checkins = relationship("CheckIn", back_populates="user", cascade="all, delete-orphan")
    redemptions = relationship("RewardRedemption", back_populates="user", cascade="all, delete-orphan")

class Product(Base):
    __tablename__ = "products"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    name = Column(String(255), nullable=False)
    brand = Column(String(255), nullable=True)
    category = Column(String(50), nullable=False, default="treatment")
    product_type = Column(String(100), nullable=True)
    active_ingredients = Column(JSON, default=list)
    skin_concerns = Column(JSON, default=list)
    usage_instructions = Column(Text, default="")
    frequency_per_week = Column(Integer, default=7)
    time_of_use = Column(String(50), default="evening") # morning, evening, both, asNeeded
    status = Column(String(50), default="active") # active, inactive, archived
    start_date = Column(DateTime, nullable=True)
    end_date = Column(DateTime, nullable=True)
    notes = Column(Text, nullable=True)
    image_url = Column(String(500), nullable=True)
    tags = Column(JSON, default=list)
    rating = Column(Float, nullable=True)
    in_routine = Column(Boolean, default=True)
    in_experiment = Column(Boolean, default=False)
    created_at = Column(DateTime, default=utc_now)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)

    user = relationship("User", back_populates="products")

class ProductIntelligence(Base):
    """Owner-specific evidence document; never a shared catalog record."""
    __tablename__ = "product_intelligence"
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    product_id = Column(String(36), ForeignKey("products.id", ondelete="CASCADE"), nullable=False, unique=True)
    document = Column(JSON, nullable=False)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)

class Experiment(Base):
    __tablename__ = "experiments"
    __table_args__ = (
        CheckConstraint("engine_version IS NULL OR (engine_version = 2 AND intervention IS NOT NULL AND routine_entry_id IS NOT NULL AND product_id IS NOT NULL AND source IS NOT NULL AND source = 'user_configured' AND status IS NOT NULL AND target_days IS NOT NULL AND status IN ('draft','active','completed','stopped','cancelled') AND target_days BETWEEN 7 AND 90)", name="ck_experiment_v2_definition"),
        CheckConstraint("engine_version IS NULL OR ((status = 'active' AND active_owner IS NOT NULL AND active_owner = user_id AND activated_at IS NOT NULL AND definition_snapshot IS NOT NULL) OR (status <> 'active' AND active_owner IS NULL))", name="ck_experiment_v2_owner"),
    )

    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    product_id = Column(String(36), ForeignKey("products.id"), nullable=True)
    target_days = Column(Integer, default=28)
    current_day = Column(Integer, default=1)
    status = Column(String(50), default="active") # baseline, active, paused, completed
    primary_concern = Column(String(100), default="texture")
    redness_delta_percent = Column(Float, nullable=True)
    texture_delta_percent = Column(Float, nullable=True)
    hydration_delta_percent = Column(Float, nullable=True)
    start_date = Column(DateTime, default=utc_now)
    end_date = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=utc_now)

    # Nullable version distinguishes quarantined legacy experiments.
    engine_version = Column(Integer, nullable=True)
    # Retain the index introduced by experiment-engine-v2-postgresql.sql.
    routine_entry_id = Column(String(36), ForeignKey("routine_entries.id"), nullable=True, index=True)
    intervention = Column(JSON, nullable=True)
    goal = Column(Text, nullable=True)
    notes = Column(Text, nullable=True)
    source = Column(String(30), nullable=True)
    activated_at = Column(DateTime, nullable=True)
    stopped_at = Column(DateTime, nullable=True)
    definition_snapshot = Column(JSON, nullable=True)
    # One active v2 experiment per user, including concurrent inserts.
    active_owner = Column(String(36), unique=True, nullable=True)

    user = relationship("User", back_populates="experiments")
    checkins = relationship("CheckIn", back_populates="experiment")

class ExperimentEvaluation(Base):
    __tablename__ = "experiment_evaluations"
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    experiment_id = Column(String(36), ForeignKey("experiments.id"), nullable=False, index=True)
    result = Column(JSON, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)

class CheckIn(Base):
    __tablename__ = "checkins"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    experiment_id = Column(String(36), ForeignKey("experiments.id"), nullable=True)
    date_str = Column(String(50), nullable=False) # e.g. "2026-09-14"
    time_of_day = Column(String(20), default="Morning") # Morning, Evening
    hydration_score = Column(Float, nullable=True)
    texture_score = Column(Float, nullable=True)
    redness_score = Column(Float, nullable=True)
    observation = Column(JSON, nullable=True) # Versioned evidence; null for legacy rows
    notes = Column(Text, nullable=True)
    image_blob_name = Column(String(255), nullable=True)
    ai_vision_analysis = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=utc_now)

    user = relationship("User", back_populates="checkins")
    experiment = relationship("Experiment", back_populates="checkins")

class DoctorPatientAccess(Base):
    __tablename__ = "doctor_patient_access"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    doctor_id = Column(String(36), ForeignKey("users.id"), nullable=True, index=True)
    patient_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    access_token = Column(String(512), unique=True, index=True, nullable=False)
    status = Column(String(50), default="pending") # pending, active, revoked, expired
    granted_by = Column(String(36), nullable=True) # Legacy unknown; new grants record patient actor.
    claimed_at = Column(DateTime, nullable=True)
    revoked_at = Column(DateTime, nullable=True)
    revoked_by = Column(String(36), nullable=True)
    export_consent = Column(Boolean, default=True)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=utc_now)

class DoctorReviewAction(Base):
    """Immutable clinician review events; current state is the latest event."""
    __tablename__ = "doctor_review_actions"
    __table_args__ = (
        CheckConstraint("state IN ('pending','in_review','reviewed','follow_up_needed')", name="ck_doctor_review_state"),
        CheckConstraint("recommendation IS NULL OR recommendation IN ('track','low_risk_self_care','doctor_review','urgent')", name="ck_doctor_recommendation"),
    )
    id = Column(String(36), primary_key=True, default=gen_uuid)
    patient_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    doctor_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    access_id = Column(String(36), ForeignKey("doctor_patient_access.id"), nullable=False, index=True)
    sequence = Column(Integer, nullable=False)
    state = Column(String(30), nullable=False)
    recommendation = Column(String(30), nullable=True)
    rationale = Column(Text, nullable=True)
    patient_visible = Column(Boolean, nullable=False, default=False)
    safety_snapshot = Column(JSON, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    __table_args__ = __table_args__ + (UniqueConstraint("patient_id", "sequence", name="uq_doctor_review_sequence"),)

class ClinicalNote(Base):
    __tablename__ = "clinical_notes"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    doctor_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    patient_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    category = Column(String(50), nullable=True)
    patient_visible = Column(Boolean, nullable=False, default=False)
    timeline_item_id = Column(String(255), nullable=True)
    review_action_id = Column(String(36), ForeignKey("doctor_review_actions.id"), nullable=True)
    updated_at = Column(DateTime, nullable=False, default=utc_now) # Equal to created_at; immutable.
    content = Column(Text, nullable=False)
    priority = Column(String(50), default="routine") # routine, review, urgent
    follow_up = Column(String(100), nullable=True)
    created_at = Column(DateTime, default=utc_now)

class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    actor_id = Column(String(36), nullable=False, index=True)
    action = Column(String(255), nullable=False)
    target_resource = Column(String(255), nullable=False)
    details = Column(JSON, default=dict)
    ip_address = Column(String(50), nullable=True)
    created_at = Column(DateTime, default=utc_now)

class RewardRedemption(Base):
    __tablename__ = "reward_redemptions"

    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    reward_title = Column(String(255), nullable=False)
    tokens_spent = Column(Integer, default=10)
    created_at = Column(DateTime, default=utc_now)

    user = relationship("User", back_populates="redemptions")


class DailyContext(Base):
    __tablename__ = "daily_contexts"
    __table_args__ = (UniqueConstraint("user_id", "date", name="uq_context_user_date"),)
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    unusual_conditions = Column(Boolean, nullable=True)
    cycle_day = Column(Integer, nullable=True)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)

class RoutineEntry(Base):
    __tablename__ = "routine_entries"
    __table_args__ = (
        CheckConstraint("schedule IN ('AM', 'PM', 'BOTH')", name="ck_routine_schedule"),
        CheckConstraint("frequency = 'daily'", name="ck_routine_frequency"),
        CheckConstraint("am_order BETWEEN 0 AND 100 AND pm_order BETWEEN 0 AND 100", name="ck_routine_order"),
        CheckConstraint("source = 'user_configured'", name="ck_routine_source"),
        CheckConstraint("(active AND end_date IS NULL) OR (NOT active AND end_date IS NOT NULL AND end_date >= start_date)", name="ck_routine_end"),
        UniqueConstraint("active_am_product", name="uq_routine_active_am"),
        UniqueConstraint("active_pm_product", name="uq_routine_active_pm"),
    )
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    product_id = Column(String(36), ForeignKey("products.id"), nullable=False, index=True)
    schedule = Column(String(4), nullable=False)
    frequency = Column(String(20), nullable=False)
    start_date = Column(Date, nullable=False)
    end_date = Column(Date, nullable=True)
    active = Column(Boolean, nullable=False, default=True)
    instructions = Column(Text, nullable=True)
    am_order = Column(Integer, nullable=False, default=0)
    pm_order = Column(Integer, nullable=False, default=0)
    active_am_product = Column(String(36), nullable=True)
    active_pm_product = Column(String(36), nullable=True)
    source = Column(String(30), nullable=False, default="user_configured")
    created_at = Column(DateTime, nullable=False, default=utc_now)
    updated_at = Column(DateTime, nullable=False, default=utc_now, onupdate=utc_now)

    product = relationship("Product")

    @property
    def product_name(self):
        return self.product.name

class RoutineAdherence(Base):
    __tablename__ = "routine_adherence"
    __table_args__ = (
        UniqueConstraint("routine_entry_id", "date", "slot", name="uq_adherence_entry_day_slot"),
        CheckConstraint("slot IN ('AM', 'PM')", name="ck_adherence_slot"),
        CheckConstraint("status IN ('completed', 'skipped')", name="ck_adherence_status"),
        CheckConstraint("source = 'user_reported'", name="ck_adherence_source"),
    )
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    routine_entry_id = Column(String(36), ForeignKey("routine_entries.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    slot = Column(String(2), nullable=False)
    status = Column(String(10), nullable=False)
    note = Column(Text, nullable=True)
    source = Column(String(30), nullable=False, default="user_reported")
    created_at = Column(DateTime, nullable=False, default=utc_now)
    configuration_snapshot = Column(JSON, nullable=False)
