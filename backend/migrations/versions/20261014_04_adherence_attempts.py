"""Durable owner/payload-bound adherence attempt evidence."""
from alembic import op
import sqlalchemy as sa

revision = "20261014_04"
down_revision = "20261014_03"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("routine_adherence", sa.Column("attempt_metadata", sa.JSON(), nullable=True))


def downgrade():
    if op.get_bind().execute(sa.text("SELECT count(*) FROM routine_adherence WHERE attempt_metadata IS NOT NULL")).scalar():
        raise RuntimeError("Cannot remove durable adherence attempts while receipts exist")
    op.drop_column("routine_adherence", "attempt_metadata")
