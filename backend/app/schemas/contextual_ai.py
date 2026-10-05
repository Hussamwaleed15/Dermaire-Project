"""Versioned backend grounding and constrained generation contracts."""
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, JsonValue, field_validator
from app.schemas.safety import SafetyEvaluation, SafetyState

Task = Literal['changes', 'worsening', 'tracking', 'routine', 'doctor_questions', 'unsupported']
Step = Literal['record_checkin', 'record_adherence', 'review_product_evidence', 'ask_doctor', 'seek_guidance']

class Strict(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)

class AssistanceRequest(Strict):
    message: str = Field(min_length=1, max_length=1000)
    task: Task | None = None

    @field_validator('message')
    @classmethod
    def nonblank(cls, value):
        if not value.strip():
            raise ValueError('A nonblank question is required')
        return value.strip()

class ContextFact(Strict):
    id: str
    source: str
    source_id: str
    field: str
    category: Literal['patient_reported', 'system_observed', 'deterministic_derived']
    value: JsonValue
    recorded_at: datetime | None
    freshness: Literal['fresh', 'stale', 'unknown', 'historical_reference']
    confidence: str | None = None
    provenance: dict[str, JsonValue] = Field(default_factory=dict)

class SourceAvailability(Strict):
    state: Literal['available', 'partial', 'missing']
    included: int
    truncated: bool = False

class SkinContext(Strict):
    schema_version: Literal['context-1.0'] = 'context-1.0'
    built_at: datetime
    facts: list[ContextFact]
    sources: dict[str, SourceAvailability]
    unknowns: list[str]
    safety: SafetyEvaluation

class InferenceSelection(Strict):
    code: Literal['tracking_gap']
    evidence_ids: list[str] = Field(min_length=1, max_length=5)

class ProviderSelection(Strict):
    """The provider generates a plan, never executable or unchecked medical prose."""
    task: Task
    fact_ids: list[str] = Field(max_length=12)
    inferred_points: list[InferenceSelection] = Field(max_length=1)
    next_steps: list[Step] = Field(min_length=1, max_length=4)
    escalation: SafetyState

class InferredPoint(Strict):
    category: Literal['ai_inferred'] = 'ai_inferred'
    statement: str
    evidence_ids: list[str]

class ProviderMetadata(Strict):
    provider: str | None = None
    model: str | None = None
    configured: bool
    invoked: bool
    availability: Literal['disabled', 'unconfigured', 'available', 'failed', 'not_invoked']
    mode: Literal['grounded_ai', 'degraded', 'safety_guard', 'narrowed']
    reason: str | None = None

class ClinicianDecision(Strict):
    """Current patient-visible decision, kept separate from engine evidence."""
    id: str
    sequence: int
    recommendation: SafetyState
    provenance: Literal['clinician_authored'] = 'clinician_authored'

class AssistanceResponse(Strict):
    schema_version: Literal['contextual-ai-1.0'] = 'contextual-ai-1.0'
    context_version: Literal['context-1.0'] = 'context-1.0'
    task: Task
    message: str
    grounded_facts_used: list[ContextFact]
    inferred_points: list[InferredPoint]
    uncertainties: list[str]
    next_steps: list[str]
    escalation: SafetyState
    authoritative_safety: SafetyEvaluation
    authoritative_clinician: ClinicianDecision | None = None
    metadata: ProviderMetadata
