from pydantic import BaseModel, ConfigDict, Field


class OpenThread(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    access_id: str = Field(min_length=1, max_length=36)
    messaging_consent: bool


class SendMessage(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    body: str = Field(min_length=1, max_length=4000)


class ReadMessages(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    through_sequence: int = Field(ge=0)
