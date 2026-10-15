"""Patient-only bundle under one PostgreSQL MVCC snapshot, no historical replay."""
from datetime import datetime, timezone
from uuid import uuid4
from fastapi import HTTPException
from sqlalchemy import text
from app.schemas.clinical_snapshot import ClinicalSnapshotOut
from app.schemas.doctor_loop import ReviewStatusOut
from app.services.personal_skin_model import personal_skin_model
from app.services.doctor_loop import review_status
from app.api.v1.home import home_projection

CONSISTENCY = 'postgresql_repeatable_read_transaction'


def build_snapshot(db, user):
    if db.get_bind().dialect.name != 'postgresql' or db.execute(text('SHOW transaction_isolation')).scalar() != 'repeatable read':
        raise HTTPException(503, 'Consistent clinical bundle requires PostgreSQL repeatable read')
    now = datetime.now(timezone.utc)
    model = personal_skin_model(db, user, now)
    safety = model.safety
    safety.provenance.consistency = CONSISTENCY
    model.source_read_consistency = CONSISTENCY
    model.sources.safety = {**safety.model_dump(mode='json'), 'category':'deterministic_derived'}
    model.sources.doctor['consistency'] = CONSISTENCY
    review = review_status(db, user, patient_view=True, now=now, safety=safety)
    review['consistency'] = CONSISTENCY
    home = home_projection(db, user, now=now, safety=safety)
    home['consistency'] = CONSISTENCY
    home['as_of'] = now  # Canonical UTC serialization across the typed bundle.
    return ClinicalSnapshotOut(snapshot_id=str(uuid4()), patient_id=user.id, evaluated_at=now,
        safety=safety, review=ReviewStatusOut.model_validate(review), home=home, personal_skin_model=model)
