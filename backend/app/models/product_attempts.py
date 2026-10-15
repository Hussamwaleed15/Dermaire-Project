from sqlalchemy import Column, String, Integer, DateTime, ForeignKey, JSON
from app.core.database import Base


class ProductCreateAttempt(Base):
    __tablename__ = 'product_create_attempts'
    id = Column(String(36), primary_key=True)
    user_id = Column(String(36), ForeignKey('users.id'), nullable=False, index=True)
    # No product FK: deletion must not destroy proof of the original CREATE.
    resource_id = Column(String(36), nullable=False)
    resource_revision = Column(Integer, nullable=False)
    payload_hash = Column(String(64), nullable=False)
    result_snapshot = Column(JSON(none_as_null=True), nullable=True)
    recorded_at = Column(DateTime, nullable=False)
