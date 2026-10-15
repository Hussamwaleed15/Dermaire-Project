from sqlalchemy import Column, String, DateTime, ForeignKey, UniqueConstraint
from app.core.database import Base
from app.models import utc_now


class CaptureObservation(Base):
    __tablename__ = 'capture_observations'
    __table_args__ = (UniqueConstraint('user_id', 'capture_id', 'checkin_id', name='uq_capture_observation_owner_pair'),)
    id = Column(String(36), primary_key=True)
    user_id = Column(String(36), ForeignKey('users.id'), nullable=False, index=True)
    capture_id = Column(String(36), ForeignKey('captures.id'), nullable=False, index=True)
    checkin_id = Column(String(36), ForeignKey('checkins.id'), nullable=False, index=True)
    created_at = Column(DateTime, default=utc_now, nullable=False)

