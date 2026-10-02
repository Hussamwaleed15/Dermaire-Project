from datetime import date, datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator


class ControlledChange(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: Literal["start_entry", "stop_entry", "change_schedule"]
    schedule: Literal["AM", "PM", "BOTH"] | None = None

    @model_validator(mode="after")
    def single_change(self):
        if (self.type != "stop_entry") != (self.schedule is not None):
            raise ValueError("Start/schedule changes require exactly one schedule; stop has no schedule")
        return self


class ExperimentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    routine_entry_id: str = Field(min_length=1, max_length=36)
    intervention: ControlledChange
    start_date: date
    target_days: int = Field(28, ge=7, le=90, strict=True)
    primary_concern: Literal["hydration", "texture", "redness"] = "texture"
    goal: str | None = Field(None, min_length=1, max_length=500)
    notes: str | None = Field(None, max_length=2000)


class ExperimentUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    # Core definitions can only be replaced as a whole while draft.
    definition: ExperimentCreate | None = None
    notes: str | None = Field(None, max_length=2000)


class FinishInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: Literal["completed", "stopped", "cancelled"]


class EvaluationResult(BaseModel):
    model_config = ConfigDict(extra="forbid")
    engine_version: Literal[2] = 2
    label: Literal["likely_associated_improvement", "likely_associated_worsening", "no_meaningful_change", "insufficient_evidence", "confounded_or_low_adherence"]
    evidence_strength: Literal["insufficient", "limited", "moderate"]
    evidence_summary: str
    comparison: dict
    adherence: dict
    confounders: dict
    observed_change: dict
    coverage: dict
    provenance: dict
    limitations: list[str]
    evaluated_at: datetime


class EvaluationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    experiment_id: str
    created_at: datetime
    result: EvaluationResult


class ExperimentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    user_id: str
    engine_version: int | None
    product_id: str | None
    routine_entry_id: str | None
    intervention: ControlledChange | None
    goal: str | None
    notes: str | None
    target_days: int
    current_day: int
    primary_concern: str
    status: str
    source: str | None
    start_date: datetime
    end_date: datetime | None
    activated_at: datetime | None
    stopped_at: datetime | None
    created_at: datetime
    definition_snapshot: dict | None
    coverage: dict
    result: EvaluationOut | None = None
    redness_delta_percent: float | None = None
    texture_delta_percent: float | None = None
    hydration_delta_percent: float | None = None
