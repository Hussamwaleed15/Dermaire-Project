from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator


class Schedule(BaseModel):
    model_config=ConfigDict(extra="forbid")
    local_due: datetime
    timezone: str=Field(min_length=1,max_length=100)
    fold: int | None=Field(None,ge=0,le=1,strict=True)


class CreatePlan(Schedule):
    access_id: str=Field(min_length=1,max_length=36)
    kind: Literal["follow_up","comparison"]
    purpose: str=Field(min_length=10,max_length=1000)
    source_type: Literal["routine","experiment","observation"] | None=None
    source_id: str | None=Field(None,min_length=1,max_length=36)
    baseline_capture_id: str | None=Field(None,min_length=1,max_length=36)

    @model_validator(mode="after")
    def valid_source(self):
        if bool(self.source_type)!=bool(self.source_id): raise ValueError("Source type/id must be supplied together")
        if self.kind=="comparison" and (not self.source_id or not self.baseline_capture_id):
            raise ValueError("Comparison requires an explicit source and baseline capture")
        return self


class RevisePlan(Schedule):
    expected_revision: int=Field(ge=1,strict=True)


class ConfirmPlan(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_revision: int=Field(ge=1)
    consent: bool


class CancelPlan(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_revision: int=Field(ge=1)
    reason: str=Field(min_length=3,max_length=500)


class AttachCapture(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_revision: int=Field(ge=1)
    capture_id: str=Field(min_length=1,max_length=36)


class ReviewPlan(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_revision: int=Field(ge=1)
    assessment: str=Field(min_length=10,max_length=1500)
