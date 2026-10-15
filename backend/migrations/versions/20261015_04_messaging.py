"""Explicitly consented grant-bound immutable messaging."""
from alembic import op
import sqlalchemy as sa
revision = "20261015_04"
down_revision = "20261015_03"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("message_threads",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("patient_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("doctor_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("access_id", sa.String(36), sa.ForeignKey("doctor_patient_access.id"), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("closed_at", sa.DateTime(), nullable=True),
        sa.Column("next_sequence", sa.Integer(), nullable=False),
        sa.Column("patient_read", sa.Integer(), nullable=False),
        sa.Column("doctor_read", sa.Integer(), nullable=False),
        sa.UniqueConstraint("access_id", name="uq_message_thread_access"),
        sa.CheckConstraint("next_sequence >= 1 AND patient_read >= 0 AND doctor_read >= 0", name="ck_thread_counters"))
    for name in ("patient_id", "doctor_id"):
        op.create_index("ix_message_threads_"+name, "message_threads", [name])
    op.create_table("thread_messages",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("thread_id", sa.String(36), sa.ForeignKey("message_threads.id"), nullable=False),
        sa.Column("actor_id", sa.String(36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("sequence", sa.Integer(), nullable=False),
        sa.Column("payload_hash", sa.String(64), nullable=False),
        sa.Column("body", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("thread_id", "sequence", name="uq_message_sequence"),
        sa.CheckConstraint("sequence > 0", name="ck_message_sequence"))
    op.create_index("ix_thread_messages_thread_id", "thread_messages", ["thread_id"])


def downgrade():
    if op.get_bind().execute(sa.text("SELECT count(*) FROM message_threads")).scalar():
        raise RuntimeError("Cannot discard consented clinical conversations")
    op.drop_table("thread_messages")
    op.drop_table("message_threads")
