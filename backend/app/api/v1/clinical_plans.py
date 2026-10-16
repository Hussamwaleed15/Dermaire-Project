from fastapi import APIRouter,Depends,Header,HTTPException,Query,Response
from sqlalchemy.orm import Session
from app.api.deps import require_role
from app.core.database import get_db
from app.models import User
from app.models.clinical_plans import ClinicalPlan,ClinicalPlanEvent
from app.schemas.clinical_plans import CreatePlan,RevisePlan,ConfirmPlan,CancelPlan,AttachCapture,ReviewPlan,EvaluatePlan,ReviewEvaluation
from app.services import clinical_plans as service

router=APIRouter(prefix="/clinical-plans",tags=["Clinician follow-up and comparison plans"])
participant=require_role(["patient","doctor"])


def key_of(keys):
    if not keys or len(keys)!=1:raise HTTPException(422,"One Idempotency-Key required")
    return keys[0]


def headers(response): response.headers["Cache-Control"]="no-store"


@router.post("",status_code=201)
def create(payload: CreatePlan,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),
           actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    headers(response)
    result=service.create(db,actor,payload,key_of(keys))
    response.headers["ETag"]=f'"{result["revision"]}"'
    return result


@router.get("")
def list_plans(response: Response,limit: int=Query(50,ge=1,le=100),after: str | None=None,
               actor: User=Depends(participant),db: Session=Depends(get_db)):
    headers(response)
    column=ClinicalPlan.user_id if actor.role=="patient" else ClinicalPlan.doctor_id
    query=db.query(ClinicalPlan).filter(column==actor.id)
    if after:query=query.filter(ClinicalPlan.id>after)
    rows=query.order_by(ClinicalPlan.id).limit(limit+1).all()
    items=[]
    for row in rows[:limit]:
        try:items.append(service.output(service.authorize(db,actor,row.id)))
        except HTTPException as error:
            if error.status_code not in (403,404):raise
    return {"items":items,"next_after":rows[limit-1].id if len(rows)>limit else None,
            "history_basis":"immutable_plan_events_no_numeric_AI_scores"}


@router.get("/creation-attempts/{patient_id}/{key}")
def creation_attempt(patient_id: str,key: str,response: Response,
                     actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    headers(response)
    identifier=service.identity(patient_id,actor.id,"create",key)
    plan=db.get(ClinicalPlan,identifier)
    if plan:return service.attempt(db,actor,plan.id,"create",key)
    from app.services.doctor_loop import authorize
    authorize(db,actor,patient_id)
    return {"attempt_id":identifier,"status":"unknown","result":None}


@router.get("/{plan_id}")
def detail(plan_id: str,response: Response,actor: User=Depends(participant),db: Session=Depends(get_db)):
    headers(response)
    return service.output(service.authorize(db,actor,plan_id))


@router.get("/{plan_id}/history")
def history(plan_id: str,response: Response,after_revision: int=Query(0,ge=0),limit: int=Query(50,ge=1,le=100),
            actor: User=Depends(participant),db: Session=Depends(get_db)):
    headers(response);service.authorize(db,actor,plan_id)
    rows=db.query(ClinicalPlanEvent).filter(ClinicalPlanEvent.plan_id==plan_id,
        ClinicalPlanEvent.revision>after_revision).order_by(ClinicalPlanEvent.revision).limit(limit+1).all()
    return {"items":[{"revision":r.revision,"operation":r.operation,"actor_id":r.actor_id,
        "recorded_at":service.utc(r.recorded_at),"snapshot":r.snapshot} for r in rows[:limit]],
        "next_after_revision":rows[limit-1].revision if len(rows)>limit else None,
        "numeric_comparison_metrics":None,"model_status":"unavailable"}


@router.get("/{plan_id}/attempts/{operation}/{key}")
def attempt(plan_id: str,operation: str,key: str,response: Response,
            actor: User=Depends(participant),db: Session=Depends(get_db)):
    headers(response)
    if operation not in ("create","reschedule","acknowledge","cancel","capture","review","evaluate","evaluation_review"):raise HTTPException(422,"Unknown operation")
    return service.attempt(db,actor,plan_id,operation,key)


def mutate(plan_id,operation,payload,response,keys,actor,db):
    headers(response)
    result=service.mutate(db,actor,plan_id,operation,payload,key_of(keys))
    response.headers["ETag"]=f'"{result["revision"]}"'
    return result


@router.post("/{plan_id}/reschedule")
def reschedule(plan_id: str,payload: RevisePlan,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    return mutate(plan_id,"reschedule",payload,response,keys,actor,db)


@router.post("/{plan_id}/acknowledge")
def acknowledge(plan_id: str,payload: ConfirmPlan,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(require_role(["patient"])),db: Session=Depends(get_db)):
    return mutate(plan_id,"acknowledge",payload,response,keys,actor,db)


@router.post("/{plan_id}/cancel")
def cancel(plan_id: str,payload: CancelPlan,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(participant),db: Session=Depends(get_db)):
    return mutate(plan_id,"cancel",payload,response,keys,actor,db)


@router.post("/{plan_id}/capture")
def capture(plan_id: str,payload: AttachCapture,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(require_role(["patient"])),db: Session=Depends(get_db)):
    return mutate(plan_id,"capture",payload,response,keys,actor,db)


@router.post("/{plan_id}/review")
def review(plan_id: str,payload: ReviewPlan,response: Response,keys: list[str] | None=Header(None,alias="Idempotency-Key"),actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    return mutate(plan_id,"review",payload,response,keys,actor,db)


@router.post("/{plan_id}/evaluation",status_code=202)
def queue_evaluation(plan_id: str,payload: EvaluatePlan,response: Response,
                     keys: list[str] | None=Header(None,alias="Idempotency-Key"),
                     actor: User=Depends(require_role(["patient"])),db: Session=Depends(get_db)):
    from app.services import comparison_jobs
    headers(response)
    return comparison_jobs.enqueue(db,actor,plan_id,payload,key_of(keys))


@router.get("/{plan_id}/evaluation")
def evaluation_status(plan_id: str,response: Response,actor: User=Depends(participant),db: Session=Depends(get_db)):
    from app.services import comparison_jobs
    headers(response)
    return comparison_jobs.status(db,actor,plan_id)


@router.delete("/{plan_id}/evaluation")
def cancel_evaluation(plan_id: str,response: Response,expected_revision: int=Query(ge=1),
                      actor: User=Depends(participant),db: Session=Depends(get_db)):
    from app.services import comparison_jobs
    headers(response)
    return comparison_jobs.cancel(db,actor,plan_id,expected_revision)


@router.post("/{plan_id}/evaluation/review")
def review_evaluation(plan_id: str,payload: ReviewEvaluation,response: Response,
                      keys: list[str] | None=Header(None,alias="Idempotency-Key"),
                      actor: User=Depends(require_role(["doctor"])),db: Session=Depends(get_db)):
    from app.services import comparison_jobs
    headers(response)
    return comparison_jobs.review(db,actor,plan_id,payload,key_of(keys))
