from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models import User, Experiment, ExperimentEvaluation, Product
from app.schemas.experiments import ExperimentCreate, ExperimentUpdate, ExperimentOut, FinishInput, EvaluationOut
from app.services import experiments as service
from app.services.routine import lock_owner

router = APIRouter(prefix="/experiments", tags=["Controlled experiments v2"])

def experiment_projection(db, user_id, row):
    if row is None:
        return None
    data = {name: getattr(row, name) for name in ExperimentOut.model_fields if hasattr(row, name)}
    # Legacy deltas are never promoted to v2 evidence.
    for metric in ("redness", "texture", "hydration"):
        data[metric + "_delta_percent"] = None
    if row.engine_version != 2:
        from app.services.baseline import baseline_snapshot, confirmed_measurement
        from app.models import CheckIn
        baseline = baseline_snapshot(db, user_id, before=row.created_at)
        latest = db.query(CheckIn).filter_by(user_id=user_id, experiment_id=row.id).order_by(CheckIn.created_at.desc(), CheckIn.id.desc()).first()
        for metric in ("hydration", "texture", "redness"):
            reference = baseline["metrics"].get(metric, {}).get("mean")
            score = getattr(latest, metric+"_score") if latest and confirmed_measurement(latest) else None
            data[metric+"_delta_percent"] = round((score-reference)/reference*100, 1) if reference and score is not None else None
    data["current_day"] = min(row.target_days, max(1, ((row.stopped_at.date() if row.stopped_at else service.today())-row.start_date.date()).days+1)) if row.activated_at else row.current_day
    data["coverage"] = service.coverage(db, row)
    data["result"] = db.query(ExperimentEvaluation).filter_by(user_id=user_id, experiment_id=row.id).order_by(ExperimentEvaluation.created_at.desc(), ExperimentEvaluation.id.desc()).first()
    return ExperimentOut.model_validate(data)

@router.get("/current", response_model=ExperimentOut | None)
def current(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.query(Experiment).filter(Experiment.user_id == user.id, Experiment.status.in_(["active", "paused", "baseline"])).order_by(Experiment.created_at.desc(), Experiment.id.desc()).first()
    return experiment_projection(db, user.id, row)

@router.get("", response_model=list[ExperimentOut])
def listing(limit: int = Query(100, ge=1, le=200), offset: int = Query(0, ge=0), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(Experiment).filter_by(user_id=user.id).order_by(Experiment.created_at.desc(), Experiment.id.desc()).offset(offset).limit(limit).all()
    return [experiment_projection(db, user.id, row) for row in rows]

@router.post("", response_model=ExperimentOut, status_code=201)
def create(payload: ExperimentCreate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    if payload.start_date < service.today():
        raise HTTPException(422, "Draft start date cannot be in the past")
    entry, _ = service.reference(db, user, payload)
    row = Experiment(user_id=user.id, engine_version=2, status="draft", source="user_configured")
    service.set_definition(row, payload, entry)
    db.add(row)
    service.commit(db)
    db.refresh(row)
    return experiment_projection(db, user.id, row)

@router.get("/{identifier}", response_model=ExperimentOut)
def read(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    return experiment_projection(db, user.id, service.owned(db, user, identifier))

@router.patch("/{identifier}", response_model=ExperimentOut)
def edit(identifier: str, payload: ExperimentUpdate, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    row = service.owned(db, user, identifier)
    service.versioned(row)
    if row.status != "draft":
        raise HTTPException(409, "Activated definitions and notes are immutable; stop and create a new draft")
    if "definition" in payload.model_fields_set:
        if payload.definition is None or payload.definition.start_date < service.today():
            raise HTTPException(422, "A valid future/today definition is required")
        entry, _ = service.reference(db, user, payload.definition)
        service.set_definition(row, payload.definition, entry)
    if "notes" in payload.model_fields_set:
        row.notes = payload.notes
    service.commit(db)
    return experiment_projection(db, user.id, row)

@router.post("/{identifier}/activate", response_model=ExperimentOut)
def activate(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    row = service.owned(db, user, identifier)
    try:
        service.activate(db, user, row)
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Conflicting experiment or routine configuration")
    service.commit(db)
    return experiment_projection(db, user.id, row)

@router.post("/{identifier}/finish", response_model=ExperimentOut)
def finish(identifier: str, payload: FinishInput, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    row = service.owned(db, user, identifier)
    if row.status not in ("draft", "active", "paused", "baseline"):
        raise HTTPException(409, "Experiment already finished")
    if row.status == "draft" and payload.status != "cancelled":
        raise HTTPException(409, "Drafts can only be cancelled")
    if row.status != "draft" and payload.status == "cancelled":
        raise HTTPException(409, "Use stopped for an activated experiment")
    if payload.status == "completed" and (not row.activated_at or service.coverage(db, row)["elapsed_days"] < row.target_days):
        raise HTTPException(409, "The intended complete-day window has not elapsed; stop instead")
    row.status = payload.status
    row.stopped_at = row.end_date = service.now()
    row.active_owner = None
    product = db.query(Product).filter_by(id=row.product_id, user_id=user.id).first()
    if product and not db.query(Experiment).filter(Experiment.user_id == user.id, Experiment.product_id == product.id, Experiment.id != row.id, Experiment.status.in_(["active", "paused", "baseline"])).first():
        product.in_experiment = False
        product.updated_at = row.stopped_at
    service.commit(db)
    return experiment_projection(db, user.id, row)

@router.delete("/{identifier}", response_model=ExperimentOut)
def cancel(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Deletion is a history-preserving lifecycle transition.
    row = service.owned(db, user, identifier)
    return finish(identifier, FinishInput(status="cancelled" if row.status == "draft" else "stopped"), user, db)

@router.post("/{identifier}/evaluate", response_model=EvaluationOut, status_code=201)
def evaluate(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    row = service.owned(db, user, identifier)
    result = service.evaluate(db, row)
    service.commit(db)
    db.refresh(result)
    return result

@router.get("/{identifier}/results", response_model=list[EvaluationOut])
def results(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    service.owned(db, user, identifier)
    return db.query(ExperimentEvaluation).filter_by(user_id=user.id, experiment_id=identifier).order_by(ExperimentEvaluation.created_at.desc(), ExperimentEvaluation.id.desc()).all()

@router.patch("/{identifier}/toggle-pause")
def retired_pause(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    row = service.owned(db, user, identifier)
    if row.engine_version == 2:
        raise HTTPException(409, "Pause is unsupported in v2; stop preserves history")
    if row.status not in ("active", "paused"):
        raise HTTPException(409, "Legacy experiment cannot pause")
    row.status = "paused" if row.status == "active" else "active"
    service.commit(db)
    return experiment_projection(db, user.id, row)
