"""Recurring routine settings; no change to old UTC adherence dates."""
from alembic import op
import sqlalchemy as sa
revision = "20261015_13"
down_revision = "20261015_11"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table("routine_reminder_settings",
        sa.Column("id",sa.String(36),primary_key=True),
        sa.Column("user_id",sa.String(36),sa.ForeignKey("users.id"),nullable=False),
        sa.Column("routine_entry_id",sa.String(36),sa.ForeignKey("routine_entries.id"),nullable=False,unique=True),
        sa.Column("revision",sa.Integer(),nullable=False),
        sa.Column("enabled",sa.Boolean(),nullable=False),
        sa.Column("timezone",sa.String(100),nullable=False),
        sa.Column("am_minute",sa.Integer(),nullable=False),
        sa.Column("pm_minute",sa.Integer(),nullable=False),
        sa.Column("fold",sa.Integer(),nullable=False),
        sa.Column("effective_at",sa.DateTime(),nullable=False),
        sa.Column("generated_at",sa.DateTime(),nullable=True))
    op.create_index("ix_routine_reminder_settings_user_id","routine_reminder_settings",["user_id"])
    op.add_column("notifications",sa.Column("reminder_id",sa.String(36),nullable=True))
    op.add_column("notifications",sa.Column("reminder_revision",sa.Integer(),nullable=True))
    op.create_table("notification_job_attempts",
        sa.Column("id",sa.String(36),primary_key=True),
        sa.Column("job_id",sa.String(36),sa.ForeignKey("notification_jobs.id",ondelete="CASCADE"),nullable=False),
        sa.Column("number",sa.Integer(),nullable=False),
        sa.Column("state",sa.String(30),nullable=False),
        sa.Column("started_at",sa.DateTime(),nullable=False),
        sa.Column("finished_at",sa.DateTime(),nullable=True))
    op.create_index("ix_notification_job_attempts_job_id","notification_job_attempts",["job_id"])


def downgrade():
    if op.get_bind().execute(sa.text("SELECT count(*) FROM notification_job_attempts")).scalar():
        raise RuntimeError("Cannot discard durable push attempt history")
    if op.get_bind().execute(sa.text("SELECT count(*) FROM routine_reminder_settings")).scalar():
        raise RuntimeError("Cannot discard recurring reminder settings")
    if op.get_bind().execute(sa.text("SELECT count(*) FROM notifications WHERE reminder_id IS NOT NULL")).scalar():
        raise RuntimeError("Cannot discard recurring occurrence provenance")
    op.drop_table("notification_job_attempts")
    op.drop_column("notifications","reminder_revision")
    op.drop_column("notifications","reminder_id")
    op.drop_table("routine_reminder_settings")
