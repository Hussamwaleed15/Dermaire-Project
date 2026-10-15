from sqlalchemy import Column,String,Integer,DateTime,ForeignKey,JSON,CheckConstraint
from app.core.database import Base


class ProductMutationAttempt(Base):
    __tablename__="product_mutation_attempts"
    __table_args__=(CheckConstraint("operation IN ('patch','delete')",name="ck_product_mutation_operation"),)
    id=Column(String(36),primary_key=True)
    user_id=Column(String(36),ForeignKey("users.id"),nullable=False,index=True)
    resource_id=Column(String(36),nullable=False,index=True)
    operation=Column(String(10),nullable=False)
    payload_hash=Column(String(64),nullable=False)
    resource_revision=Column(Integer,nullable=False)
    result_snapshot=Column(JSON(none_as_null=True),nullable=True)
    recorded_at=Column(DateTime,nullable=False)
