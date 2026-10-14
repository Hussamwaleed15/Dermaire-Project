"""All-writer routine configuration revisions; legacy rows remain unprotected."""
from alembic import op
import sqlalchemy as sa

revision = "20261014_02"
down_revision = "20261014_01"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("routine_entries", sa.Column("revision", sa.Integer(), nullable=False, server_default="1"))
    op.add_column("routine_entries", sa.Column("revision_protected", sa.Boolean(), nullable=False, server_default=sa.false()))


def downgrade():
    if op.get_bind().execute(sa.text("SELECT count(*) FROM routine_entries WHERE revision_protected = true")).scalar():
        raise RuntimeError("Cannot remove revisions while protected routine entries exist")
    op.drop_column("routine_entries", "revision_protected")
    op.drop_column("routine_entries", "revision")
