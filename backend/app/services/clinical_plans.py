"""Clinician-authored visible plans. Image inference remains unavailable."""
import hashlib
import json
from datetime import datetime,timezone,timedelta
from uuid import uuid5,NAMESPACE_URL
from fastapi import HTTPException
from fastapi.encoders import jsonable_encoder
from app.models import User,Capture,RoutineEntry,Experiment,CheckIn,AuditLog
from app.models.clinical_plans import ClinicalPlan,ClinicalPlanEvent,ClinicalPlanAttempt
from app.services.messaging import current_grant,attempt_id as message_key
from app.services.wall_time import resolve_due
from app.services.temporal import utc
from app.services.notifications import enqueue,cancel
from app.models.notifications import Notification
from app.services.model_providers import ComparisonInference


def now(): return datetime.now(timezone.utc)


def authorize(db,actor,plan_id):
    row=db.get(ClinicalPlan,plan_id)
    if not row or actor.id not in (row.user_id,row.doctor_id): raise HTTPException(404,"Clinical plan not found")
    db.query(User).filter_by(id=row.user_id,role="patient").with_for_update().one()
    if actor.id==row.doctor_id:
        grant=current_grant(db,actor,row.access_id)
        if (grant.patient_id,grant.doctor_id)!=(row.user_id,row.doctor_id): raise HTTPException(403,"Original plan grant changed")
    elif actor.role!="patient": raise HTTPException(403,"Patient role required")
    return db.query(ClinicalPlan).filter_by(id=plan_id).populate_existing().with_for_update().one()


def output(row):
    return {"schema_version":"clinical-plan-1","id":row.id,"patient_id":row.user_id,"doctor_id":row.doctor_id,
        "access_id":row.access_id,"kind":row.kind,"revision":row.revision,"state":row.state,"purpose":row.purpose,
        "due_at_utc":utc(row.due_at),"schedule_provenance":row.schedule_provenance,"source_snapshot":row.source_snapshot,
        "baseline_capture_id":row.baseline_capture_id,"followup_capture_id":row.followup_capture_id,
        "acknowledged_at":utc(row.acknowledged_at) if row.acknowledged_at else None,"created_at":utc(row.created_at),
        "provenance":"clinician_authored","patient_visible":True,"clinical_clearance":False,
        "image_inference":ComparisonInference(status="unavailable",reason="validated_model_not_integrated").model_dump()}


def identity(owner,actor,operation,key,plan_id=""):
    message_key("clinical-plan-key-validation",actor,key)
    return str(uuid5(NAMESPACE_URL,json.dumps(["clinical-plan-attempt-1",owner,actor,operation,plan_id,key])))


def fingerprint(payload):
    return hashlib.sha256(json.dumps(payload.model_dump(mode="json"),sort_keys=True,separators=(",",":"),allow_nan=False).encode()).hexdigest()


def replay(db,identifier,payload):
    row=db.get(ClinicalPlanAttempt,identifier)
    if not row:return None
    if utc(row.recorded_at)+timedelta(days=30)<=now(): raise HTTPException(410,"Plan replay expired; refresh plan and history")
    if row.payload_hash!=fingerprint(payload):raise HTTPException(409,"Attempt key is bound to a different plan operation")
    return row.result


def commit(db,actor,row,operation,identifier,payload,details=None):
    result=jsonable_encoder(output(row))
    db.add(ClinicalPlanEvent(plan_id=row.id,actor_id=actor.id,revision=row.revision,operation=operation,
        snapshot={"plan":result,"details":details or {}}))
    db.add(ClinicalPlanAttempt(id=identifier,plan_id=row.id,user_id=row.user_id,actor_id=actor.id,
        operation=operation,payload_hash=fingerprint(payload),result=result))
    db.add(AuditLog(actor_id=actor.id,action="CLINICAL_PLAN_"+operation.upper(),target_resource="clinical_plans",
        details={"patient_id":row.user_id,"plan_id":row.id,"revision":row.revision,"attempt_id":identifier}))
    try: db.commit()
    except Exception:
        db.rollback(); raise HTTPException(503,"Plan operation unconfirmed; reconcile the original attempt") from None
    return result


def schedule(payload):
    try: provenance=resolve_due(payload.local_due,payload.timezone,payload.fold)
    except ValueError as error: raise HTTPException(422,str(error)) from None
    due=datetime.fromisoformat(provenance["due_at_utc"])
    if due<=now():raise HTTPException(422,"New due time must be in the future")
    return due,provenance


def private_capture(db,owner,identifier):
    from app.services.image_access import safe_reference
    capture=db.query(Capture).filter_by(id=identifier,user_id=owner,state="accepted",storage="azure_blob").first()
    if (not capture or not safe_reference(capture.image_blob_name) or utc(capture.received_at)>now()
        or not capture.image_blob_name.startswith(f"skin_photos/{owner}/{owner}_")):
        raise HTTPException(404,"Owned persisted accepted capture required")
    return capture


def source_snapshot(db,owner,payload):
    if payload.source_type is None:return {}
    model={"routine":RoutineEntry,"experiment":Experiment,"observation":CheckIn}[payload.source_type]
    row=db.query(model).filter_by(id=payload.source_id,user_id=owner).first()
    if not row or (model is Experiment and row.engine_version!=2):raise HTTPException(404,"Owned current source required")
    return {"source_type":payload.source_type,"source_id":row.id,"revision":getattr(row,"revision",None),
        "recorded_at":utc(row.created_at).isoformat(),"linked_at":now().isoformat(),"basis":"linked_source_identity_at_creation"}


def create(db,actor,payload,key):
    if actor.role!="doctor":raise HTTPException(403,"Clinician authority required")
    grant=current_grant(db,actor,payload.access_id)
    identifier=identity(grant.patient_id,actor.id,"create",key)
    existing=db.get(ClinicalPlan,identifier)
    if existing:authorize(db,actor,existing.id)
    previous=replay(db,identifier,payload)
    if previous:return previous
    due,provenance=schedule(payload)
    source=source_snapshot(db,grant.patient_id,payload)
    if payload.baseline_capture_id:private_capture(db,grant.patient_id,payload.baseline_capture_id)
    row=ClinicalPlan(id=identifier,user_id=grant.patient_id,doctor_id=actor.id,access_id=grant.id,
        kind=payload.kind,state="proposed",revision=1,purpose=payload.purpose,due_at=due,
        schedule_provenance=provenance,source_snapshot=source,baseline_capture_id=payload.baseline_capture_id)
    db.add(row);db.flush()
    return commit(db,actor,row,"create",identifier,payload)


def mutate(db,actor,plan_id,operation,payload,key):
    row=authorize(db,actor,plan_id)
    identifier=identity(row.user_id,actor.id,operation,key,plan_id)
    # Authorize the operation before replaying a prior result.
    if operation in ("reschedule","review") and actor.role!="doctor":raise HTTPException(403,"Clinician authority required")
    if operation in ("acknowledge","capture") and actor.id!=row.user_id:raise HTTPException(403,"Patient action required")
    previous=replay(db,identifier,payload)
    if previous:return previous
    if row.revision!=payload.expected_revision:raise HTTPException(409,"Clinical plan revision changed")
    details={}
    if operation=="reschedule":
        if row.state not in ("proposed","scheduled"):raise HTTPException(409,"Plan cannot be rescheduled in this state")
        due,provenance=schedule(payload)
        row.due_at=due;row.schedule_provenance=provenance;row.state="proposed";row.acknowledged_at=None
    elif operation=="acknowledge":
        if row.state!="proposed" or payload.consent is not True:raise HTTPException(409,"Explicit consent to a proposed plan required")
        # Patient retains history after grant revocation, but may not activate a
        # plan whose clinician no longer has the original authority.
        current_grant(db,actor,row.access_id)
        row.state="scheduled";row.acknowledged_at=now()
    elif operation=="cancel":
        if row.state in ("cancelled","reviewed"):raise HTTPException(409,"Plan cannot be cancelled in this state")
        row.state="cancelled";details={"reason":payload.reason,"actor_role":actor.role}
    elif operation=="capture":
        if row.kind!="comparison" or row.state!="scheduled":raise HTTPException(409,"Scheduled comparison required")
        capture=private_capture(db,row.user_id,payload.capture_id)
        if capture.id==row.baseline_capture_id or utc(capture.received_at)<utc(row.acknowledged_at):
            raise HTTPException(409,"New private follow-up capture after consent required")
        row.followup_capture_id=capture.id;row.state="captured"
        details={"followup_received_at":utc(capture.received_at).isoformat(),"early_capture":utc(capture.received_at)<utc(row.due_at),
            "image_inference":"unavailable","clinical_accuracy_tested":False}
    elif operation=="review":
        if row.state not in ("scheduled","captured"):raise HTTPException(409,"Scheduled follow-up or captured comparison required")
        if row.kind=="comparison" and row.state!="captured":raise HTTPException(409,"Comparison follow-up capture required")
        row.state="reviewed";details={"assessment":payload.assessment,"provenance":"clinician_authored","clinical_clearance":False}
    else:raise HTTPException(422,"Unknown plan operation")
    for notice in db.query(Notification).filter_by(user_id=row.user_id,source_id=row.id,cancelled_at=None):cancel(db,notice)
    row.revision+=1
    if row.state=="scheduled":enqueue(db,row.user_id,"comparison" if row.kind=="comparison" else "follow_up",row.id,row.revision,utc(row.due_at))
    return commit(db,actor,row,operation,identifier,payload,details)


def attempt(db,actor,plan_id,operation,key):
    row=authorize(db,actor,plan_id)
    identifier=identity(row.user_id,actor.id,operation,key,"" if operation=="create" else plan_id)
    receipt=db.get(ClinicalPlanAttempt,identifier)
    if not receipt:return {"attempt_id":identifier,"status":"unknown","result":None}
    expired=utc(receipt.recorded_at)+timedelta(days=30)<=now()
    return {"attempt_id":identifier,"status":"expired" if expired else "committed","result":None if expired else receipt.result}
