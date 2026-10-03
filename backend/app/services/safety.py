"""Read-only structured triage. Scores, prose and AI outputs cannot reassure."""
from datetime import datetime, timezone, timedelta
from app.models import CheckIn, Capture, Measurement, Experiment, ExperimentEvaluation, DailyContext, RoutineAdherence, RoutineEntry
from app.services.personal_skin_model import report_of, utc
from app.services.product_intelligence import routine_intelligence
from app.schemas.safety import SafetyEvaluation, SafetyReason

FLAGS = ("breathing_difficulty", "facial_or_mouth_swelling", "eye_or_mucosal_involvement",
         "fever_or_systemic_illness", "rapid_spread", "extensive_blistering_or_peeling",
         "pus_or_hot_swollen_skin", "new_medication_or_product_reaction")
RANK = {"track": 0, "low_risk_self_care": 1, "doctor_review": 2, "urgent": 3}
GUIDANCE = {
 "track": "Continue recording changes. Missing information does not establish safety. Seek care if you are concerned.",
 "low_risk_self_care": "Keep care simple and monitor changes. Seek clinician advice if symptoms persist or worsen.",
 "doctor_review": "Arrange clinician review. Seek urgent care if symptoms become severe or spread rapidly.",
 "urgent": "Seek urgent medical assessment now. For breathing difficulty or face, mouth or throat swelling, contact local emergency services now."}

def latest_current_symptoms(current):
    return bool(current and current[-1][1].symptoms)

def evaluate_safety(db, user, now=None):
    now = utc(now or datetime.now(timezone.utc))
    reasons = []
    def add(code, state, summary, evidence):
        reasons.append(SafetyReason(code=code, state=state, summary=summary, evidence=evidence))
    def ref(row, fields):
        return {"source": "checkin", "id": row.id, "recorded_at": utc(row.created_at).isoformat(),
                "kind": "user_reported", "fields": fields,
                "report": report_of(row).model_dump(), "values": {f: getattr(report_of(row).safety, f) for f in fields} if report_of(row).safety else {}}
    rows = db.query(CheckIn).filter_by(user_id=user.id).order_by(CheckIn.created_at, CheckIn.id).all()
    reports = [(r, report_of(r)) for r in rows if utc(r.created_at) <= now and report_of(r)
        and not (r.ai_vision_analysis or {}).get("simulated")
        and (r.ai_vision_analysis or {}).get("measurement_source") not in ("mock", "fake", "simulated")
        and (r.ai_vision_analysis or {}).get("azure_vision_status") not in ("SIMULATED", "SIMULATED_SUCCESS", "FALLBACK_SIMULATED")]
    recent = [(r, p) for r, p in reports if utc(r.created_at) >= now-timedelta(days=14)]
    current = [(r, p) for r, p in recent if utc(r.created_at) >= now-timedelta(hours=72)]
    # Every positive signal in the current window survives later reassuring reports.
    for row, report in current:
        s = report.safety
        if s is None:
            continue
        for field in ("breathing_difficulty", "facial_or_mouth_swelling", "eye_or_mucosal_involvement", "rapid_spread", "extensive_blistering_or_peeling"):
            if getattr(s, field) is True:
                add(field, "urgent", "You reported " + field.replace("_", " ") + "; prompt medical assessment is needed.", [ref(row, [field])])
        if s.pain == "severe" or s.severity == "severe":
            add("severe_symptoms", "urgent", "Severe symptoms or pain were reported.", [ref(row, ["severity", "pain"])])
        concern = bool(report.symptoms) or s.severity in ("mild", "moderate", "severe") or s.pain in ("mild", "moderate", "severe") or s.pus_or_hot_swollen_skin is True
        if s.fever_or_systemic_illness is True and concern:
            add("systemic_with_skin_concern", "urgent", "Systemic illness and a skin concern were reported together.", [ref(row, ["fever_or_systemic_illness", "severity", "pain", "pus_or_hot_swollen_skin"])])
        for field in ("pus_or_hot_swollen_skin", "new_medication_or_product_reaction"):
            if getattr(s, field) is True:
                add(field, "doctor_review", "A reported risk signal needs clinician review; no cause has been determined.", [ref(row, [field])])
        if s.severity == "moderate" or s.pain == "moderate" or report.overall_change == "worse":
            add("concerning_current_report", "doctor_review", "Moderate symptoms, pain or worsening were reported.", [ref(row, ["severity", "pain"] )])
    # Legacy reports can still disclose worsening without the new optional fields.
    for row, report in current:
        if report.safety is None and (report.overall_change == "worse" or set(report.symptoms) & {"burning", "sensitivity"}):
            add("uncertain_current_concern", "doctor_review", "Reported worsening or irritation needs review; severity is unknown.", [ref(row, [])])
    days = {}
    for row, report in recent:
        if report.symptoms:
            days.setdefault(utc(row.created_at).date(), (row, report))
    symptomatic = list(days.values())
    if current and len(symptomatic) >= 3:
        irritation_days = {utc(r.created_at).date() for r,p in recent if set(p.symptoms) & {"burning", "sensitivity"}}
        persistent = (utc(symptomatic[-1][0].created_at).date()-utc(symptomatic[0][0].created_at).date()).days >= 7
        if len(irritation_days) >= 3 or persistent:
            add("persistent_or_repeated_irritation", "doctor_review", "Symptoms persist across report days or irritation was repeatedly reported.", [ref(r, []) for r,p in symptomatic])
    # Stale concerns cannot silently become reassurance; no stale urgent claim.
    for row, report in recent:
        if (row, report) in current:
            continue
        s = report.safety
        if report.overall_change == "worse" or (s and (any(getattr(s, f) is True for f in FLAGS) or s.severity in ("moderate", "severe") or s.pain in ("moderate", "severe"))):
            add("historical_concern_needs_update", "doctor_review", "A recent concerning report needs updated assessment; resolution is not established.", [ref(row, [])])
    experiments = db.query(Experiment).filter_by(user_id=user.id, engine_version=2).all()
    experiment_ids = {e.id for e in experiments}
    evaluations = db.query(ExperimentEvaluation).filter_by(user_id=user.id).order_by(ExperimentEvaluation.created_at, ExperimentEvaluation.id).all()
    latest_evaluations = {}
    for evaluation in evaluations:
        if evaluation.experiment_id in experiment_ids and now-timedelta(days=14) <= utc(evaluation.created_at) <= now:
            latest_evaluations[evaluation.experiment_id] = evaluation
    for evaluation in latest_evaluations.values():
        outcome = evaluation.result or {}
        if (latest_current_symptoms(current) and outcome.get("engine_version") == 2
                and outcome.get("evidence_strength") in ("limited", "moderate")
                and outcome.get("label") in ("likely_associated_worsening", "no_meaningful_change")):
            add("experiment_concern_not_improved", "doctor_review",
                "Current symptoms accompany a recent experiment result with worsening or no meaningful tracked change. Cause is unknown.",
                [{"source": "experiment_evaluation", "id": evaluation.id, "experiment_id": evaluation.experiment_id,
                  "recorded_at": utc(evaluation.created_at).isoformat(), "kind": "server_derived",
                  "label": outcome["label"], "algorithm": "experiment_v2_rules_1"},
                 ref(current[-1][0], [])])
    pi = routine_intelligence(db, user)
    for warning in pi["warnings"]:
        if warning["key"] == "disclosed_sensitivity_match":
            add("explicit_sensitivity_match", "doctor_review", "An active routine ingredient matches a disclosed sensitivity. This does not confirm a reaction.", warning["evidence"] + [{"source": "profile", "id": user.id, "kind": "user_reported", "field": "sensitivities_allergies", "value": warning["disclosure"]}])
        else:
            add("product_"+warning["key"], "track", warning["explanation"], warning["evidence"])
    unknown_products = [p["product_id"] for p in pi["products"] if p["data_completeness"] != "complete"]
    if unknown_products:
        add("unknown_product_facts", "track", "Incomplete ingredient information cannot establish product safety.", [{"source": "product_intelligence", "id": p, "kind": "server_derived"} for p in unknown_products])
    latest = current[-1] if current else None
    complete = bool(latest and latest[1].safety and all(getattr(latest[1].safety, f) is not None for f in FLAGS) and latest[1].safety.severity is not None and latest[1].safety.pain is not None)
    for row, report in current:
        s = report.safety
        screened = bool(s and all(getattr(s, f) is not None for f in FLAGS) and s.severity is not None and s.pain is not None)
        if report.symptoms and not screened:
            add("incomplete_symptom_assessment", "doctor_review", "Symptoms were reported without enough structured safety information.", [ref(row, [])])
    if not any(RANK[r.state] >= 2 for r in reasons):
        if complete and latest[1].symptoms and latest[1].safety.severity == "mild" and latest[1].safety.pain in ("none", "mild") and latest[1].overall_change in ("same", "better") and not unknown_products and not pi["warnings"]:
            add("mild_report_no_disclosed_red_flags", "low_risk_self_care", "A mild stable or improving concern was reported with a complete risk screen. This is not a safety guarantee.", [ref(latest[0], ["severity", "pain", *FLAGS])])
        else:
            add("monitoring_or_insufficient_evidence", "track", "Continue monitoring; this evaluation does not rule out health risks.", [ref(latest[0], [])] if latest else [])
    # Context/visual scores are descriptive, never clinical clearance.
    captures = db.query(Capture).filter_by(user_id=user.id).all()
    measurements = db.query(Measurement).filter_by(user_id=user.id).all()
    contexts = db.query(DailyContext).filter(DailyContext.user_id == user.id,
        DailyContext.date >= (now-timedelta(days=14)).date(), DailyContext.date <= now.date()).all()
    entries = db.query(RoutineEntry).filter_by(user_id=user.id, active=True).all()
    entry_ids = {e.id for e in entries}
    adherence = db.query(RoutineAdherence).filter(RoutineAdherence.user_id == user.id,
        RoutineAdherence.date >= (now-timedelta(days=14)).date(), RoutineAdherence.date <= now.date()).all()
    reasons.sort(key=lambda r: (-RANK[r.state], r.code, str(r.evidence)))
    status = max((r.state for r in reasons), key=RANK.get)
    return SafetyEvaluation(status=status, evaluated_at=now, reasons=reasons,
        evidence_status={"current_report_count": len(current), "risk_screen_complete": complete,
            "stale_or_absent": not bool(current), "unknown_product_ids": unknown_products,
            "visual_evidence": "unavailable_for_triage", "capture_ids": sorted(c.id for c in captures),
            "measurement_ids": sorted(m.id for m in measurements),
            "baseline": "descriptive_scores_not_clinical_clearance",
            "daily_context_ids": sorted(c.id for c in contexts),
            "adherence_ids": sorted(a.id for a in adherence if a.routine_entry_id in entry_ids),
            "experiment_ids": sorted(experiment_ids),
            "context_adherence": "context_only_no_causal_or_sensitive_trait_inference"},
        guidance=GUIDANCE[status], limitations=["Not a diagnosis or a replacement for a doctor.",
            "Escalation uses structured user reports and documented ingredient evidence; no cause is inferred.",
            "Missing flags are unknown. Scores, photos, prose and AI conclusions cannot rule out risk.",
            "72-hour current and 14-day history windows are product rules, not validated clinical thresholds.",
            "Reports older than 14 days do not establish current status; seek care whenever concerned."])
