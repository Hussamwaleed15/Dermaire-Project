"""Experiment definition/lifecycle/evaluation revision fence."""
from alembic import op
import sqlalchemy as sa

revision = "20261014_03"
down_revision = "20261014_02"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("experiments", sa.Column("revision", sa.Integer(), nullable=False, server_default="1"))
    op.add_column("experiments", sa.Column("revision_protected", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade():
    if op.get_bind().execute(sa.text("SELECT count(*) FROM experiments WHERE revision_protected = true")).scalar():
        raise RuntimeError("Cannot remove revisions while protected experiments exist")
    op.drop_column("experiments", "revision_protected")
    op.drop_column("experiments", "revision")
