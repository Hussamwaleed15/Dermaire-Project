from datetime import date, datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator

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
    day_basis: Literal["UTC"] = "UTC"
    configuration_history: Literal["current_with_adherence_snapshots"] = "current_with_adherence_snapshots"
    model_config = ConfigDict(from_attributes=True)
    revision: int
    revision_protected: bool
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

class AdherenceReceipt(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal[1] = 1
    operation: Literal["routine_adherence"]
    attempt_id: str
    owner_id: str
    actor_id: str
    resource_id: str
    configuration_revision: int = Field(ge=1)
    status: Literal["committed", "expired"]
    committed_at: datetime
    expires_at: datetime

    @model_validator(mode="after")
    def scope(self):
        if self.owner_id != self.actor_id or self.resource_id != self.attempt_id or self.expires_at <= self.committed_at:
            raise ValueError("Inconsistent adherence receipt scope")
        return self


class AdherenceOut(AdherenceCreate):
    day_basis: Literal["UTC"] = "UTC"
    receipt: AdherenceReceipt | None = None
    model_config = ConfigDict(from_attributes=True)
    id: str
    source: Literal["user_reported"]
    created_at: datetime
    configuration_snapshot: dict


class AdherenceAttemptLookup(BaseModel):
    schema_version: Literal[1] = 1
    operation: Literal["routine_adherence"]
    attempt_id: str
    owner_id: str
    actor_id: str
    status: Literal["unknown", "committed", "expired"]
    resource_id: str | None = None
    configuration_revision: int | None = None
    committed_at: datetime | None = None
    expires_at: datetime | None = None
    result: AdherenceOut | None = None

    @model_validator(mode="after")
    def scope(self):
        if self.owner_id != self.actor_id:
            raise ValueError("Adherence actor must be owner")
        if self.status == "unknown":
            if any(value is not None for value in (self.result,self.resource_id,self.configuration_revision,self.committed_at,self.expires_at)):
                raise ValueError("Unknown cannot assert commitment")
        else:
            if self.resource_id != self.attempt_id or self.committed_at is None or self.expires_at is None or self.configuration_revision is None or self.configuration_revision < 1:
                raise ValueError("Incomplete adherence receipt")
            if self.status == "expired" and self.result is not None:
                raise ValueError("Expired must reconcile history")
            if self.status == "committed":
                result=self.result
                if result is None or result.id != self.resource_id or result.receipt is None or result.receipt.owner_id != self.owner_id or result.receipt.attempt_id != self.attempt_id or result.receipt.status != "committed" or result.receipt.configuration_revision != self.configuration_revision:
                    raise ValueError("Result differs from committed attempt")
        return self
