"""Monotonic product revisions with explicit per-resource protected mode."""
from alembic import op
import sqlalchemy as sa

revision = "20261014_01"
down_revision = "20261008_01"
branch_labels = None
depends_on = None

def upgrade():
    op.add_column("products", sa.Column("revision", sa.Integer(), nullable=False, server_default="1"))
    op.add_column("products", sa.Column("revision_protected", sa.Boolean(), nullable=False, server_default=sa.false()))

def downgrade():
    # Removing protection from opted-in records silently reopens stale writes.
    protected = op.get_bind().execute(sa.text("SELECT count(*) FROM products WHERE revision_protected = true")).scalar()
    if protected:
        raise RuntimeError("Cannot remove revisions while protected products exist")
    op.drop_column("products", "revision_protected")
    op.drop_column("products", "revision")
