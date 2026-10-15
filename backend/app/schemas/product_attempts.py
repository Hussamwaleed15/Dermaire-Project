from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, model_validator
from app.schemas import ProductOut


class ProductCreateAttemptOut(BaseModel):
    model_config = ConfigDict(extra='forbid')
    schema_version: Literal[1] = 1
    operation: Literal['product_create'] = 'product_create'
    attempt_id: str
    owner_id: str
    actor_id: str
    status: Literal['unknown', 'committed', 'expired']
    result_availability: Literal['unknown', 'retained', 'erased', 'expired'] = 'unknown'
    resource_id: str | None = None
    resource_revision: int | None = None
    recorded_at: datetime | None = None
    expires_at: datetime | None = None
    result: ProductOut | None = None

    @model_validator(mode='after')
    def scope(self):
        if self.owner_id != self.actor_id:
            raise ValueError('Product create actor must be owner')
        if self.status == 'unknown':
            if self.result_availability != 'unknown':
                raise ValueError('Unknown availability')
            if any(v is not None for v in (self.resource_id, self.resource_revision, self.recorded_at, self.expires_at, self.result)):
                raise ValueError('Unknown cannot assert a result')
        else:
            if not self.resource_id or self.resource_revision != 1 or self.recorded_at is None or self.expires_at is None or self.expires_at <= self.recorded_at:
                raise ValueError('Incomplete creation receipt')
            if self.status == 'expired' and (self.result is not None or self.result_availability != 'expired'):
                raise ValueError('Expired result unavailable')
            if self.status == 'committed' and self.result_availability not in ('retained', 'erased'):
                raise ValueError('Committed availability invalid')
            if self.result_availability == 'erased' and self.result is not None:
                raise ValueError('Erased content unavailable')
            if self.status == 'committed' and self.result_availability == 'retained' and (self.result is None or self.result.id != self.resource_id or self.result.user_id != self.owner_id or self.result.revision != self.resource_revision):
                raise ValueError('Result differs from original creation')
        return self
