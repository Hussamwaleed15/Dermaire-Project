from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, model_validator
from app.schemas.safety import SafetyState

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
