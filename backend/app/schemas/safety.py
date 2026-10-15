from datetime import datetime
from typing import Literal, Any
from pydantic import BaseModel, ConfigDict
SafetyState = Literal["track", "low_risk_self_care", "doctor_review", "urgent"]
class SafetyReason(BaseModel):
    model_config = ConfigDict(extra="forbid")
    code: str
    state: SafetyState
    summary: str
    evidence: list[dict[str, Any]]
class SafetyProvenance(BaseModel):
    model_config = ConfigDict(extra="forbid")
    schema_version: Literal[1] = 1
    evaluation_id: str
    source: Literal["deterministic_safety_engine"] = "deterministic_safety_engine"
    mode: Literal["dynamic_current"] = "dynamic_current"
    as_of: datetime
    source_revision: str
    consistency: Literal["multiple_reads_not_atomic_snapshot"] = "multiple_reads_not_atomic_snapshot"
    report_freshness: Literal["current", "stale", "missing"]
    latest_report_at: datetime | None
    evidence_completeness: Literal["partial", "screen_complete"]
    clinical_clearance: Literal[False] = False

class SafetyEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    provenance: SafetyProvenance | None = None
    status: SafetyState
    engine_version: Literal["safety-1.0"] = "safety-1.0"
    evaluated_at: datetime
    reasons: list[SafetyReason]
    evidence_status: dict[str, Any]
    guidance: str
    limitations: list[str]
