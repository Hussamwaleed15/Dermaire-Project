from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from app.core.database import get_db
from app.api.deps import get_current_user
from app.models import User, Experiment, ExperimentEvaluation, Product
from app.schemas.experiments import ExperimentCreate, ExperimentUpdate, ExperimentOut, FinishInput, EvaluationOut
from app.services import experiments as service
from app.services.routine import lock_owner

from app.services import resource_revisions as revisions
from app.services import configuration_attempts as configuration

router = APIRouter(prefix="/experiments", tags=["Controlled experiments v2"])

def experiment_projection(db, user_id, row, *, as_of=None):
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
    data["current_day"] = min(row.target_days, max(1, ((row.stopped_at.date() if row.stopped_at else as_of.date() if as_of is not None else service.today())-row.start_date.date()).days+1)) if row.activated_at else row.current_day
    data["coverage"] = service.coverage(db, row)
    data["result"] = db.query(ExperimentEvaluation).filter_by(user_id=user_id, experiment_id=row.id).order_by(ExperimentEvaluation.created_at.desc(), ExperimentEvaluation.id.desc()).first()
    return ExperimentOut.model_validate(data)

@router.get("/current", response_model=ExperimentOut | None)
def current(response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = db.query(Experiment).filter(Experiment.user_id == user.id, Experiment.status.in_(["active", "paused", "baseline"])).order_by(Experiment.created_at.desc(), Experiment.id.desc()).first()
    if row is not None:
        revisions.etag(response, row)
    return experiment_projection(db, user.id, row)

@router.get("", response_model=list[ExperimentOut])
def listing(limit: int = Query(100, ge=1, le=200), offset: int = Query(0, ge=0), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = db.query(Experiment).filter_by(user_id=user.id).order_by(Experiment.created_at.desc(), Experiment.id.desc()).offset(offset).limit(limit).all()
    return [experiment_projection(db, user.id, row) for row in rows]

@router.post("", response_model=ExperimentOut, status_code=201)
def create(payload: ExperimentCreate, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db), request: Request = None):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"experiment","create","",payload,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    if payload.start_date < service.today():
        raise HTTPException(422, "Draft start date cannot be in the past")
    entry, _ = service.reference(db, user, payload)
    row = Experiment(user_id=user.id, engine_version=2, status="draft", source="user_configured")
    service.set_definition(row, payload, entry)
    db.add(row)
    if attempt:return configuration.commit(db,attempt,row,lambda:experiment_projection(db,user.id,row,as_of=service.now()),service.commit,response,"experiment")
    service.commit(db)
    db.refresh(row)
    revisions.etag(response, row)
    return experiment_projection(db, user.id, row)


@router.get("/operation-attempts/{operation}/{key}")
def operation_attempt(operation: str,key: str,response: Response,resource_id: str="",
                      user: User=Depends(get_current_user),db: Session=Depends(get_db)):
    response.headers["Cache-Control"]="no-store"
    return configuration.lookup(db,user.id,"experiment",operation,resource_id,key)

@router.get("/{identifier}", response_model=ExperimentOut)
def read(identifier: str, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    row = service.owned(db, user, identifier)
    revisions.etag(response, row)
    revisions.etag(response, row)
    return experiment_projection(db, user.id, row)

@router.patch("/{identifier}", response_model=ExperimentOut)
def edit(identifier: str, payload: ExperimentUpdate, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"experiment","edit",identifier,payload,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    row = service.owned(db, user, identifier)
    revisions.enforce(row, revisions.header(request))
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
    revisions.reserve(db, row, revisions.header(request))
    if attempt:return configuration.commit(db,attempt,row,lambda:experiment_projection(db,user.id,row,as_of=service.now()),service.commit,response,"experiment")
    service.commit(db)
    revisions.etag(response, row)
    return experiment_projection(db, user.id, row)

@router.post("/{identifier}/activate", response_model=ExperimentOut)
def activate(identifier: str, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"experiment","activate",identifier,None,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    row = service.owned(db, user, identifier)
    try:
        from app.services.resource_revisions import header
        service.activate(db, user, row, header(request, "Routine-If-Match"), header(request))
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Conflicting experiment or routine configuration")
    if attempt:return configuration.commit(db,attempt,row,lambda:experiment_projection(db,user.id,row,as_of=service.now()),service.commit,response,"experiment")
    service.commit(db)
    revisions.etag(response, row)
    return experiment_projection(db, user.id, row)

@router.post("/{identifier}/finish", response_model=ExperimentOut)
def finish(identifier: str, payload: FinishInput, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"experiment","finish",identifier,payload,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    row = service.owned(db, user, identifier)
    finish_mutation(db,user,row,payload,request)
    if attempt:return configuration.commit(db,attempt,row,lambda:experiment_projection(db,user.id,row,as_of=service.now()),service.commit,response,"experiment")
    service.commit(db)
    revisions.etag(response,row)
    return experiment_projection(db,user.id,row)


def finish_mutation(db,user,row,payload,request):
    revisions.enforce(row, revisions.header(request))
    if row.status not in ("draft", "active", "paused", "baseline"):
        raise HTTPException(409, "Experiment already finished")
    if row.status == "draft" and payload.status != "cancelled":
        raise HTTPException(409, "Drafts can only be cancelled")
    if row.status != "draft" and payload.status == "cancelled":
        raise HTTPException(409, "Use stopped for an activated experiment")
    if payload.status == "completed" and (not row.activated_at or service.coverage(db, row)["elapsed_days"] < row.target_days):
        raise HTTPException(409, "The intended complete-day window has not elapsed; stop instead")
    revisions.reserve(db, row, revisions.header(request))
    row.status = payload.status
    row.stopped_at = row.end_date = service.now()
    row.active_owner = None
    product = db.query(Product).filter_by(id=row.product_id, user_id=user.id).first()
    if product and not db.query(Experiment).filter(Experiment.user_id == user.id, Experiment.product_id == product.id, Experiment.id != row.id, Experiment.status.in_(["active", "paused", "baseline"])).first():
        product.in_experiment = False
        product.updated_at = row.stopped_at

@router.delete("/{identifier}", response_model=ExperimentOut)
def cancel(identifier: str, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Deletion is a history-preserving lifecycle transition.
    lock_owner(db,user)
    attempt=configuration.begin(db,user.id,"experiment","cancel",identifier,None,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    row = service.owned(db, user, identifier)
    finish_mutation(db,user,row,FinishInput(status="cancelled" if row.status=="draft" else "stopped"),request)
    if attempt:return configuration.commit(db,attempt,row,lambda:experiment_projection(db,user.id,row,as_of=service.now()),service.commit,response,"experiment")
    service.commit(db);revisions.etag(response,row)
    return experiment_projection(db,user.id,row)

@router.post("/{identifier}/evaluate", response_model=EvaluationOut, status_code=201)
def evaluate(identifier: str, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"experiment","evaluate",identifier,None,request,response,etag_name="Experiment-ETag")
    if attempt and attempt.previous is not None:return attempt.previous
    row = service.owned(db, user, identifier)
    revisions.enforce(row, revisions.header(request))
    result = service.evaluate(db, row)
    revisions.reserve(db, row, revisions.header(request))
    if attempt:return configuration.commit(db,attempt,row,lambda:EvaluationOut.model_validate(result),service.commit,response,"evaluation",etag_name="Experiment-ETag")
    service.commit(db)
    db.refresh(result)
    response.headers["Experiment-ETag"] = f'"{row.revision}"'
    return result

@router.get("/{identifier}/results", response_model=list[EvaluationOut])
def results(identifier: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    service.owned(db, user, identifier)
    return db.query(ExperimentEvaluation).filter_by(user_id=user.id, experiment_id=identifier).order_by(ExperimentEvaluation.created_at.desc(), ExperimentEvaluation.id.desc()).all()

@router.patch("/{identifier}/toggle-pause")
def retired_pause(identifier: str, request: Request, response: Response, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    lock_owner(db, user)
    attempt=configuration.begin(db,user.id,"experiment","legacy_pause",identifier,None,request,response)
    if attempt and attempt.previous is not None:return attempt.previous
    row = service.owned(db, user, identifier)
    revisions.enforce(row, revisions.header(request))
    if row.engine_version == 2:
        raise HTTPException(409, "Pause is unsupported in v2; stop preserves history")
    if row.status not in ("active", "paused"):
        raise HTTPException(409, "Legacy experiment cannot pause")
    revisions.reserve(db, row, revisions.header(request))
    row.status = "paused" if row.status == "active" else "active"
    if attempt:return configuration.commit(db,attempt,row,lambda:experiment_projection(db,user.id,row,as_of=service.now()),service.commit,response,"experiment")
    service.commit(db)
    revisions.etag(response, row)
    return experiment_projection(db, user.id, row)
