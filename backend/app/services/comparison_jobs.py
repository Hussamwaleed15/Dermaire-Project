"""Durable comparison evaluation events; no live images or model transport.

A queue entry requires fresh explicit patient image-processing consent after both
private captures exist. Lease fencing rejects stale worker completion. Provider
calls may only be made through a separately verified deployment adapter.
"""
from datetime import datetime,timedelta
from uuid import uuid4
from fastapi import HTTPException
from app.models import User
from app.models.clinical_plans import ClinicalPlan,ClinicalPlanEvent,ClinicalPlanAttempt
from app.services import clinical_plans as plans
from app.services.messaging import current_grant
from app.services.model_providers import ComparisonInput,ComparisonInference,DisabledComparisonProvider


def latest(db,plan):
    event=db.query(ClinicalPlanEvent).filter_by(plan_id=plan.id,operation="evaluation").order_by(ClinicalPlanEvent.revision.desc()).first()
    return dict(event.snapshot) if event else None


def record(db,plan,actor,job):
    plan.revision+=1
    job={**job,"plan_revision":plan.revision,"updated_at":plans.now().isoformat()}
    db.add(ClinicalPlanEvent(plan_id=plan.id,actor_id=actor.id,revision=plan.revision,operation="evaluation",snapshot=job))
    db.flush()
    return job


def ready(db,actor,plan_id):
    plan=plans.authorize(db,actor,plan_id)
    current_grant(db,actor,plan.access_id)
    if plan.kind!="comparison" or plan.state!="captured" or not plan.acknowledged_at:
        raise HTTPException(409,"Consented captured comparison required")
    plans.private_capture(db,plan.user_id,plan.baseline_capture_id)
    plans.private_capture(db,plan.user_id,plan.followup_capture_id)
    return plan


def enqueue(db,actor,plan_id,payload,key):
    if actor.role!="patient" or payload.image_processing_consent is not True:
        raise HTTPException(403,"Explicit patient image processing consent required")
    plan=ready(db,actor,plan_id)
    identifier=plans.identity(plan.user_id,actor.id,"evaluate",key,plan_id)
    prior=plans.replay(db,identifier,payload)
    if prior:return prior
    if plan.revision!=payload.expected_revision:raise HTTPException(409,"Clinical plan revision changed")
    previous=latest(db,plan)
    if previous and previous["state"] in ("queued","running","pending_human_review"):
        raise HTTPException(409,"Evaluation already active; reconcile or cancel it first")
    job=record(db,plan,actor,{"schema_version":"comparison-job-1","id":identifier,"state":"queued",
        "input":ComparisonInput(plan_id=plan.id,plan_revision=plan.revision,
            baseline_capture_id=plan.baseline_capture_id,followup_capture_id=plan.followup_capture_id,
            consent_revision=plan.revision).model_dump(),"attempts":0,"lease_token":None,"lease_until":None,
        "inference":None,"medical_resources_modified":False,"clinical_clearance":False})
    db.add(ClinicalPlanAttempt(id=identifier,plan_id=plan.id,user_id=actor.id,actor_id=actor.id,
        operation="evaluate",payload_hash=plans.fingerprint(payload),result=job))
    from app.services.agent_platform import save
    save(db)
    return job


def status(db,actor,plan_id):
    plan=plans.authorize(db,actor,plan_id)
    job=latest(db,plan)
    if job:
        try:current_grant(db,actor,plan.access_id)
        except HTTPException as error:
            if error.status_code not in (403,404):raise
            return {**job,"effective_state":"cancelled","reason":"original_authority_revoked"}
    if job and plan.state in ("cancelled","reviewed") and job["state"] in ("queued","running","pending_human_review"):
        return {**job,"effective_state":"cancelled","reason":"plan_no_longer_active"}
    return job or {"state":"not_requested","inference":None}


def cancel(db,actor,plan_id,revision):
    plan=plans.authorize(db,actor,plan_id)
    job=latest(db,plan)
    if not job:raise HTTPException(404,"Evaluation not found")
    if job["state"]=="cancelled":return job
    if plan.revision!=revision:raise HTTPException(409,"Clinical plan revision changed")
    job=record(db,plan,actor,{**job,"state":"cancelled","lease_token":None,"lease_until":None,"inference":None})
    from app.services.agent_platform import save
    save(db)
    return job


def run_one(db,plan_id,provider=None):
    """One bounded local worker iteration, with committed lease before adapter.

    The default provider never accesses images or network. Injected adapters must
    satisfy the typed contract; results always require human review.
    """
    plan=db.get(ClinicalPlan,plan_id)
    if not plan:return {"state":"not_found"}
    actor=db.get(User,plan.user_id)
    actor_id=plan.user_id
    plan=ready(db,actor,plan_id)
    job=latest(db,plan)
    if not job or job["state"] not in ("queued","running"):return job or {"state":"not_requested"}
    if job["state"]=="running" and datetime.fromisoformat(job["lease_until"])>plans.now():return {"state":"busy"}
    if job["attempts"]>=3:return {"state":"retry_limit"}
    lease=str(uuid4())
    claimed=record(db,plan,actor,{**job,"state":"running","attempts":job["attempts"]+1,
        "lease_token":lease,"lease_until":(plans.now()+timedelta(minutes=2)).isoformat()})
    from app.services.agent_platform import save
    save(db)
    try:
        raw=(provider or DisabledComparisonProvider()).evaluate(ComparisonInput.model_validate(job["input"]))
        result=ComparisonInference.model_validate(raw)
        if result.result and (result.result.baseline_capture_id!=job["input"]["baseline_capture_id"] or result.result.followup_capture_id!=job["input"]["followup_capture_id"]):
            raise ValueError("Adapter evidence references another capture pair")
    except Exception:
        result=ComparisonInference(status="unavailable",reason="adapter_error_or_invalid_envelope")
    # Reload after adapter and fence cancellation/revocation/account deletion.
    db.expunge_all()
    refreshed_actor=db.get(User,actor_id)
    if not refreshed_actor or not db.get(ClinicalPlan,plan_id):return {"state":"superseded","result_committed":False}
    actor=refreshed_actor
    plan=ready(db,actor,plan_id)
    current=latest(db,plan)
    if current["lease_token"]!=lease or current["state"]!="running" or datetime.fromisoformat(current["lease_until"])<=plans.now():
        return {"state":"superseded","result_committed":False}
    completed=record(db,plan,actor,{**claimed,"state":result.status,"lease_token":None,"lease_until":None,"inference":result.model_dump()})
    save(db)
    return completed


def review(db,actor,plan_id,payload,key):
    if actor.role!="doctor":raise HTTPException(403,"Clinician authority required")
    plan=plans.authorize(db,actor,plan_id)
    identifier=plans.identity(plan.user_id,actor.id,"evaluation_review",key,plan_id)
    prior=plans.replay(db,identifier,payload)
    if prior:return prior
    job=latest(db,plan)
    if plan.state not in ("captured","reviewed"):raise HTTPException(409,"Patient plan withdrawal prevents inference signoff")
    if plan.revision!=payload.expected_revision:raise HTTPException(409,"Clinical plan revision changed")
    if not job or job["id"]!=payload.job_id or job["state"]!="pending_human_review":
        raise HTTPException(409,"Pending version-bound inference review required")
    inference=ComparisonInference.model_validate(job["inference"])
    if inference.status!="pending_human_review":raise HTTPException(409,"No inference evidence to review")
    reviewed=record(db,plan,actor,{**job,"state":payload.decision,"human_review":{
        "decision":payload.decision,"assessment":payload.assessment,"actor_id":actor.id,
        "job_id":job["id"],"model_version":inference.model_version,"artifact_sha256":inference.artifact_sha256,
        "reviewed_at":plans.now().isoformat(),"provenance":"clinician_authored",
        "clinical_accuracy_validated":False,"clinical_clearance":False}})
    db.add(ClinicalPlanAttempt(id=identifier,plan_id=plan.id,user_id=plan.user_id,actor_id=actor.id,
        operation="evaluation_review",payload_hash=plans.fingerprint(payload),result=reviewed))
    from app.services.agent_platform import save
    save(db)
    return reviewed
