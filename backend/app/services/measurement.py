"""Deterministic image appearance proxies, never clinical measurements."""
from datetime import datetime, timezone
import cv2
import numpy as np
from sqlalchemy import and_, or_
from app.models import Measurement, Capture
from app.services import capture_quality

VERSION = "measurement-1.0"
LIMITATIONS = ["Fixed cheek rectangles are not validated skin segmentation; hair, cosmetics and shadows can contaminate them.",
               "Camera processing, color balance and lighting affect these image proxies.",
               "No medical interpretation, calibrated physical roughness or probability of accuracy."]
SPECS = {
    "red_chromaticity_proxy": ("fraction_0_to_1", "Median R/(R+G+B) in fixed cheek patches; not redness severity."),
    "texture_contrast_proxy": ("fraction_0_to_1", "Mean absolute grayscale residual from a 5x5 Gaussian blur / 255 at fixed patch resolution; not physical roughness."),
}


def compute(image, quality):
    if quality.get("decision") != "accepted":
        return "insufficient_quality", {}, "capture_not_accepted"
    factor = capture_quality.RULES.analysis_size / max(image.size)
    rgb = np.asarray(image.resize(tuple(max(1, round(d * factor)) for d in image.size)))
    faces, _ = capture_quality.detect_geometry(cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY))
    if len(faces) != 1:
        return "insufficient_quality", {}, "cheek_regions_unavailable"
    x, y, w, h = faces[0]
    patches = [rgb[y+round(.50*h):y+round(.68*h), x+round(a*w):x+round(b*w)]
               for a, b in ((.18, .36), (.64, .82))]
    if any(p.shape[0] < 16 or p.shape[1] < 16 for p in patches):
        return "insufficient_quality", {}, "cheek_regions_too_small"
    reds, textures = [], []
    for patch in patches:
        # Avoid manufacturing a number from clipped, dark, or washed-out patches.
        gray = cv2.cvtColor(patch, cv2.COLOR_RGB2GRAY)
        usable = (gray > 20) & (gray < 235)
        if np.mean(usable) < .9:
            return "insufficient_quality", {}, "cheek_exposure_insufficient"
        pixels = patch.astype(np.float64)
        reds.extend((pixels[..., 0] / np.maximum(pixels.sum(axis=2), 1))[usable].tolist())
        fixed = cv2.resize(gray, (64, 64), interpolation=cv2.INTER_AREA).astype(np.float32)
        textures.append(float(np.mean(np.abs(fixed - cv2.GaussianBlur(fixed, (5, 5), 0))) / 255))
    return "measured", {"red_chromaticity_proxy": round(float(np.median(reds)), 3),
                        "texture_contrast_proxy": round(float(np.mean(textures)), 3)}, None


def compare(current, previous):
    result = {"state": "not_comparable", "reason": "no_previous_measured_capture",
              "previous_comparable_measurement_id": None, "previous_measurement_id": previous.id if previous else None,
              "deltas": None}
    if not previous:
        return result
    if current.user_id != previous.user_id or current.algorithm_version != previous.algorithm_version:
        result["reason"] = "owner_or_algorithm_mismatch"
        return result
    if current.status != "measured" or previous.status != "measured":
        result["reason"] = "measurement_unavailable"
        return result
    cq, pq = current.quality_reference, previous.quality_reference
    if cq.get("version") != pq.get("version") or cq.get("decision") != "accepted" or pq.get("decision") != "accepted":
        result["reason"] = "quality_version_or_acceptance_mismatch"
        return result
    for key in ("yaw", "pitch", "occlusion", "uneven_lighting"):
        if any(q.get("checks", {}).get(key, {}).get("status") != "pass" for q in (cq, pq)):
            result["reason"] = "unknown_or_failed_" + key
            return result
    limits = (("scale", "face_width_fraction", .05), ("roll", "degrees", 3),
              ("exposure", "dark_clipped_fraction", .03), ("exposure", "bright_clipped_fraction", .03),
              ("framing", "center_offset_x", .03), ("framing", "center_offset_y", .03))
    for check, metric, limit in limits:
        entries = [q.get("checks", {}).get(check, {}) for q in (cq, pq)]
        values = [e.get("metrics", {}).get(metric) for e in entries]
        if any(e.get("status") != "pass" for e in entries) or any(type(v) not in (int, float) or not np.isfinite(v) for v in values):
            result["reason"] = "unknown_" + check
            return result
        if abs(values[0] - values[1]) > limit:
            result["reason"] = "mismatch_" + check
            return result
    sharpness = [q.get("checks", {}).get("sharpness", {}) for q in (cq, pq)]
    sharpness_values = [e.get("metrics", {}).get("laplacian_variance") for e in sharpness]
    if any(e.get("status") != "pass" for e in sharpness) or any(type(v) not in (int, float) or not np.isfinite(v) or v <= 0 for v in sharpness_values):
        result["reason"] = "unknown_sharpness"
        return result
    if max(sharpness_values) / min(sharpness_values) > 1.5:
        result["reason"] = "mismatch_sharpness"
        return result
    for key in SPECS:
        metrics = [row.results.get(key, {}) for row in (current, previous)]
        if any(m.get("status") != "measured" or m.get("method_version") != current.algorithm_version
               or m.get("unit") != SPECS[key][0] or type(m.get("value")) not in (float, int)
               or not np.isfinite(m["value"]) or not 0 <= m["value"] <= 1 for m in metrics):
            result["reason"] = "invalid_metric_provenance"
            return result
    # Reserved for a future quality gate with validated missing dimensions.
    # Current gate can never reach this branch with genuine server metadata.
    deltas = {}
    for key in SPECS:
        a, b = current.results[key]["value"], previous.results[key]["value"]
        delta = round(a - b, 3)
        threshold = .01 if key == "red_chromaticity_proxy" else .005
        deltas[key] = {"value": delta, "unit": SPECS[key][0],
                       "change": "no_meaningful_change" if abs(delta) <= threshold else "increase" if delta > 0 else "decrease",
                       "threshold": threshold, "interpretation": "Engineering tolerance only; no clinical significance."}
    result.update(state="comparable", reason=None, previous_comparable_measurement_id=previous.id, deltas=deltas)
    return result


def build(db, capture, image=None):
    if capture.state != "accepted":
        raise ValueError("Only accepted captures can be measured")
    existing = db.query(Measurement).filter_by(capture_id=capture.id, user_id=capture.user_id, algorithm_version=VERSION).first()
    if existing:
        return existing
    when = datetime.now(timezone.utc)
    status, values, reason = "unavailable", {}, "historical_image_bytes_unavailable"
    if image is not None:
        try:
            status, values, reason = compute(image, capture.quality)
        except Exception:
            status, values, reason = "failed", {}, "measurement_processing_failed"
    results = {key: {"key": key, "value": values.get(key), "unit": unit, "meaning": meaning,
                     "status": status, "reliability": "limited_image_proxy" if status == "measured" else "unavailable",
                     "method_version": VERSION, "source_capture_id": capture.id,
                     "region": "fixed_bilateral_cheek_rectangles_from_frontal_face_detector",
                     "measured_at": when.isoformat(), "limitations": LIMITATIONS, "reason": reason}
               for key, (unit, meaning) in SPECS.items()}
    row = Measurement(user_id=capture.user_id, capture_id=capture.id, algorithm_version=VERSION,
                      status=status, measured_at=when, results=results, quality_reference=capture.quality)
    # Strictly earlier capture receipt order, regardless of historical generation time.
    candidates = (db.query(Measurement).join(Capture, Measurement.capture_id == Capture.id)
                  .filter(Measurement.user_id == capture.user_id, Capture.user_id == capture.user_id,
                          Capture.state == "accepted", Measurement.algorithm_version == VERSION,
                          Measurement.status == "measured",
                          or_(Capture.received_at < capture.received_at,
                              and_(Capture.received_at == capture.received_at, Capture.id < capture.id)))
                  .order_by(Capture.received_at.desc(), Capture.id.desc()))
    row.comparison = compare(row, None)
    current_blocked = row.status != "measured" or any(
        capture.quality.get("checks", {}).get(key, {}).get("status") != "pass"
        for key in ("yaw", "pitch", "occlusion", "uneven_lighting"))
    for index, previous in enumerate(candidates.yield_per(100)):
        comparison = compare(row, previous)
        if index == 0:
            row.comparison = comparison
        if comparison["state"] == "comparable":
            row.comparison = comparison
            break
        if current_blocked:
            break
    db.add(row)
    db.flush()
    return row


def response(row):
    return {"id": row.id, "capture_id": row.capture_id, "algorithm_version": row.algorithm_version,
            "status": row.status, "measured_at": row.measured_at.replace(tzinfo=timezone.utc),
            "metrics": row.results, "capture_quality": row.quality_reference, "comparison": row.comparison,
            "provenance": "server_computed_from_upload_bytes" if row.status != "unavailable" else "server_recorded_unavailability"}
