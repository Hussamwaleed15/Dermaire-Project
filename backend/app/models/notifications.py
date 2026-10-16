from sqlalchemy import Column, String, Integer, Boolean, DateTime, ForeignKey, JSON, Text, UniqueConstraint, CheckConstraint
from app.core.database import Base
from app.models import gen_uuid, utc_now


class NotificationPreference(Base):
    __tablename__ = "notification_preferences"
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, unique=True)
    revision = Column(Integer, nullable=False, default=1)
    enabled_kinds = Column(JSON, nullable=False)
    push_enabled = Column(Boolean, nullable=False, default=False)
    timezone = Column(String(100), nullable=False)
    quiet_start = Column(Integer, nullable=False)
    quiet_end = Column(Integer, nullable=False)


class NotificationDevice(Base):
    __tablename__ = "notification_devices"
    id = Column(String(36), primary_key=True)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    session_id = Column(String(100), nullable=False)
    credential = Column(String(64), nullable=False)
    session_expires_at = Column(DateTime, nullable=False)
    token_hash = Column(String(64), nullable=False, unique=True)
    token_encrypted = Column(Text, nullable=False)
    platform = Column(String(10), nullable=False)
    revoked_at = Column(DateTime, nullable=True)


class Notification(Base):
    __tablename__ = "notifications"
    id = Column(String(36), primary_key=True)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    kind = Column(String(20), nullable=False)
    source_id = Column(String(36), nullable=False)
    source_revision = Column(Integer, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    due_at = Column(DateTime, nullable=False)
    read_at = Column(DateTime, nullable=True)
    cancelled_at = Column(DateTime, nullable=True)
    reminder_id = Column(String(36), nullable=True)
    reminder_revision = Column(Integer, nullable=True)


class NotificationJob(Base):
    __tablename__ = "notification_jobs"
    __table_args__ = (UniqueConstraint("notification_id", "device_id", name="uq_notification_device_job"),
        CheckConstraint("state IN ('queued','leased','retry','provider_unavailable','provider_accepted','cancelled')", name="ck_notification_job_state"))
    id = Column(String(36), primary_key=True, default=gen_uuid)
    notification_id = Column(String(36), ForeignKey("notifications.id"), nullable=False, index=True)
    device_id = Column(String(36), ForeignKey("notification_devices.id"), nullable=False)
    state = Column(String(30), nullable=False, default="queued")
    available_at = Column(DateTime, nullable=False)
    attempts = Column(Integer, nullable=False, default=0)
    lease_token = Column(String(36), nullable=True)
    lease_until = Column(DateTime, nullable=True)

class RoutineReminderSetting(Base):
    __tablename__ = "routine_reminder_settings"
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    routine_entry_id = Column(String(36), ForeignKey("routine_entries.id"), nullable=False, unique=True)
    revision = Column(Integer, nullable=False, default=1)
    enabled = Column(Boolean, nullable=False, default=False)
    timezone = Column(String(100), nullable=False)
    am_minute = Column(Integer, nullable=False)
    pm_minute = Column(Integer, nullable=False)
    fold = Column(Integer, nullable=False)
    effective_at = Column(DateTime, nullable=False, default=utc_now)
    generated_at = Column(DateTime, nullable=True)

class NotificationJobAttempt(Base):
    """Durable bounded transport-attempt state; never delivery certification."""
    __tablename__ = "notification_job_attempts"
    id = Column(String(36), primary_key=True)
    job_id = Column(String(36), ForeignKey("notification_jobs.id", ondelete="CASCADE"), nullable=False, index=True)
    number = Column(Integer, nullable=False)
    state = Column(String(30), nullable=False)
    started_at = Column(DateTime, nullable=False)
    finished_at = Column(DateTime, nullable=True)
