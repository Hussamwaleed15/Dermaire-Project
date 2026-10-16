"""Transactional clinician note/review receipts."""
from alembic import op
import sqlalchemy as sa
revision = '20261015_10'
down_revision = '20261015_09'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('clinical_attempts',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('doctor_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('patient_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('access_id', sa.String(36), nullable=False),
        sa.Column('operation', sa.String(10), nullable=False),
        sa.Column('resource_id', sa.String(36), nullable=False),
        sa.Column('payload_hash', sa.String(64), nullable=False),
        sa.Column('result_snapshot', sa.JSON(none_as_null=True), nullable=True),
        sa.Column('recorded_at', sa.DateTime(), nullable=False),
        sa.CheckConstraint("operation IN ('note','review','claim')", name='ck_clinical_attempt_operation'))
    op.create_index('ix_clinical_attempts_doctor_id', 'clinical_attempts', ['doctor_id'])
    op.create_index('ix_clinical_attempts_patient_id', 'clinical_attempts', ['patient_id'])
    op.create_table('grant_attempts',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('operation', sa.String(10), nullable=False),
        sa.Column('access_id', sa.String(36), nullable=False),
        sa.Column('payload_hash', sa.String(64), nullable=False),
        sa.Column('result_snapshot', sa.JSON(none_as_null=True), nullable=True),
        sa.Column('recorded_at', sa.DateTime(), nullable=False),
        sa.CheckConstraint("operation IN ('issue','revoke','revoke_all')", name='ck_grant_attempt_operation'))
    op.create_index('ix_grant_attempts_user_id', 'grant_attempts', ['user_id'])


def downgrade():
    if op.get_bind().execute(sa.text('SELECT count(*) FROM clinical_attempts')).scalar():
        raise RuntimeError('Cannot discard committed clinical receipts')
    if op.get_bind().execute(sa.text('SELECT count(*) FROM grant_attempts')).scalar():
        raise RuntimeError('Cannot discard committed grant receipts')
    op.drop_table('grant_attempts')
    op.drop_table('clinical_attempts')
