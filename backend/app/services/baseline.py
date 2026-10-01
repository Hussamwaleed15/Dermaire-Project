"""Baseline is derived from confirmed measurements, never a stored counter."""
import math
from datetime import datetime, timezone
from statistics import mean, pstdev

from app.models import CheckIn


def confirmed_measurement(row):
    analysis = row.ai_vision_analysis or {}
    values = [row.hydration_score, row.texture_score, row.redness_score]
    return analysis.get("measurement_source") in ("manual", "image_proxy") and all(
        v is not None and math.isfinite(v) and 0 <= v <= 100 for v in values)


def baseline_snapshot(db, user_id, before=None):
    # Only confirmed, unlinked measurements qualify. Freeze the first five
    # distinct UTC days so later history cannot silently change the reference.
    rows = db.query(CheckIn).filter(CheckIn.user_id == user_id,
                                  CheckIn.experiment_id.is_(None)).order_by(
        CheckIn.created_at, CheckIn.id).all()
    days, selected = set(), []
    for row in rows:
        if before and row.created_at >= before:
            continue
        if not confirmed_measurement(row):
            continue  # Legacy/default/simulated measurements are quarantined.
        day = row.created_at.date()
        if day not in days and len(selected) < 5:
            days.add(day)
            selected.append(row)
    ready = len(selected) == 5
    metrics = {}
    if ready:
        for name in ("hydration", "texture", "redness"):
            values = [getattr(row, name + "_score") for row in selected]
            metrics[name] = {"mean": mean(values), "standard_deviation": pstdev(values)}
    today = datetime.now(timezone.utc).date()
    return {"status": "ready" if ready else "collecting", "required_days": 5,
            "completed_days": len(selected), "checkin_ids": [r.id for r in selected],
            "metrics": metrics, "today_checked_in": any(r.created_at.date() == today for r in rows
                if confirmed_measurement(r))}
