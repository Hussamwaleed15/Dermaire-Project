"""Additive Home observation contract; measurement fields retain legacy semantics."""
from typing import Literal
from datetime import datetime
from pydantic import BaseModel

class ObservationSummary(BaseModel):
    id: str
    created_at: datetime
    time_of_day: str
    kind: Literal["report_only", "report_and_measurement"]
    measurement_available: bool

class ObservationStatus(BaseModel):
    schema_version: Literal[1] = 1
    day_basis: Literal["UTC"] = "UTC"
    today_completed: bool
    recent: list[ObservationSummary]
