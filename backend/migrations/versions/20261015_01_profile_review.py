"""Explicit patient profile review; legacy rows remain unreviewed."""
from alembic import op
import sqlalchemy as sa
revision = "20261015_01"
down_revision = "20261014_04"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("users", sa.Column("profile_reviewed_at", sa.DateTime(), nullable=True))


def downgrade():
    if op.get_bind().execute(sa.text("SELECT count(*) FROM users WHERE profile_reviewed_at IS NOT NULL")).scalar():
        raise RuntimeError("Cannot discard recorded profile review consent")
    op.drop_column("users", "profile_reviewed_at")
