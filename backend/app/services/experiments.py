"""Deterministic observations, not causal or clinical inference. All days are UTC."""
from datetime import datetime, timedelta, timezone
from statistics import mean, pstdev
from math import ceil
from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from app.models import (Experiment, ExperimentEvaluation, RoutineEntry, RoutineAdherence,
                        Product, CheckIn, DailyContext)
from app.services.baseline import confirmed_measurement
from app.services.routine import today, slot_keys, deactivate


def now():
    return datetime.now(timezone.utc).replace(tzinfo=None)


def owned(db, user, identifier):
    row = db.query(Experiment).filter_by(id=identifier, user_id=user.id).first()
    if row is None:
        raise HTTPException(404, "Experiment not found")
    return row


def versioned(row):
    if row.engine_version != 2:
        raise HTTPException(409, "Legacy experiment is read-only; stop it before creating a v2 experiment")


def commit(db):
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(409, "Conflicting experiment or routine configuration")
    except Exception:
        db.rollback()
        raise HTTPException(503, "Experiment write unavailable; refresh before retrying")


def reference(db, user, payload):
    entry = db.query(RoutineEntry).filter_by(id=payload.routine_entry_id, user_id=user.id).first()
    if entry is None:
        raise HTTPException(404, "Routine entry not found")
    product = db.query(Product).filter_by(id=entry.product_id, user_id=user.id).first()
    if product is None:
        raise HTTPException(404, "Product not found")
    if not entry.active or product.status != "active":
        raise HTTPException(409, "Choose an active routine entry and product")
    if payload.intervention.type == "change_schedule" and payload.intervention.schedule == entry.schedule:
        raise HTTPException(422, "Schedule must change")
    if payload.intervention.type == "start_entry" and entry.start_date != payload.start_date:
        raise HTTPException(422, "Start experiments require an entry starting on the planned date")
    return entry, product


def set_definition(row, payload, entry):
    row.routine_entry_id = entry.id
    row.product_id = entry.product_id
    row.intervention = payload.intervention.model_dump()
    row.goal, row.notes = payload.goal, payload.notes
    row.start_date = datetime.combine(payload.start_date, datetime.min.time())
    row.target_days, row.primary_concern = payload.target_days, payload.primary_concern


def evidence_row(row):
    return {"id": row.id, "created_at": row.created_at.isoformat(),
            "source": (row.ai_vision_analysis or {}).get("measurement_source"),
            "metrics": {m: getattr(row, m + "_score") if confirmed_measurement(row) else None for m in ("hydration", "redness", "texture")},
            "report": (row.observation or {}).get("user_reported")}


def activate(db, user, row):
    from app.schemas.experiments import ExperimentCreate
    versioned(row)
    if row.status != "draft":
        raise HTTPException(409, "Only drafts can activate")
    if row.start_date.date() != today():
        raise HTTPException(422, "Activation must be on the planned UTC start day; edit draft first")
    if db.query(Experiment).filter(Experiment.user_id == user.id,
            Experiment.status.in_(["active", "paused", "baseline"])).first():
        raise HTTPException(409, "One active experiment per user; finish the existing experiment first")
    payload = ExperimentCreate(routine_entry_id=row.routine_entry_id, intervention=row.intervention,
        start_date=row.start_date.date(), target_days=row.target_days, primary_concern=row.primary_concern)
    entry, product = reference(db, user, payload)
    previous = configuration(entry)
    if row.intervention["type"] == "start_entry" and entry.schedule != row.intervention["schedule"]:
        raise HTTPException(422, "Start expectation must match the new entry schedule")
    baseline_start = row.start_date - timedelta(days=28)
    baseline = db.query(CheckIn).filter(CheckIn.user_id == user.id,
        CheckIn.created_at >= baseline_start, CheckIn.created_at < row.start_date).order_by(CheckIn.created_at, CheckIn.id).all()
    # Store actual baseline evidence, not just mutable identifiers.
    baseline = [evidence_row(r) for r in baseline if confirmed_measurement(r) or (r.observation or {}).get("user_reported")]
    baseline_context = db.query(DailyContext).filter(DailyContext.user_id == user.id,
        DailyContext.date >= baseline_start.date(), DailyContext.date < row.start_date.date()).all()
    if row.intervention["type"] == "stop_entry":
        deactivate(entry)
    elif row.intervention["type"] == "change_schedule":
        entry.schedule = row.intervention["schedule"]
        slot_keys(entry)
    row.activated_at = now()
    product.in_experiment = True
    product.updated_at = row.activated_at
    if row.intervention["type"] != "start_entry":
        entry.updated_at = row.activated_at
    row.definition_snapshot = {
        "engine_version": 2, "intervention": row.intervention, "goal": row.goal,
        "target_days": row.target_days, "primary_concern": row.primary_concern,
        "product": {"id": product.id, "name": product.name, "updated_at": product.updated_at.isoformat()},
        "before": previous, "expected": configuration(entry),
        "routine_configurations": [configuration(e) for e in db.query(RoutineEntry).filter_by(user_id=user.id).order_by(RoutineEntry.id)],
        "baseline": {"start": baseline_start.isoformat(), "end_exclusive": row.start_date.isoformat(),
            "checkins": baseline, "contexts": [context_data(c) for c in baseline_context]},
        "profile_context": user.profile_context, "frozen_at": row.activated_at.isoformat(),
        "source": "user_configured"}
    row.status, row.active_owner = "active", user.id


def configuration(entry):
    return {"id": entry.id, "product_id": entry.product_id, "schedule": entry.schedule,
        "frequency": entry.frequency, "active": entry.active, "instructions": entry.instructions,
        "am_order": entry.am_order, "pm_order": entry.pm_order,
        "start_date": entry.start_date.isoformat(), "end_date": entry.end_date.isoformat() if entry.end_date else None,
        "updated_at": entry.updated_at.isoformat()}


def context_data(c):
    return {"id": c.id, "date": c.date.isoformat(), "unusual_conditions": c.unusual_conditions,
        "cycle_day": c.cycle_day, "updated_at": c.updated_at.isoformat(), "source": "user_reported"}


def window(row):
    start = row.start_date.date()
    # Current day is incomplete and never dilutes adherence denominator.
    end = min(today() - timedelta(days=1), start + timedelta(days=row.target_days - 1))
    if row.stopped_at:
        end = min(end, row.stopped_at.date() - timedelta(days=1))
    return start, end, max(0, (end - start).days + 1)


def inputs(db, row):
    start, end, days = window(row)
    checks = db.query(CheckIn).filter(CheckIn.user_id == row.user_id,
        CheckIn.created_at >= row.start_date,
        CheckIn.created_at < datetime.combine(end + timedelta(days=1), datetime.min.time())).order_by(CheckIn.created_at, CheckIn.id).all() if days else []
    checks = [c for c in checks if c.created_at >= row.activated_at and
              (confirmed_measurement(c) or (c.observation or {}).get("user_reported"))]
    logs = db.query(RoutineAdherence).filter(RoutineAdherence.user_id == row.user_id,
        RoutineAdherence.routine_entry_id == row.routine_entry_id,
        RoutineAdherence.date >= start, RoutineAdherence.date <= end).all() if days else []
    # Earlier reports on activation day cannot establish following the change.
    logs = [l for l in logs if l.created_at >= row.activated_at]
    contexts = db.query(DailyContext).filter(DailyContext.user_id == row.user_id,
        DailyContext.date >= start, DailyContext.date <= end).all() if days else []
    return checks, logs, contexts


def coverage(db, row):
    if row.engine_version != 2 or not row.activated_at:
        return {"elapsed_days": 0, "observed_days": 0, "checkins": 0, "adherence_coverage": 0,
                "context_coverage": 0, "latest_checkin_at": None}
    checks, logs, contexts = inputs(db, row)
    _, _, days = window(row)
    slots = 2 if row.definition_snapshot["expected"]["schedule"] == "BOTH" else 1
    return {"elapsed_days": days, "observed_days": len({c.created_at.date() for c in checks}),
        "checkins": len(checks), "adherence_coverage": min(1, len(logs)/(days*slots)) if days else 0,
        "context_coverage": sum(c.unusual_conditions is not None for c in contexts)/days if days else 0,
        "latest_checkin_at": checks[-1].created_at.isoformat() if checks else None}


def daily_measurements(rows, source, metric):
    # Average within a day, then weight days equally; never mix proxy/manual scales.
    days = {}
    for r in rows:
        if r["source"] == source and r["metrics"][metric] is not None:
            days.setdefault(r["created_at"][:10], []).append(r["metrics"][metric])
    return [mean(v) for v in days.values()]


def evaluate(db, row):
    versioned(row)
    if not row.activated_at or row.status == "cancelled":
        raise HTTPException(409, "Activate the experiment before evaluation")
    checks, logs, contexts = inputs(db, row)
    cov = coverage(db, row)
    snap = row.definition_snapshot
    baseline = snap["baseline"]["checkins"]
    metric = row.primary_concern
    source = max(("manual", "image_proxy"), key=lambda s: min(
        len(daily_measurements(baseline, s, metric)),
        len(daily_measurements([evidence_row(c) for c in checks if confirmed_measurement(c)], s, metric))))
    prior = daily_measurements(baseline, source, metric)
    after = daily_measurements([evidence_row(c) for c in checks if confirmed_measurement(c)], source, metric)
    expected_status = "skipped" if row.intervention["type"] == "stop_entry" else "completed"
    expected = snap["expected"]
    slots = ("AM", "PM") if expected["schedule"] == "BOTH" else (expected["schedule"],)
    valid_logs = [l for l in logs if l.slot in slots and all(
        l.configuration_snapshot.get(k) == expected[k] for k in ("schedule", "active", "frequency", "product_id"))]
    denominator = cov["elapsed_days"] * len(slots)
    followed = sum(l.status == expected_status for l in valid_logs)
    adherence = {"expected_status": expected_status, "expected_slots": denominator,
        "reported_slots": len(valid_logs), "followed_slots": followed,
        "coverage": len(valid_logs)/denominator if denominator else 0,
        "followed_fraction": followed/denominator if denominator else 0,
        "source": "user_reported", "expectation": expected}
    current = [configuration(e) for e in db.query(RoutineEntry).filter_by(user_id=row.user_id).order_by(RoutineEntry.id)]
    changed_routine = current != snap["routine_configurations"]
    # Product edits, including transient edits with reverted content, limit interpretation.
    product = db.query(Product).filter_by(id=row.product_id, user_id=row.user_id).first()
    product_time = row.stopped_at.isoformat() if row.stopped_at else snap["product"]["updated_at"]
    changed_product = not product or product.updated_at.isoformat() != product_time or product.status != "active" or product.name != snap["product"]["name"]
    unusual = sum(c.unusual_conditions is True for c in contexts)
    baseline_unusual = any(c["unusual_conditions"] is True for c in snap["baseline"]["contexts"])
    baseline_inconsistent = any((c.get("report") or {}).get("routine_status") in ("partial", "skipped") for c in baseline)
    reports = [(c.observation or {}).get("user_reported") for c in checks]
    inconsistent = any(r and r.get("routine_status") in ("partial", "skipped") for r in reports) if expected_status == "completed" else False
    major = unusual / cov["elapsed_days"] >= .3 if cov["elapsed_days"] else False
    confounders = {"unusual_days": unusual, "baseline_unusual_conditions": baseline_unusual,
        "routine_changed_after_activation": changed_routine, "product_changed_after_activation": changed_product,
        "baseline_inconsistent_routine_reports": baseline_inconsistent,
        "inconsistent_routine_reports": inconsistent, "cycle_context_days": sum(c.cycle_day is not None for c in contexts),
        "interpretation": "Cycle context is disclosed context; no automatic medical adjustment."}
    delta = mean(after) - mean(prior) if prior and after else None
    threshold = max(5, 2 * pstdev(prior)) if len(prior) >= 5 else None
    latest = max((c.created_at.date() for c in checks if confirmed_measurement(c) and (c.ai_vision_analysis or {}).get("measurement_source") == source), default=None)
    _, end, _ = window(row)
    prior_dates = [datetime.fromisoformat(c["created_at"]).date() for c in baseline
                   if c["source"] == source and c["metrics"][metric] is not None]
    latest_prior = max(prior_dates) if prior_dates else None
    sufficient = (cov["elapsed_days"] >= 7 and len(prior) >= 5
        and len(after) >= max(5, ceil(cov["elapsed_days"] * .5))
        and latest is not None and (end-latest).days <= 3
        and latest_prior is not None and (row.start_date.date()-latest_prior).days <= 7
        and pstdev(prior) <= 15 and pstdev(after) <= 15)
    label, strength = "insufficient_evidence", "insufficient"
    if sufficient:
        if adherence["coverage"] < .8 or adherence["followed_fraction"] < .8 or cov["context_coverage"] < .7 or major or baseline_unusual or baseline_inconsistent or changed_routine or changed_product or inconsistent:
            label, strength = "confounded_or_low_adherence", "limited"
        else:
            strength = "moderate" if len(after) >= 10 and cov["context_coverage"] >= .9 and source == "manual" else "limited"
            if abs(delta) < threshold:
                label = "no_meaningful_change"
            else:
                improved = delta < 0 if metric == "redness" else delta > 0
                label = "likely_associated_improvement" if improved else "likely_associated_worsening"
            # Contradictory day-level changes cannot be reduced to a directional mean.
            signs = [v-mean(prior) for v in after]
            if any(v >= threshold for v in signs) and any(v <= -threshold for v in signs):
                label, strength = "insufficient_evidence", "insufficient"
            if label.startswith("likely") and sum((v > 0) == (delta > 0) for v in signs)/len(signs) < .8:
                label, strength = "insufficient_evidence", "insufficient"
            contrary = "worse" if label == "likely_associated_improvement" else "better"
            if label.startswith("likely") and any(r and r.get("overall_change") == contrary for r in reports):
                label, strength = "insufficient_evidence", "insufficient"
    summaries = {
        "insufficient_evidence": "There is not enough consistent, recent evidence to interpret this change.",
        "confounded_or_low_adherence": "Adherence, missing context or other changes limit interpretation of the observed differences.",
        "no_meaningful_change": "No meaningful difference was observed against your prior history within the defined descriptive threshold.",
        "likely_associated_improvement": "An improvement in the tracked score was observed during the planned change. This is an association, not evidence that the change caused it.",
        "likely_associated_worsening": "A worsening in the tracked score was observed during the planned change. This is an association, not evidence that the change caused it."}
    result = {"engine_version": 2, "label": label, "evidence_strength": strength,
        "evidence_summary": summaries[label], "comparison": {"start": snap["baseline"]["start"],
            "end_exclusive": snap["baseline"]["end_exclusive"], "strategy": "previous_28_UTC_days_frozen_at_activation",
            "baseline_days": len(prior), "experiment_days": len(after), "measurement_source": source},
        "adherence": adherence, "confounders": confounders, "coverage": cov,
        "observed_change": {"metric": metric, "baseline_mean": mean(prior) if prior else None,
            "experiment_mean": mean(after) if after else None, "delta_points": round(delta, 2) if delta is not None else None,
            "descriptive_threshold_points": threshold, "reported_checkins": sum(r is not None for r in reports)},
        "provenance": {"source": "server_derived", "algorithm": "experiment_v2_rules_1",
            "definition_snapshot": snap, "experiment_checkins": [evidence_row(c) for c in checks],
            "adherence": [{"id": l.id, "date": l.date.isoformat(), "slot": l.slot, "status": l.status,
                "created_at": l.created_at.isoformat(), "source": l.source, "configuration_snapshot": l.configuration_snapshot} for l in logs],
            "contexts": [context_data(c) for c in contexts]},
        "limitations": ["Observational, self-reported evidence cannot establish causality or a diagnosis.",
            "Scores and image proxies are not clinical measurements; sources are never pooled.",
            "Missing reports are unknown, not confirmed non-use. Stop adherence means reported skipped use.",
            "Unreported confounders and changes outside Dermaire cannot be ruled out.",
            "Evidence strength is a rule-based description, not a probability or statistical confidence interval.",
            "Texture/hydration use higher-is-better score semantics; redness uses lower-is-better.",
            "Structured reports supplement measurements; report-only histories cannot support directional labels in v2."],
        "evaluated_at": now().isoformat()}
    evaluation = ExperimentEvaluation(user_id=row.user_id, experiment_id=row.id, result=result)
    db.add(evaluation)
    return evaluation


def guard_routine_write(db, user_id):
    if db.query(Experiment).filter_by(user_id=user_id, engine_version=2, status="active").first():
        raise HTTPException(409, "Stop the active experiment before changing routine configuration")


def stopped_experiment(db, user_id, entry_id):
    row = db.query(Experiment).filter_by(user_id=user_id, routine_entry_id=entry_id, engine_version=2, status="active").first()
    return row if row and row.intervention["type"] == "stop_entry" else None
