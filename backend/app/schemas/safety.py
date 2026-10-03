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
class SafetyEvaluation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    status: SafetyState
    engine_version: Literal["safety-1.0"] = "safety-1.0"
    evaluated_at: datetime
    reasons: list[SafetyReason]
    evidence_status: dict[str, Any]
    guidance: str
    limitations: list[str]
