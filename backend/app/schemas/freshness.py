from datetime import datetime
from typing import Literal
from pydantic import BaseModel


class EvidenceFreshness(BaseModel):
    schema_version: Literal[1] = 1
    as_of: datetime
    basis: Literal['elapsed_UTC_duration'] = 'elapsed_UTC_duration'
    age_days_basis: Literal['UTC_calendar_difference'] = 'UTC_calendar_difference'
    threshold_days: Literal[14] = 14
    latest_at: datetime | None
    age_days: int | None
    state: Literal['missing', 'fresh', 'stale', 'unknown']
