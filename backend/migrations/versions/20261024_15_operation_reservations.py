"""Add the inactive B6-A operation reservation foundation.

Revision ID: 20261024_15
Revises: 20261024_14
"""
from alembic import op
import sqlalchemy as sa


revision = "20261024_15"
down_revision = "20261024_14"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "operation_reservations",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("owner_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("domain", sa.String(64), nullable=False),
        sa.Column("operation", sa.String(64), nullable=False),
        sa.Column("key_hash", sa.String(64), nullable=False),
        sa.Column("payload_hash", sa.String(64), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("generation", sa.Integer(), nullable=False),
        sa.Column("lease_token_hash", sa.String(64), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(), nullable=True),
        sa.Column("result_snapshot", sa.JSON(none_as_null=True), nullable=True),
        sa.Column("failure_code", sa.String(64), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
        sa.Column("retain_until", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("owner_id", "domain", "operation", "key_hash",
                            name="uq_operation_reservation_identity"),
        sa.CheckConstraint("status IN ('reserved','committed','failed')",
                           name="ck_operation_reservation_status"),
        sa.CheckConstraint("generation > 0", name="ck_operation_reservation_generation"),
        sa.CheckConstraint("length(key_hash) = 64", name="ck_operation_reservation_key_hash"),
        sa.CheckConstraint("length(payload_hash) = 64", name="ck_operation_reservation_payload_hash"),
        sa.CheckConstraint("retain_until > created_at", name="ck_operation_reservation_retention"),
        sa.CheckConstraint(
            "(status = 'reserved' AND lease_token_hash IS NOT NULL AND lease_expires_at IS NOT NULL "
            "AND result_snapshot IS NULL AND failure_code IS NULL) OR "
            "(status = 'committed' AND lease_token_hash IS NULL AND lease_expires_at IS NULL "
            "AND failure_code IS NULL) OR "
            "(status = 'failed' AND lease_token_hash IS NULL AND lease_expires_at IS NULL "
            "AND result_snapshot IS NULL AND failure_code IS NOT NULL)",
            name="ck_operation_reservation_shape"),
    )
    op.create_index("ix_operation_reservations_owner_id", "operation_reservations", ["owner_id"])
    op.create_index("ix_operation_reservations_retain_until", "operation_reservations", ["retain_until"])


def downgrade():
    bind = op.get_bind()
    if bind.execute(sa.text("SELECT 1 FROM operation_reservations LIMIT 1")).first() is not None:
        raise RuntimeError("refusing to drop non-empty operation_reservations; archive or purge explicitly")
    op.drop_index("ix_operation_reservations_retain_until", table_name="operation_reservations")
    op.drop_index("ix_operation_reservations_owner_id", table_name="operation_reservations")
    op.drop_table("operation_reservations")
