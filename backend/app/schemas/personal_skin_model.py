"""Public deterministic, non-diagnostic read model contract."""
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, Field

Strength = Literal['none', 'limited', 'moderate']

class Evidence(BaseModel):
    source: Literal['checkin', 'daily_context', 'profile', 'product']
    id: str
    fields: list[str]
    recorded_at: datetime
    kind: Literal['user_reported', 'image_proxy', 'server_recorded']

class Finding(BaseModel):
    code: str
    subject: str
    direction: Literal['increased', 'decreased', 'stable', 'better', 'worse', 'same', 'associated']
    statement: str
    strength: Strength
    rule: str
    evidence: list[Evidence]
    reference_value: float | None = None
    recent_value: float | None = None
    threshold: float | None = None

class Sufficiency(BaseModel):
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

class PersonalSkinModel(BaseModel):
    schema_version: Literal[1] = 1
    derivation_version: Literal['psm-v1.0'] = 'psm-v1.0'
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
