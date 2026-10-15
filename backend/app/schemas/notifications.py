from typing import Literal
from pydantic import BaseModel, ConfigDict, Field, field_validator
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

Kind = Literal["message", "follow_up", "comparison", "routine"]


class PreferencesIn(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    expected_revision: int = Field(ge=0)
    enabled_kinds: list[Kind] = Field(max_length=4)
    push_enabled: bool = False
    timezone: str = Field(max_length=100)
    quiet_start: int = Field(ge=0, lt=1440)
    quiet_end: int = Field(ge=0, lt=1440)

    @field_validator("timezone")
    @classmethod
    def known_zone(cls, value):
        try: ZoneInfo(value)
        except (ZoneInfoNotFoundError, ValueError): raise ValueError("Unknown IANA timezone") from None
        return value

    @field_validator("enabled_kinds")
    @classmethod
    def unique_kinds(cls, value):
        if len(set(value)) != len(value): raise ValueError("Duplicate kind")
        return value


class DeviceIn(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    installation_id: str = Field(min_length=16, max_length=128, pattern=r"^[A-Za-z0-9_-]+$")
    token: str = Field(min_length=16, max_length=4096)
    platform: Literal["ios", "android", "web"]
    push_consent: bool
