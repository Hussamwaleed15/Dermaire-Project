from datetime import date, datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field

class RoutineCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    product_id: str = Field(min_length=1, max_length=36)
    schedule: Literal["AM", "PM", "BOTH"]
    frequency: Literal["daily"]
    start_date: date
    instructions: str | None = Field(default=None, max_length=2000)
    am_order: int = Field(default=0, ge=0, le=100)
    pm_order: int = Field(default=0, ge=0, le=100)

class RoutineUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schedule: Literal["AM", "PM", "BOTH"] | None = None
    frequency: Literal["daily"] | None = None
    instructions: str | None = Field(default=None, max_length=2000)
    am_order: int | None = Field(default=None, ge=0, le=100)
    pm_order: int | None = Field(default=None, ge=0, le=100)
    active: Literal[False] | None = None

class RoutineOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    product_id: str
    product_name: str
    schedule: Literal["AM", "PM", "BOTH"]
    frequency: Literal["daily"]
    start_date: date
    end_date: date | None
    active: bool
    instructions: str | None
    am_order: int
    pm_order: int
    source: Literal["user_configured"]
    created_at: datetime
    updated_at: datetime

class AdherenceCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    routine_entry_id: str = Field(min_length=1, max_length=36)
    date: date
    slot: Literal["AM", "PM"]
    status: Literal["completed", "skipped"]
    note: str | None = Field(default=None, max_length=2000)

class AdherenceOut(AdherenceCreate):
    model_config = ConfigDict(from_attributes=True)
    id: str
    source: Literal["user_reported"]
    created_at: datetime
    configuration_snapshot: dict
