from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, model_validator
from app.schemas.safety import SafetyEvaluation
from app.schemas.doctor_loop import ReviewStatusOut
from app.schemas.personal_skin_model import PersonalSkinModel


class ClinicalSnapshotOut(BaseModel):
    model_config = ConfigDict(extra='forbid')
    schema_version: Literal[1] = 1
    snapshot_id: str
    patient_id: str
    evaluated_at: datetime
    consistency: Literal['postgresql_repeatable_read_transaction'] = 'postgresql_repeatable_read_transaction'
    atomic_scope: Literal['database_rows_visible_in_one_transaction'] = 'database_rows_visible_in_one_transaction'
    external_sources: Literal['not_fetched_not_atomic'] = 'not_fetched_not_atomic'
    replayable: Literal[False] = False
    clinical_clearance: Literal[False] = False
    safety: SafetyEvaluation
    review: ReviewStatusOut
    home: dict
    personal_skin_model: PersonalSkinModel
    limitations: list[str] = [
        'Evaluated_at is the shared evaluation clock, not an exact database commit watermark.',
        'The bundle is current at its transaction snapshot; later writes require a new read.',
        'No external service, image bytes, AI inference, future clock or standalone endpoint is included in this atomicity claim.',
        'The identifier is correlation only, not a reusable token or clinical clearance.'
    ]

    @model_validator(mode='after')
    def consistent_safety(self):
        safety=self.safety.model_dump(mode='json')
        if self.review.patient_id != self.patient_id or self.review.safety.model_dump(mode='json') != safety or self.home.get('safety') != safety or self.personal_skin_model.safety.model_dump(mode='json') != safety:
            raise ValueError('Bundle scopes and Safety must agree')
        if self.safety.evaluated_at != self.evaluated_at or self.review.as_of != self.evaluated_at or self.personal_skin_model.generated_at != self.evaluated_at or self.home.get('as_of') != self.evaluated_at:
            raise ValueError('Bundle evaluation clocks must agree')
        return self
