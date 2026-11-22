from sqlalchemy import (
    CheckConstraint,
    Column,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    String,
    UniqueConstraint,
)

from app.core.database import Base


class OperationReservation(Base):
    """Durable coordination record. Raw client keys and lease tokens are never stored."""

    __tablename__ = "operation_reservations"
    __table_args__ = (
        UniqueConstraint(
            "owner_id", "domain", "operation", "key_hash",
            name="uq_operation_reservation_identity",
        ),
        CheckConstraint("status IN ('reserved','committed','failed')", name="ck_operation_reservation_status"),
        CheckConstraint("generation > 0", name="ck_operation_reservation_generation"),
        CheckConstraint("length(key_hash) = 64", name="ck_operation_reservation_key_hash"),
        CheckConstraint("length(payload_hash) = 64", name="ck_operation_reservation_payload_hash"),
        CheckConstraint("retain_until > created_at", name="ck_operation_reservation_retention"),
        CheckConstraint(
            "(status = 'reserved' AND lease_token_hash IS NOT NULL AND lease_expires_at IS NOT NULL "
            "AND result_snapshot IS NULL AND failure_code IS NULL) OR "
            "(status = 'committed' AND lease_token_hash IS NULL AND lease_expires_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(status = 'failed' AND lease_token_hash IS NULL AND lease_expires_at IS NULL "
            "AND result_snapshot IS NULL AND failure_code IS NOT NULL)",
            name="ck_operation_reservation_shape",
        ),
    )

    id = Column(String(36), primary_key=True)
    owner_id = Column(String(36), ForeignKey("users.id"), nullable=False, index=True)
    domain = Column(String(64), nullable=False)
    operation = Column(String(64), nullable=False)
    key_hash = Column(String(64), nullable=False)
    payload_hash = Column(String(64), nullable=False)
    status = Column(String(16), nullable=False)
    generation = Column(Integer, nullable=False)
    lease_token_hash = Column(String(64), nullable=True)
    lease_expires_at = Column(DateTime, nullable=True)
    result_snapshot = Column(JSON(none_as_null=True), nullable=True)
    failure_code = Column(String(64), nullable=True)
    created_at = Column(DateTime, nullable=False)
    updated_at = Column(DateTime, nullable=False)
    retain_until = Column(DateTime, nullable=False, index=True)
