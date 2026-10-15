"""Durable product-create outcomes, no historical backfill."""
from alembic import op
import sqlalchemy as sa
revision = '20261015_03'
down_revision = '20261015_02'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('product_create_attempts',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('resource_id', sa.String(36), nullable=False),
        sa.Column('resource_revision', sa.Integer(), nullable=False),
        sa.Column('payload_hash', sa.String(64), nullable=False),
        sa.Column('result_snapshot', sa.JSON(none_as_null=True), nullable=True),
        sa.Column('recorded_at', sa.DateTime(), nullable=False))
    op.create_index('ix_product_create_attempts_user_id', 'product_create_attempts', ['user_id'])


def downgrade():
    if op.get_bind().execute(sa.text('SELECT count(*) FROM product_create_attempts')).scalar():
        raise RuntimeError('Cannot discard durable product create attempts')
    op.drop_table('product_create_attempts')
