"""Explicit patient-selected references; no measurement or inferred relationship."""
from datetime import datetime
from typing import Literal
from pydantic import BaseModel, ConfigDict, field_validator


class CaptureObservationSelect(BaseModel):
    model_config = ConfigDict(extra='forbid')
    associated: Literal[True]

    @field_validator('associated', mode='before')
    @classmethod
    def explicit_boolean(cls, value):
        if value is not True:
            raise ValueError('Explicit association selection is required')
        return value


class CaptureObservationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    schema_version: Literal[1] = 1
    id: str
    capture_id: str
    checkin_id: str
    created_at: datetime
    source: Literal['patient_selected'] = 'patient_selected'
    clinical_inference: Literal[False] = False

