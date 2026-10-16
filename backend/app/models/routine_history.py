"""Prospective immutable configuration evidence, written in the source transaction."""
from sqlalchemy.orm import object_session
from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, JSON, UniqueConstraint, event, inspect
from app.core.database import Base
from app.models import RoutineEntry, Product, gen_uuid, utc_now


class RoutineConfigurationEvent(Base):
    __tablename__ = 'routine_configuration_events'
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey('users.id'), nullable=False, index=True)
    routine_entry_id = Column(String(36), ForeignKey('routine_entries.id', ondelete='CASCADE'), nullable=False, index=True)
    source_product_id = Column(String(36), nullable=False, index=True)
    kind = Column(String(30), nullable=False)
    schema_version = Column(Integer, nullable=False, default=1)
    snapshot = Column(JSON, nullable=False)
    created_at = Column(DateTime, nullable=False, default=utc_now)


FIELDS = ('product_id', 'schedule', 'frequency', 'start_date', 'end_date', 'active',
          'instructions', 'am_order', 'pm_order', 'source')


def tag_writer(db, target, actor_id, operation, **references):
    # Bind ephemeral attribution to this transaction; never infer actors from ownership.
    target._configuration_writer = (db.get_transaction(), {
        'actor_id': actor_id, 'writer_operation': operation, **references})


def writer(target):
    db = object_session(target)
    tagged = getattr(target, '_configuration_writer', None)
    if db is not None and tagged and tagged[0] is db.get_transaction():
        return tagged[1]
    return {'actor_id': None, 'writer_operation': 'unattributed_orm_write'}


def record(connection, values, kind, product=None, attribution=None):
    snapshot = {key: (value.isoformat() if hasattr(value, 'isoformat') else value)
                for key, value in values.items()}
    if product is None:
        product = connection.execute(Product.__table__.select().where(
            Product.id == values['product_id'], Product.user_id == values['user_id'])).mappings().first()
    snapshot['product_evidence'] = ({key: product[key] for key in
        ('id', 'name', 'brand', 'status', 'active_ingredients', 'usage_instructions')} if product else None)
    snapshot['provenance'] = {'source': 'committed_configuration_write', 'day_basis': 'UTC',
        'historical_backfill': False, 'clinical_validation': False,
        'owner_id': values['user_id'], **(attribution or {'actor_id': None, 'writer_operation': 'unattributed_orm_write'})}
    connection.execute(RoutineConfigurationEvent.__table__.insert().values(
        id=gen_uuid(), user_id=values['user_id'], routine_entry_id=values['id'], source_product_id=values['product_id'],
        kind=kind, schema_version=1, snapshot=snapshot, created_at=utc_now()))


@event.listens_for(RoutineEntry, 'after_insert')
def inserted(mapper, connection, target):
    record(connection, {key: getattr(target, key) for key in ('id', 'user_id', 'revision', 'created_at', 'updated_at', *FIELDS)}, 'created', attribution=writer(target))


@event.listens_for(RoutineEntry, 'after_update')
def updated(mapper, connection, target):
    # Fence pending effects in the same transaction, including CAS reservations.
    if (inspect(target).attrs.revision.history.has_changes() or
            any(inspect(target).attrs[key].history.has_changes() for key in FIELDS)):
        from app.models.notifications import Notification, NotificationJob
        ids = connection.execute(Notification.__table__.select().with_only_columns(Notification.id).where(
            Notification.user_id == target.user_id, Notification.kind == 'routine',
            Notification.source_id == target.id, Notification.cancelled_at.is_(None))).scalars().all()
        if ids:
            connection.execute(Notification.__table__.update().where(Notification.id.in_(ids)).values(cancelled_at=utc_now()))
            connection.execute(NotificationJob.__table__.update().where(
                NotificationJob.notification_id.in_(ids), NotificationJob.state != 'provider_accepted').values(
                    state='cancelled', lease_token=None, lease_until=None))
    if any(inspect(target).attrs[key].history.has_changes() for key in FIELDS):
        record(connection, {key: getattr(target, key) for key in ('id', 'user_id', 'revision', 'created_at', 'updated_at', *FIELDS)},
               'changed' if target.active else 'stopped', attribution=writer(target))


@event.listens_for(Product, 'after_update')
def product_updated(mapper, connection, target):
    if not any(inspect(target).attrs[key].history.has_changes() for key in
               ('name', 'brand', 'status', 'active_ingredients', 'usage_instructions')):
        return
    product = {column.name: getattr(target, column.name) for column in Product.__table__.columns}
    for row in connection.execute(RoutineEntry.__table__.select().where(
            RoutineEntry.product_id == target.id, RoutineEntry.user_id == target.user_id)).mappings():
        record(connection, {key: row[key] for key in ('id', 'user_id', 'revision', 'created_at', 'updated_at', *FIELDS)},
               'product_evidence_changed', product, attribution=writer(target))


@event.listens_for(RoutineConfigurationEvent, 'before_update')
@event.listens_for(RoutineConfigurationEvent, 'before_delete')
def immutable(mapper, connection, target):
    raise ValueError('Configuration events are immutable; only account purge may bulk-delete them')


class UserCalendarPolicy(Base):
    __tablename__ = 'user_calendar_policies'
    __table_args__ = (UniqueConstraint('user_id', 'revision', name='uq_calendar_policy_revision'),)
    id = Column(String(36), primary_key=True, default=gen_uuid)
    user_id = Column(String(36), ForeignKey('users.id'), nullable=False, index=True)
    revision = Column(Integer, nullable=False)
    timezone_name = Column(String(100), nullable=False)
    effective_at = Column(DateTime, nullable=False, default=utc_now)


event.listen(UserCalendarPolicy, 'before_update', immutable)
event.listen(UserCalendarPolicy, 'before_delete', immutable)
