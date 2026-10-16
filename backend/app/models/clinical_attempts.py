from sqlalchemy import Column, String, DateTime, ForeignKey, JSON, CheckConstraint
from app.core.database import Base

class ClinicalAttempt(Base):
    """Committed clinician writes. Erased bilaterally with either account."""
    __tablename__ = "clinical_attempts"
    __table_args__ = (CheckConstraint("operation IN ('note','review','claim')", name="ck_clinical_attempt_operation"),)
    id = Column(String(36), primary_key=True)
    doctor_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    patient_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    access_id = Column(String(36), nullable=False)
    operation = Column(String(10), nullable=False)
    resource_id = Column(String(36), nullable=False)
    payload_hash = Column(String(64), nullable=False)
    result_snapshot = Column(JSON(none_as_null=True), nullable=True)
    recorded_at = Column(DateTime, nullable=False)


class GrantAttempt(Base):
    """Patient-authored issue/revoke consent outcomes; no token survives deletion."""
    __tablename__ = "grant_attempts"
    __table_args__ = (CheckConstraint("operation IN ('issue','revoke','revoke_all')", name="ck_grant_attempt_operation"),)
    id = Column(String(36), primary_key=True)
    user_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    operation = Column(String(10), nullable=False)
    access_id = Column(String(36), nullable=False)
    payload_hash = Column(String(64), nullable=False)
    result_snapshot = Column(JSON(none_as_null=True), nullable=True)
    recorded_at = Column(DateTime, nullable=False)
