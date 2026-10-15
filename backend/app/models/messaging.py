"""Grant-bound immutable messages; no external delivery claim."""
from sqlalchemy import Column, String, Integer, Text, DateTime, ForeignKey, UniqueConstraint, CheckConstraint
from app.core.database import Base
from app.models import gen_uuid, utc_now


class MessageThread(Base):
    __tablename__ = "message_threads"
    __table_args__ = (UniqueConstraint("access_id", name="uq_message_thread_access"),
                     CheckConstraint("next_sequence >= 1 AND patient_read >= 0 AND doctor_read >= 0", name="ck_thread_counters"))
    id = Column(String(36), primary_key=True, default=gen_uuid)
    patient_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    doctor_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    access_id = Column(String(36), ForeignKey("doctor_patient_access.id"), nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
    closed_at = Column(DateTime, nullable=True)
    next_sequence = Column(Integer, nullable=False, default=1)
    patient_read = Column(Integer, nullable=False, default=0)
    doctor_read = Column(Integer, nullable=False, default=0)


class ThreadMessage(Base):
    __tablename__ = "thread_messages"
    __table_args__ = (UniqueConstraint("thread_id", "sequence", name="uq_message_sequence"),
                     CheckConstraint("sequence > 0", name="ck_message_sequence"))
    id = Column(String(36), primary_key=True)
    thread_id = Column(String(36), ForeignKey("message_threads.id"), nullable=False, index=True)
    actor_id = Column(String(36), ForeignKey("users.id"), nullable=False)
    sequence = Column(Integer, nullable=False)
    payload_hash = Column(String(64), nullable=False)
    body = Column(Text, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)
