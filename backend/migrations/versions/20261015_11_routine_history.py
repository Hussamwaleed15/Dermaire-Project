"""Prospective routine configuration evidence; no historical reconstruction."""
from alembic import op
import sqlalchemy as sa
revision = '20261015_11'
down_revision = '20261015_10'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('user_calendar_policies',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('revision', sa.Integer(), nullable=False),
        sa.Column('timezone_name', sa.String(100), nullable=False),
        sa.Column('effective_at', sa.DateTime(), nullable=False),
        sa.UniqueConstraint('user_id', 'revision', name='uq_calendar_policy_revision'))
    op.create_index('ix_user_calendar_policies_user_id', 'user_calendar_policies', ['user_id'])
    op.create_table('routine_configuration_events',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('routine_entry_id', sa.String(36), sa.ForeignKey('routine_entries.id', ondelete='CASCADE'), nullable=False),
        sa.Column('source_product_id', sa.String(36), nullable=False),
        sa.Column('kind', sa.String(30), nullable=False),
        sa.Column('schema_version', sa.Integer(), nullable=False),
        sa.Column('snapshot', sa.JSON(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False))
    op.create_index('ix_routine_configuration_events_source_product_id', 'routine_configuration_events', ['source_product_id'])
    op.create_index('ix_routine_configuration_events_user_id', 'routine_configuration_events', ['user_id'])
    op.create_index('ix_routine_configuration_events_routine_entry_id', 'routine_configuration_events', ['routine_entry_id'])


def downgrade():
    connection = op.get_bind()
    for table in ('routine_configuration_events', 'user_calendar_policies'):
        if connection.execute(sa.text('SELECT count(*) FROM ' + table)).scalar():
            raise RuntimeError('Cannot discard prospective configuration/calendar history')
    op.drop_table('routine_configuration_events')
    op.drop_table('user_calendar_policies')
