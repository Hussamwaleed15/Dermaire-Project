"""Notification state revision for cross-device CAS.

Revision ID: 20261024_14
Revises: 20261015_13
"""
from alembic import op
import sqlalchemy as sa

revision = "20261024_14"
down_revision = "20261015_13"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("notifications", sa.Column("state_revision", sa.Integer(), nullable=False, server_default="1"))


def downgrade():
    op.drop_column("notifications", "state_revision")
