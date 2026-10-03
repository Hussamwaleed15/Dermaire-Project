"""Clinician projections. No inference or mutation of underlying tracking/safety facts."""
from datetime import datetime, timezone
import math
from fastapi import HTTPException
from app.models import (User, DoctorPatientAccess, ClinicalNote, DoctorReviewAction, AuditLog,
    CheckIn, DailyContext, RoutineEntry, RoutineAdherence, Experiment, ExperimentEvaluation,
    Capture, Measurement, Product)
from app.schemas import ClinicalNoteOut
from app.services.context_builder import build_context
from app.services.personal_skin_model import utc, report_of, measurement_of
from app.services.safety import evaluate_safety
from app.services.product_intelligence import read_intelligence

RANK = {"track": 0, "low_risk_self_care": 1, "doctor_review": 2, "urgent": 3}

def authorize(db, doctor, patient_id):
    # Same patient lock serializes clinician writes, revocations and account deletion.
    patient = db.query(User).filter_by(id=patient_id, role="patient").with_for_update().first()
    grant = db.query(DoctorPatientAccess).filter(
        DoctorPatientAccess.patient_id == patient_id,
        DoctorPatientAccess.doctor_id == doctor.id,
        DoctorPatientAccess.status == "active",
        DoctorPatientAccess.expires_at > datetime.now(timezone.utc),
    ).order_by(DoctorPatientAccess.created_at.desc(), DoctorPatientAccess.id.desc()).with_for_update().first()
    if not patient or not grant:
        raise HTTPException(403, "No current access to this patient")
    return patient, grant


def save(db, actor_id, action, target, details):
    db.add(AuditLog(actor_id=actor_id, action=action, target_resource=target, details=details))
    try:
        db.commit()
    except Exception:
        db.rollback()
        raise HTTPException(503, "Clinician action could not be confirmed; retry after refreshing")


def access_out(row):
    expired = utc(row.expires_at) <= datetime.now(timezone.utc)
    return {"id": row.id, "patient_id": row.patient_id, "doctor_id": row.doctor_id,
        "granted_by": row.granted_by, "status": "expired" if expired and row.status in ("active", "pending") else row.status,
        "created_at": row.created_at, "expires_at": row.expires_at, "claimed_at": row.claimed_at,
        "revoked_at": row.revoked_at, "revoked_by": row.revoked_by}


def review_out(row, safety):
    return {"id": row.id, "sequence": row.sequence, "patient_id": row.patient_id,
        "doctor_id": row.doctor_id, "access_id": row.access_id, "state": row.state,
        "recommendation": row.recommendation, "rationale": row.rationale,
        "patient_visible": row.patient_visible, "created_at": row.created_at,
        "provenance": "clinician_authored", "safety_at_review": row.safety_snapshot,
        "diverges_from_current_safety": bool(row.recommendation and row.recommendation != safety.status),
        "lower_than_current_safety": bool(row.recommendation and RANK[row.recommendation] < RANK[safety.status]),
        "urgent_safety_preserved": safety.status == "urgent"}


def reviews(db, patient_id):
    return db.query(DoctorReviewAction).filter_by(patient_id=patient_id).order_by(
        DoctorReviewAction.sequence.desc()).all()


def review_status(db, patient, patient_view=False):
    safety = evaluate_safety(db, patient)
    rows = reviews(db, patient.id)
    latest = rows[0] if rows else None
    grants = db.query(DoctorPatientAccess).filter_by(patient_id=patient.id).all()
    return {"schema_version": "doctor-loop-2.0", "patient_id": patient.id,
        "state": latest.state if latest else "pending" if any(access_out(g)["status"] in ("active", "pending") for g in grants) else "not_requested",
        "latest_sequence": latest.sequence if latest else 0,
        "changed_at": latest.created_at if latest else None,
        "changed_by": latest.doctor_id if latest else None,
        "safety": safety.model_dump(mode="json"),
        # No fallback to an older visible decision as though it were current.
        "current_decision": review_out(latest, safety) if latest and (not patient_view or latest.patient_visible) else None,
        "history": [review_out(r, safety) for r in rows if not patient_view or r.patient_visible],
        "notes": [ClinicalNoteOut.model_validate(n).model_dump(mode="json") for n in
            db.query(ClinicalNote).filter_by(patient_id=patient.id).order_by(ClinicalNote.created_at, ClinicalNote.id)
            if not patient_view or n.patient_visible],
        "access": [access_out(g) for g in grants] if patient_view else None}


def timeline(db, patient):
    now = datetime.now(timezone.utc)
    context = build_context(db, patient, now=now)
    items = []
    def add(source, source_id, category, timestamp, data, field="record", provenance=None, identity_suffix=""):
        if timestamp and utc(timestamp) > now:
            return
        items.append({"id": f"{source}:{source_id}:{field}" + identity_suffix, "source": source,
            "source_id": str(source_id), "field": field, "category": category,
            "recorded_at": utc(timestamp) if timestamp else None,
            "provenance": provenance or {"source_table": source, "timestamp_basis": "server_recorded"},
            "data": data})
    add("profile", patient.id, "patient_reported", patient.updated_at,
        {"skin_type": patient.skin_type, "selected_goal": patient.selected_goal,
         "skin_concerns": patient.skin_concerns, "disclosures": patient.profile_context},
        provenance={"mutable_current_snapshot": True, "source_table": "users"})
    specifications = (
        (DailyContext, "daily_context", "updated_at", "patient_reported", ("date", "unusual_conditions", "cycle_day")),
        (RoutineEntry, "routine", "updated_at", "patient_reported", ("product_id", "schedule", "frequency", "start_date", "end_date", "active", "instructions", "source")),
        (RoutineAdherence, "adherence", "created_at", "patient_reported", ("routine_entry_id", "date", "slot", "status", "note", "configuration_snapshot")),
        (Experiment, "experiment", "created_at", "patient_reported", ("product_id", "engine_version", "status", "intervention", "goal", "notes", "definition_snapshot", "activated_at", "stopped_at")),
        (ExperimentEvaluation, "experiment_evaluation", "created_at", "deterministic_derived", ("experiment_id", "result")),
        (Capture, "capture", "received_at", "system_observed", ("state", "source", "view", "storage", "server_version")),
    )
    for model, source, timestamp, category, fields in specifications:
        for row in db.query(model).filter_by(user_id=patient.id):
            if model is Experiment and row.engine_version != 2:
                continue # Legacy defaults are not authoritative patient reports.
            add(source, row.id, category, getattr(row, timestamp), {f: getattr(row, f) for f in fields},
                provenance={"source_table": model.__tablename__, "mutable_current_snapshot": model in (DailyContext, RoutineEntry, Experiment)})
    for capture in db.query(Capture).filter_by(user_id=patient.id):
        add("capture", capture.id, "deterministic_derived", capture.received_at,
            {"quality": capture.quality}, "quality", {"source_table": "captures", "version": capture.server_version})
    for product in db.query(Product).filter_by(user_id=patient.id):
        pi = read_intelligence(db, product)
        when = datetime.fromisoformat(pi["updated_at"]) if pi["updated_at"] else None
        source_map = {v["id"]: v for v in pi["facts"]["sources"]}
        for field, fact in pi["facts"].items():
            if field == "sources" or not fact:
                continue
            if field == "ingredients":
                for index, ingredient in enumerate(fact["items"]):
                    evidence = source_map[ingredient["source_id"]]
                    add("product_intelligence", product.id,
                        "patient_reported" if evidence["type"] == "user_reported" else "system_observed",
                        when, ingredient, "ingredient", {"source_table": "product_intelligence", "evidence": evidence},
                        identity_suffix=f":{index}")
                continue
            evidence = source_map[fact["source_id"]]
            add("product_intelligence", product.id,
                "patient_reported" if evidence["type"] == "user_reported" else "system_observed",
                when, fact, "reported_"+field, {"source_table": "product_intelligence", "evidence": evidence})
        add("product_intelligence", product.id, "deterministic_derived", when,
            {"state": pi["state"], "data_completeness": pi["data_completeness"], "unknowns": pi["unknowns"],
             "ingredients": pi["ingredients"]}, "normalized_summary", {"version": pi["version"], "clinical_determination": False})
    for row in db.query(CheckIn).filter_by(user_id=patient.id):
        report = report_of(row)
        add("checkin", row.id, "patient_reported", row.created_at,
            {"date": row.date_str, "observation": report.model_dump(mode="json", exclude_unset=True) if report else None,
             "notes": row.notes}, provenance={"source_table": "checkins", "report_status": "validated" if report else "unknown"})
        if measurement_of(row):
            source = (row.ai_vision_analysis or {}).get("measurement_source")
            add("checkin", row.id, "patient_reported" if source == "manual" else "system_observed",
                row.created_at, {k: getattr(row, k+"_score") for k in ("hydration", "texture", "redness")},
                "tracking_scores", {"source_table": "checkins", "measurement_source": source, "clinical_measurement": False})
        analysis = row.ai_vision_analysis or {}
        # Historical AI prose stays isolated and untrusted; never a clinician assessment.
        if analysis and analysis.get("measurement_source") not in ("manual", "image_proxy"):
            add("checkin", row.id, "ai_inferred", row.created_at,
                {"availability": "historical_output_quarantined", "authoritative": False, "simulated": analysis.get("simulated"), "measurement_source": analysis.get("measurement_source")}, "ai_analysis",
                {"source_table": "checkins", "legacy_or_simulated": True, "clinical_evidence": False})
    captures = {c.id: c for c in db.query(Capture).filter_by(user_id=patient.id)}
    for row in db.query(Measurement).filter_by(user_id=patient.id):
        capture = captures.get(row.capture_id)
        values = {}
        if capture and capture.state == "accepted" and row.status == "measured" and (row.quality_reference or {}).get("decision") == "accepted":
            for key in ("red_chromaticity_proxy", "texture_contrast_proxy"):
                item = (row.results or {}).get(key, {})
                v = item.get("value")
                if (item.get("status") == "measured" and item.get("method_version") == row.algorithm_version
                    and item.get("source_capture_id") == row.capture_id and item.get("unit") == "fraction_0_to_1"
                    and type(v) in (int, float) and math.isfinite(v) and 0 <= v <= 1):
                    values[key] = item
        add("measurement", row.id, "system_observed", row.measured_at,
            {"capture_id": row.capture_id, "status": row.status, "values": values or None},
            provenance={"source_table": "measurements", "algorithm": row.algorithm_version, "clinical_measurement": False})
    # Reuse existing validated derivations; their bounded availability stays explicit.
    for f in context.facts:
        if f.source in ("baseline", "product_intelligence", "personal_skin_model", "safety"):
            add(f.source, f.source_id, f.category, f.recorded_at, {"value": f.value}, f.field,
                {**f.provenance, "freshness": f.freshness, "confidence": f.confidence, "projection": "context-1.0"},
                identity_suffix=":"+f.provenance["ingredient_ref"] if f.provenance.get("ingredient_ref") else "")
    for note in db.query(ClinicalNote).filter_by(patient_id=patient.id):
        add("clinical_note", note.id, "clinician_authored", note.created_at,
            ClinicalNoteOut.model_validate(note).model_dump(mode="json"))
    for row in reviews(db, patient.id):
        add("doctor_review", row.id, "clinician_authored", row.created_at, review_out(row, context.safety))
    items.sort(key=lambda i: (i["recorded_at"] or datetime.min.replace(tzinfo=timezone.utc), i["id"]))
    return {"schema_version": "doctor-timeline-2.0", "built_at": now, "items": items,
        "unknowns": context.unknowns, "derived_source_availability": {k:v.model_dump() for k,v in context.sources.items()},
        "safety": context.safety.model_dump(mode="json"),
        "limitations": ["Mutable source rows are current snapshots, not an edit history.",
            "Derived projections use existing context limits (14 recent records, 240 facts); availability and truncation are explicit.",
            "Null timestamps are unknown and sort first; source IDs and stable tie-breakers are preserved."]}
