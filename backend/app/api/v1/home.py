"""Read-only Home projection. No client counters or seeded measurements."""
from datetime import datetime, timezone
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User, Experiment, Product, CheckIn
from app.services.baseline import confirmed_measurement
from app.services.safety import evaluate_safety
from app.schemas.home import ObservationStatus
from app.api.v1.experiments import experiment_projection

router = APIRouter(prefix="/home", tags=["Home"])


@router.get("")
def get_home(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    now = datetime.now(timezone.utc)
    experiment = db.query(Experiment).filter(
        Experiment.user_id == current_user.id,
        Experiment.status.in_(["active", "paused", "baseline"])
    ).order_by(Experiment.created_at.desc(), Experiment.id.desc()).first()
    summary = None
    if experiment:
        projection = experiment_projection(db, current_user.id, experiment)
        product = db.query(Product).filter(Product.id == experiment.product_id,
            Product.user_id == current_user.id).first()
        summary = {key: getattr(projection, key) for key in (
            "id", "status", "current_day", "target_days", "primary_concern",
            "redness_delta_percent", "texture_delta_percent", "hydration_delta_percent")}
        summary["product_name"] = product.name if product else None
    rows = db.query(CheckIn).filter(CheckIn.user_id == current_user.id).order_by(
        CheckIn.created_at.desc(), CheckIn.id.desc()).all()
    confirmed = [row for row in rows if confirmed_measurement(row)]
    observations = [row for row in rows if isinstance(row.observation, dict)
        and row.observation.get("schema_version") == 1
        and isinstance(row.observation.get("user_reported"), dict)]
    def utc(recorded):
        return recorded.replace(tzinfo=timezone.utc) if recorded.tzinfo is None else recorded.astimezone(timezone.utc)
    return {"as_of": now.isoformat(), "date": now.date().isoformat(),
        "consistency": "multiple_reads_not_atomic_snapshot",
        "safety": evaluate_safety(db, current_user, now).model_dump(mode="json"),
        "experiment": summary,
        "observation_status": ObservationStatus.model_validate({
            "schema_version": 1, "day_basis": "UTC",
            "today_completed": any(utc(row.created_at).date() == now.date() for row in observations),
            "recent": [{"id": row.id, "created_at": utc(row.created_at).isoformat(),
                "time_of_day": row.time_of_day,
                "kind": "report_and_measurement" if confirmed_measurement(row) else "report_only",
                "measurement_available": confirmed_measurement(row)} for row in observations[:2]]}).model_dump(mode="json"),
        "today_checked_in": any(utc(row.created_at).date() == now.date() for row in confirmed),
        "journal": [{"id": row.id, "created_at": row.created_at.isoformat(),
            "time_of_day": row.time_of_day,
            "measurement_source": row.ai_vision_analysis["measurement_source"],
            "hydration_score": row.hydration_score, "texture_score": row.texture_score,
            "redness_score": row.redness_score} for row in confirmed[:2]]}
