from datetime import datetime
from typing import List, Optional, Any, Dict, Literal, Annotated
from pydantic import BaseModel, EmailStr, Field, ConfigDict, field_validator

# ==================== User & Auth Schemas ====================

class UserRegister(BaseModel):
    email: EmailStr
    password: str = Field(..., min_length=8, description="Password must be at least 8 characters with letters and numbers")
    full_name: str = Field(..., min_length=2, max_length=100)
    accept_safety: bool = Field(..., description="User must accept medical safety & responsibility terms")

    model_config = ConfigDict(extra="forbid")

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user_id: str
    role: str
    full_name: str

class AcceptSafetyRequest(BaseModel):
    accepted: bool = Field(True)
    policy_version: str = Field("1.0")

ProfileText = Annotated[str, Field(min_length=1, max_length=200, pattern=r'\S')]

class SkinContext(BaseModel):
    age_band: Optional[Literal['under_18', '18_24', '25_34', '35_44', '45_54', '55_64', '65_plus', 'prefer_not_to_say']] = None
    sex: Optional[Literal['female', 'male', 'intersex', 'prefer_not_to_say']] = None
    sensitivities_allergies: Optional[List[ProfileText]] = Field(None, max_length=30)
    dermatologist_care: Optional[Literal['current', 'past', 'never', 'prefer_not_to_say']] = None
    medications_treatments: Optional[List[ProfileText]] = Field(None, max_length=30)
    primary_goals: Optional[List[ProfileText]] = Field(None, max_length=10)
    hormonal_context: Optional[List[Literal['puberty', 'pregnancy', 'postpartum', 'perimenopause', 'menopause', 'hormonal_contraception', 'hormone_therapy']]] = Field(None, max_length=7)
    hormonal_disclosure: Optional[Literal['disclosed', 'none_reported', 'prefer_not_to_say']] = None
    menstrual_context: Optional[Literal['regular', 'irregular', 'not_menstruating', 'not_applicable', 'prefer_not_to_say']] = None
    model_config = ConfigDict(extra='forbid')

class SkinProfileUpdate(BaseModel):
    profile_context: Optional[SkinContext] = None
    model_config = ConfigDict(extra='forbid')
    skin_type: Optional[str] = Field(None, pattern="^(dry|oily|combination|normal|sensitive)$")
    selected_goal: Optional[str] = Field(None, max_length=100)
    skin_concerns: Optional[List[ProfileText]] = Field(None, max_length=30)

class UserOut(BaseModel):
    id: str
    email: EmailStr
    full_name: str
    role: str
    safety_accepted: bool
    safety_accepted_at: Optional[datetime] = None
    skin_type: Optional[str] = None
    profile_context: Optional[SkinContext] = None
    selected_goal: Optional[str] = None
    skin_concerns: List[str]
    tokens_balance: int
    baseline_checkins_count: int
    created_at: datetime

    @field_validator('skin_concerns', mode='before')
    @classmethod
    def legacy_empty_concerns(cls, value):
        return [] if value is None else value

    model_config = ConfigDict(from_attributes=True)

# ==================== Product Schemas ====================

class ProductCreate(BaseModel):
    name: str = Field(..., min_length=2, max_length=150)
    brand: Optional[str] = Field(None, max_length=100)
    category: str = Field("treatment", pattern="^(cleanser|toner|serum|moisturizer|treatment|sunscreen|other)$")
    product_type: Optional[str] = Field(None, max_length=100)
    active_ingredients: List[str] = Field(default_factory=list)
    skin_concerns: List[str] = Field(default_factory=list)
    usage_instructions: str = Field("", max_length=1000)
    frequency_per_week: int = Field(7, ge=1, le=14)
    time_of_use: str = Field("evening", pattern="^(morning|evening|both|asNeeded)$")
    tags: List[str] = Field(default_factory=list)
    in_routine: bool = True
    in_experiment: bool = False
    notes: Optional[str] = Field(None, max_length=1000)
    start_date: Optional[datetime] = None

class ProductUpdate(BaseModel):
    name: Optional[str] = Field(None, min_length=2, max_length=150)
    brand: Optional[str] = Field(None, max_length=100)
    category: Optional[str] = Field(None, pattern="^(cleanser|toner|serum|moisturizer|treatment|sunscreen|other)$")
    product_type: Optional[str] = None
    active_ingredients: Optional[List[str]] = None
    skin_concerns: Optional[List[str]] = None
    usage_instructions: Optional[str] = None
    frequency_per_week: Optional[int] = Field(None, ge=1, le=14)
    time_of_use: Optional[str] = Field(None, pattern="^(morning|evening|both|asNeeded)$")
    status: Optional[str] = Field(None, pattern="^(active|inactive|archived)$")
    in_routine: Optional[bool] = None
    in_experiment: Optional[bool] = None
    notes: Optional[str] = None
    rating: Optional[float] = Field(None, ge=1.0, le=5.0)
    tags: Optional[List[str]] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None

class ProductOut(BaseModel):
    id: str
    user_id: str
    name: str
    brand: Optional[str] = None
    category: str
    product_type: Optional[str] = None
    active_ingredients: List[str]
    skin_concerns: List[str]
    usage_instructions: str
    frequency_per_week: int
    time_of_use: str
    status: str
    rating: Optional[float] = None
    in_routine: bool
    in_experiment: bool
    tags: List[str]
    notes: Optional[str] = None
    image_url: Optional[str] = None
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)

class ProductInteractionCheckRequest(BaseModel):
    ingredients: List[str] = Field(..., min_length=2, description="List of active ingredients to evaluate")

class ConflictItem(BaseModel):
    ingredient_a: str
    ingredient_b: str
    severity: str # conflict, caution, safe
    reason: str
    recommendation: str

class ProductInteractionCheckResponse(BaseModel):
    is_safe: bool
    risk_level: str # safe, conflict, unknown
    conflicts: List[ConflictItem]
    advice: str

# ==================== Experiment Schemas ====================

from app.schemas.experiments import ExperimentCreate, ExperimentUpdate, ExperimentOut

# ==================== CheckIn Schemas ====================

class SafetyDisclosure(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    severity: Optional[Literal["none", "mild", "moderate", "severe"]] = None
    pain: Optional[Literal["none", "mild", "moderate", "severe"]] = None
    breathing_difficulty: Optional[bool] = None
    facial_or_mouth_swelling: Optional[bool] = None
    eye_or_mucosal_involvement: Optional[bool] = None
    fever_or_systemic_illness: Optional[bool] = None
    rapid_spread: Optional[bool] = None
    extensive_blistering_or_peeling: Optional[bool] = None
    pus_or_hot_swollen_skin: Optional[bool] = None
    new_medication_or_product_reaction: Optional[bool] = None


class CheckInReport(BaseModel):
    model_config = ConfigDict(extra="forbid")
    safety: Optional[SafetyDisclosure] = None
    overall_change: Literal["better", "same", "worse"]
    symptoms: List[Literal["redness", "dryness", "itching", "burning", "breakouts", "sensitivity", "texture"]] = Field(default_factory=list, max_length=7)
    routine_status: Optional[Literal["followed", "partial", "skipped", "not_applicable"]] = None

class CheckInObservation(BaseModel):
    schema_version: Literal[1] = 1
    user_reported: Optional[CheckInReport] = None
    daily_context_date: str
    daily_context_id: Optional[str] = None
    provenance: Dict[str, str]

class CheckInCreate(BaseModel):
    experiment_id: Optional[str] = None
    time_of_day: str = Field("Morning", pattern="^(Morning|Evening)$")
    report: Optional[CheckInReport] = None
    hydration_score: Optional[float] = Field(None, ge=0.0, le=100.0)
    texture_score: Optional[float] = Field(None, ge=0.0, le=100.0)
    redness_score: Optional[float] = Field(None, ge=0.0, le=100.0)
    notes: Optional[str] = Field(None, max_length=1500)

class CheckInResponse(BaseModel):
    id: str
    user_id: str
    experiment_id: Optional[str] = None
    date_str: str
    time_of_day: str
    hydration_score: Optional[float] = None
    texture_score: Optional[float] = None
    redness_score: Optional[float] = None
    observation: Optional[CheckInObservation] = None
    notes: Optional[str] = None
    image_sas_url: Optional[str] = None
    ai_vision_analysis: Optional[Dict[str, Any]] = None
    tokens_earned: int = 0
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# ==================== Doctor & Consent Schemas ====================

class GenerateQrResponse(BaseModel):
    access_token: str
    qr_payload: str
    expires_at: datetime
    instructions: str

class ClaimAccessRequest(BaseModel):
    access_token: str

class ClinicalNoteCreate(BaseModel):
    content: str = Field(..., min_length=10, max_length=1500, description="Clinical note must be between 10 and 1500 characters")
    priority: str = Field("routine", pattern="^(routine|review|urgent)$")
    follow_up: Optional[str] = Field(None, max_length=100)

class ClinicalNoteOut(BaseModel):
    id: str
    doctor_id: str
    patient_id: str
    content: str
    priority: str
    follow_up: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

class DoctorPatientOut(BaseModel):
    patient_id: str
    full_name: str
    email: EmailStr
    skin_type: Optional[str] = None
    selected_goal: Optional[str] = None
    last_check_in: str
    active_experiment: Optional[str] = None
    priority: str
    active_products_count: int
    notes: List[ClinicalNoteOut]

class AuditLogOut(BaseModel):
    id: str
    actor_id: str
    action: str
    target_resource: str
    details: Dict[str, Any]
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)

# ==================== Rewards Schemas ====================

class RewardBalanceOut(BaseModel):
    tokens_balance: int
    can_redeem: bool
    rewards_available: List[Dict[str, Any]]

class RewardRedeemRequest(BaseModel):
    reward_id: str = Field(..., description="ID or title of the reward tier")

class RewardRedemptionOut(BaseModel):
    id: str
    reward_title: str
    tokens_spent: int
    remaining_balance: int
    created_at: datetime

# ==================== Chat & AI Schemas ====================

class ChatMessageRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=2000)
    session_id: Optional[str] = None

class ChatMessageResponse(BaseModel):
    reply: str
    kind: str # education, uncertainty, escalation
    escalation_triggered: bool
    safety_details: Optional[Dict[str, Any]] = None
    azure_model_used: str
