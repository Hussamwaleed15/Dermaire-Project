from typing import Optional
from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session
from app.core.database import get_db
from app.core.exceptions import EntityNotFoundException, DermaireException
from app.api.deps import get_current_user, record_audit
from app.models import User, Experiment, Product, CheckIn
from app.services.baseline import baseline_snapshot, confirmed_measurement
from app.schemas import ExperimentCreate, ExperimentOut, ExperimentUpdate

router = APIRouter(prefix="/experiments", tags=["Skin Experiments & Baselines"])

@router.get("/current", response_model=Optional[ExperimentOut])
def get_current_experiment(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    experiment = db.query(Experiment).filter(
        Experiment.user_id == current_user.id,
        Experiment.status.in_(["active", "paused", "baseline"])
    ).order_by(Experiment.created_at.desc()).first()
    return experiment_projection(db, current_user.id, experiment)


def experiment_projection(db, user_id, experiment):
    if experiment is None:
        return None
    result = ExperimentOut.model_validate(experiment).model_dump()
    baseline = baseline_snapshot(db, user_id, before=experiment.created_at)
    latest = db.query(CheckIn).filter(CheckIn.experiment_id == experiment.id,
        CheckIn.user_id == user_id).order_by(CheckIn.created_at.desc(), CheckIn.id.desc()).first()
    confirmed = latest and confirmed_measurement(latest)
    for metric in ("hydration", "redness", "texture"):
        reference = baseline["metrics"].get(metric, {}).get("mean")
        score = getattr(latest, metric + "_score") if confirmed else None
        result[metric + "_delta_percent"] = round((score - reference) / reference * 100, 1) if reference and score is not None else None
    return result

@router.post("", response_model=ExperimentOut, status_code=status.HTTP_201_CREATED)
def start_experiment(
    payload: ExperimentCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    active_exp = db.query(Experiment).filter(
        Experiment.user_id == current_user.id,
        Experiment.status.in_(["active", "baseline"])
    ).first()
    if active_exp:
        raise DermaireException(
            message="You already have an active skin experiment running. Complete or pause it before starting a new one.",
            error_code="ACTIVE_EXPERIMENT_EXISTS",
            status_code=status.HTTP_409_CONFLICT
        )

    if payload.product_id:
        product = db.query(Product).filter(
            Product.id == payload.product_id,
            Product.user_id == current_user.id
        ).first()
        if not product:
            raise EntityNotFoundException("Product", payload.product_id)
        product.in_experiment = True

    experiment = Experiment(
        user_id=current_user.id,
        product_id=payload.product_id,
        target_days=payload.target_days,
        current_day=1,
        status="active",
        primary_concern=payload.primary_concern,
        redness_delta_percent=None,
        texture_delta_percent=None,
        hydration_delta_percent=None
    )
    db.add(experiment)
    db.commit()
    db.refresh(experiment)

    record_audit(db, current_user.id, "EXPERIMENT_STARTED", "experiments", {"experiment_id": experiment.id})
    return experiment_projection(db, current_user.id, experiment)

@router.patch("/{experiment_id}/toggle-pause", response_model=ExperimentOut)
def toggle_pause_experiment(
    experiment_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    experiment = db.query(Experiment).filter(
        Experiment.id == experiment_id,
        Experiment.user_id == current_user.id
    ).first()
    if not experiment:
        raise EntityNotFoundException("Experiment", experiment_id)

    if experiment.status == "active":
        experiment.status = "paused"
    elif experiment.status == "paused":
        experiment.status = "active"

    db.commit()
    db.refresh(experiment)
    record_audit(db, current_user.id, "EXPERIMENT_PAUSE_TOGGLED", "experiments", {"new_status": experiment.status})
    return experiment_projection(db, current_user.id, experiment)
