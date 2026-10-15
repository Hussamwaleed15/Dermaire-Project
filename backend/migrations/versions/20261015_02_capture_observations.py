"""Explicit owner-selected capture/observation links; no historical backfill."""
from alembic import op
import sqlalchemy as sa
revision = '20261015_02'
down_revision = '20261015_01'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('capture_observations',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('capture_id', sa.String(36), sa.ForeignKey('captures.id'), nullable=False),
        sa.Column('checkin_id', sa.String(36), sa.ForeignKey('checkins.id'), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.UniqueConstraint('user_id', 'capture_id', 'checkin_id', name='uq_capture_observation_owner_pair'))
    for column in ('user_id', 'capture_id', 'checkin_id'):
        op.create_index('ix_capture_observations_' + column, 'capture_observations', [column])


def downgrade():
    if op.get_bind().execute(sa.text('SELECT count(*) FROM capture_observations')).scalar():
        raise RuntimeError('Cannot discard recorded capture observation associations')
    op.drop_table('capture_observations')
