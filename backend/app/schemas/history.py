from datetime import datetime
from typing import Literal
from pydantic import BaseModel
from app.schemas.routine import AdherenceOut


class AdherenceHistoryPage(BaseModel):
    schema_version: Literal[1] = 1
    day_basis: Literal['UTC'] = 'UTC'
    consistency: Literal['append_only_keyset_cutoff_not_atomic_snapshot'] = 'append_only_keyset_cutoff_not_atomic_snapshot'
    order: Literal['created_at_desc_id_desc'] = 'created_at_desc_id_desc'
    as_of: datetime
    items: list[AdherenceOut]
    next_cursor: str | None = None
