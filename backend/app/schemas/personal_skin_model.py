"""Public deterministic, non-diagnostic read model contract."""
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, Field, model_validator, ConfigDict

from app.schemas.safety import SafetyEvaluation

Strength = Literal['none', 'limited', 'moderate']

class Evidence(BaseModel):
    source: Literal['checkin', 'daily_context', 'profile', 'product', 'adherence']
    id: str
    fields: list[str]
    recorded_at: datetime
    kind: Literal['user_reported', 'image_proxy', 'server_recorded']
    category: Literal['patient_reported', 'system_observed'] = 'patient_reported'

    @model_validator(mode='after')
    def provenance_category(self):
        self.category = 'patient_reported' if self.kind == 'user_reported' else 'system_observed'
        return self

class Finding(BaseModel):
    code: str
    subject: str
    direction: Literal['increased', 'decreased', 'stable', 'better', 'worse', 'same', 'associated']
    statement: str
    strength: Strength
    rule: str
    evidence: list[Evidence]
    evidence_count: int = 0
    latest_evidence_at: datetime | None = None
    confidence: Strength = 'none'
    caveats: list[str] = Field(default_factory=list)
    category: Literal['deterministic_derived'] = 'deterministic_derived'
    reference_value: float | None = None
    recent_value: float | None = None
    threshold: float | None = None

class Sufficiency(BaseModel):
    proxy_measurement_days: int = 0
    latest_proxy_measurement_at: datetime | None = None
    confirmed_days: int
    report_days: int
    measurement_days: int
    excluded_checkins: int
    latest_evidence_at: datetime | None
    age_days: int | None
    recency: Literal['missing', 'fresh', 'stale']
    baseline_ready: bool
    reasons: list[str]

class ProfileInput(BaseModel):
    available: bool
    primary_goals: list[str] = Field(default_factory=list)
    evidence: list[Evidence] = Field(default_factory=list)

class ProductInput(BaseModel):
    id: str
    status: str
    evidence: Evidence

class IntegratedSources(BaseModel):
    model_config = ConfigDict(extra='forbid')
    profile: dict = Field(default_factory=dict)
    history: dict = Field(default_factory=dict)
    baseline: dict = Field(default_factory=dict)
    daily_context: dict = Field(default_factory=dict)
    routine: dict = Field(default_factory=dict)
    experiments: list[dict] = Field(default_factory=list)
    measurements: dict = Field(default_factory=dict)
    product_intelligence: dict = Field(default_factory=dict)
    safety: dict = Field(default_factory=dict)
    doctor: dict = Field(default_factory=dict)


class AssistantLayer(BaseModel):
    model_config = ConfigDict(extra='forbid')
    category: Literal['ai_inferred'] = 'ai_inferred'
    authoritative: Literal[False] = False
    included: Literal[False] = False


class PersonalSkinModel(BaseModel):
    schema_version: Literal[2] = 2
    contract_version: Literal['personal-skin-model-2.0'] = 'personal-skin-model-2.0'
    derivation_version: Literal['psm-v2.0'] = 'psm-v2.0'
    generated_at: datetime
    status: Literal['no_data', 'insufficient_data', 'no_meaningful_change', 'meaningful_change', 'stale']
    statement: str
    strength: Strength
    changing: list[Finding]
    stable: list[Finding]
    associations: list[Finding]
    sufficiency: Sufficiency
    profile: ProfileInput
    products: list[ProductInput]
    limitations: list[str]

    safety: SafetyEvaluation | None = None
    sources: IntegratedSources = Field(default_factory=IntegratedSources)
    summaries: dict = Field(default_factory=dict)
    unknowns: list[str] = Field(default_factory=list)
    assistant_layer: AssistantLayer = Field(default_factory=AssistantLayer)
