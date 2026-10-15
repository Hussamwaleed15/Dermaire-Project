from datetime import datetime, timezone
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator, field_validator
from app.schemas.safety import SafetyState, SafetyEvaluation
from app.schemas import ClinicalNoteOut

class ReviewActionCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, strict=True)
    state: Literal["pending", "in_review", "reviewed", "follow_up_needed"]
    recommendation: SafetyState | None = None
    rationale: str | None = Field(None, min_length=10, max_length=1500)
    patient_visible: bool = False
    expected_sequence: int = Field(ge=0)

    @model_validator(mode="after")
    def decision_requires_rationale(self):
        if self.recommendation and not self.rationale:
            raise ValueError("A clinician decision requires a rationale")
        return self


class AccessGrantOut(BaseModel):
    id: str
    patient_id: str
    doctor_id: str | None = None
    granted_by: str | None = None
    status: Literal["pending", "active", "revoked", "expired"]
    created_at: datetime | None = None
    expires_at: datetime
    claimed_at: datetime | None = None
    revoked_at: datetime | None = None
    revoked_by: str | None = None
    doctor_name: str | None = None
    consent_version: Literal[2] | None = None
    consent_source: Literal["explicit_patient_intent", "legacy_view_only"]
    view_consent: bool
    export_consent: bool
    scopes: list[Literal["VIEW", "EXPORT"]]
    effective_scopes: list[Literal["VIEW", "EXPORT"]]

    @field_validator("created_at", "expires_at", "claimed_at", "revoked_at")
    @classmethod
    def utc_times(cls, value):
        return value.replace(tzinfo=timezone.utc) if value and value.tzinfo is None else value.astimezone(timezone.utc) if value else None


class ReviewActionOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal["clinical-review-1.0"] = "clinical-review-1.0"
    id: str
    sequence: int = Field(ge=1)
    patient_id: str
    doctor_id: str
    access_id: str
    state: Literal["pending", "in_review", "reviewed", "follow_up_needed"]
    recommendation: SafetyState | None = None
    rationale: str | None = None
    patient_visible: bool
    created_at: datetime
    provenance: Literal["clinician_authored"] = "clinician_authored"
    safety_at_review: SafetyEvaluation
    diverges_from_current_safety: bool
    lower_than_current_safety: bool
    urgent_safety_preserved: bool
    is_current: bool | None = None
    resource_revision: int = Field(ge=1)
    safety_at_review_kind: Literal["historical_saved"] = "historical_saved"
    current_safety_evaluation_id: str | None = None
    clinical_clearance: Literal[False] = False

    @field_validator("created_at")
    @classmethod
    def utc_time(cls, value):
        return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)

    @model_validator(mode="after")
    def immutable_sequence_revision(self):
        if self.sequence != self.resource_revision:
            raise ValueError("Review revision must equal its immutable sequence")
        return self


class ReviewStatusOut(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal["doctor-loop-2.0"] = "doctor-loop-2.0"
    patient_id: str
    state: Literal["not_requested", "pending", "in_review", "reviewed", "follow_up_needed"]
    latest_sequence: int = Field(ge=0)
    changed_at: datetime | None = None
    changed_by: str | None = None
    as_of: datetime
    consistency: Literal["multiple_reads_not_atomic_snapshot"]
    current_decision_visibility: Literal["available", "absent", "not_available_to_patient"]
    safety: SafetyEvaluation
    current_decision: ReviewActionOut | None = None
    history: list[ReviewActionOut]
    notes: list[ClinicalNoteOut]
    access: list[AccessGrantOut] | None = None

    @field_validator("as_of", "changed_at")
    @classmethod
    def utc_times(cls, value):
        return value.replace(tzinfo=timezone.utc) if value and value.tzinfo is None else value.astimezone(timezone.utc) if value else None

    @model_validator(mode="after")
    def current_and_history(self):
        if self.current_decision and (self.current_decision.patient_id != self.patient_id or self.current_decision.sequence != self.latest_sequence or self.current_decision.is_current is not True):
            raise ValueError("Current decision must match latest sequence")
        if self.current_decision_visibility != "available" and self.current_decision is not None:
            raise ValueError("Unavailable decision must not expose content")
        if self.current_decision_visibility == "available" and self.current_decision is None:
            raise ValueError("Available decision requires content")
        if any(row.patient_id != self.patient_id or row.is_current != (row.sequence == self.latest_sequence) for row in self.history):
            raise ValueError("History owner/current state mismatch")
        if any(note.patient_id != self.patient_id for note in self.notes) or any(grant.patient_id != self.patient_id for grant in self.access or []):
            raise ValueError("Clinical projection owner mismatch")
        if any(a.sequence <= b.sequence for a,b in zip(self.history,self.history[1:])):
            raise ValueError("History must be newest sequence first")
        return self


class DoctorPatientDetailOut(BaseModel):
    patient_id: str
    full_name: str
    access: AccessGrantOut
    review: ReviewStatusOut


class TimelineItemOut(BaseModel):
    id: str
    source: str
    source_id: str
    field: str
    category: Literal["patient_reported", "system_observed", "deterministic_derived", "clinician_authored", "ai_inferred"]
    recorded_at: datetime | None = None
    provenance: dict
    data: dict


class DoctorTimelineOut(BaseModel):
    schema_version: Literal["doctor-timeline-2.0"]
    built_at: datetime
    items: list[TimelineItemOut]
    unknowns: list[str]
    derived_source_availability: dict[str, dict]
    safety: SafetyEvaluation
    limitations: list[str]
    total: int = Field(ge=0)
    offset: int = Field(ge=0)
    limit: int = Field(ge=1, le=200)
    next_offset: int | None = None
