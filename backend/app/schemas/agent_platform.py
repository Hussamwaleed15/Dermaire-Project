from typing import Literal
from pydantic import BaseModel,ConfigDict,Field,model_validator


class SessionIn(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    longitudinal_read_consent: bool
    proposal_actions_consent: bool=False


class RevisionIn(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_revision: int=Field(ge=1)


class TurnIn(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    message: str=Field(min_length=1,max_length=1000)


class ActionIn(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_session_revision: int=Field(ge=1)
    kind: Literal["request_checkin","propose_followup","propose_routine_adjustment"]
    rationale: str=Field(min_length=3,max_length=500)
    routine_id: str | None=Field(None,min_length=1,max_length=36)
    routine_revision: int | None=Field(None,ge=1)

    @model_validator(mode="after")
    def routine_link(self):
        linked=self.routine_id is not None and self.routine_revision is not None
        if self.kind=="propose_routine_adjustment" and not linked:raise ValueError("Routine proposal requires an explicit routine revision")
        if self.kind!="propose_routine_adjustment" and (self.routine_id is not None or self.routine_revision is not None):raise ValueError("Unexpected routine link")
        return self


class ConfirmAction(BaseModel):
    model_config=ConfigDict(extra="forbid",strict=True)
    expected_revision: int=Field(ge=1)
    confirm: bool
