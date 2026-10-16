from datetime import datetime, date
from typing import Literal
from pydantic import BaseModel, Field, ConfigDict
from app.schemas.routine import AdherenceOut


class AdherenceHistoryPage(BaseModel):
    schema_version: Literal[1] = 1
    day_basis: Literal['UTC'] = 'UTC'
    consistency: Literal['append_only_keyset_cutoff_not_atomic_snapshot'] = 'append_only_keyset_cutoff_not_atomic_snapshot'
    order: Literal['created_at_desc_id_desc'] = 'created_at_desc_id_desc'
    as_of: datetime
    items: list[AdherenceOut]
    next_cursor: str | None = None


class ConfigurationEventOut(BaseModel):
    model_config = {'from_attributes': True}
    id: str
    routine_entry_id: str
    source_product_id: str
    kind: str
    schema_version: int
    snapshot: dict
    created_at: datetime


class ConfigurationHistoryPage(BaseModel):
    schema_version: Literal[1] = 1
    day_basis: Literal['UTC'] = 'UTC'
    coverage: Literal['prospective_orm_writes_no_backfill'] = 'prospective_orm_writes_no_backfill'
    coverage_since: datetime | None = None
    last_evidence_at: datetime | None = None
    freshness: Literal['event_history_not_current_state_verification'] = 'event_history_not_current_state_verification'
    consistency: Literal['append_only_keyset_cutoff_not_atomic_snapshot'] = 'append_only_keyset_cutoff_not_atomic_snapshot'
    as_of: datetime
    items: list[ConfigurationEventOut]
    next_cursor: str | None = None


class CalendarPolicyChange(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    timezone: str = Field(min_length=1, max_length=100)
    expected_revision: int = Field(ge=0, le=2147483647)


class CalendarPolicyOut(BaseModel):
    schema_version: Literal[1] = 1
    revision: int
    timezone: str
    effective_at: datetime | None
    local_today: date
    adherence_day_basis: Literal['UTC'] = 'UTC'
    historical_reinterpretation: Literal[False] = False
    policy: Literal['forward_only_labels_at_committed_instant'] = 'forward_only_labels_at_committed_instant'
    reminder_policy: Literal['explicit_per_reminder_timezone_fold_and_gap'] = 'explicit_per_reminder_timezone_fold_and_gap'
