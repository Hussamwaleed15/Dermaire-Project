"""Non-medical image quality rules. No Azure AI or simulated success."""
from dataclasses import asdict, dataclass
from io import BytesIO
import math
import struct
import warnings

import cv2
import numpy as np
from PIL import Image, UnidentifiedImageError
from fastapi import HTTPException

VERSION = "capture-quality-1.0"


@dataclass(frozen=True)
class Thresholds:
    max_bytes: int = 8 * 1024 * 1024
    max_pixels: int = 16_000_000
    min_dimension: int = 640
    analysis_size: int = 800
    face_width_min: float = .30
    face_width_max: float = .70
    center_offset_max: float = .15
    border_margin: float = .03
    sharpness_min: float = 20
    dark_fraction_max: float = .35
    bright_fraction_max: float = .20
    roll_max: float = 10


RULES = Thresholds()


def decode_image(data, declared_type):
    if len(data) > RULES.max_bytes:
        raise HTTPException(413, "Image must be at most 8 MiB.")
    if declared_type not in ("image/jpeg", "image/png"):
        raise HTTPException(415, "Use a JPEG or PNG image.")
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            image = Image.open(BytesIO(data))
            expected = {"image/jpeg": "JPEG", "image/png": "PNG"}[declared_type]
            if image.format != expected or getattr(image, "n_frames", 1) != 1:
                raise HTTPException(415, "Use a single JPEG or PNG matching its media type.")
            if image.width * image.height > RULES.max_pixels:
                raise HTTPException(413, "Image exceeds 16 megapixels.")
            orientation = image.getexif().get(274, 1)
            if not isinstance(orientation, int) or orientation not in range(1, 9):
                raise HTTPException(422, "Invalid orientation metadata. Export a new upright photo.")
            image.load()
            if "A" in image.getbands() or "transparency" in image.info:
                raise HTTPException(415, "Use an opaque JPEG or PNG photograph.")
            return image.convert("RGB"), orientation
    except (UnidentifiedImageError, OSError, ValueError, SyntaxError, TypeError, OverflowError, struct.error):
        raise HTTPException(422, "Image is corrupt. Export a new JPEG or PNG and retry.")
    except (Image.DecompressionBombError, Image.DecompressionBombWarning):
        raise HTTPException(413, "Image dimensions are unsafe.")


def detect_geometry(gray):
    # Construct per request: CascadeClassifier instances are mutable native objects.
    face = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_frontalface_default.xml")
    eye = cv2.CascadeClassifier(cv2.data.haarcascades + "haarcascade_eye.xml")
    if face.empty() or eye.empty():
        raise RuntimeError("Capture detector unavailable")
    faces = face.detectMultiScale(gray, 1.1, 5, minSize=(80, 80))
    eyes = []
    if len(faces) == 1:
        x, y, w, h = map(int, faces[0])
        for ex, ey, ew, eh in eye.detectMultiScale(gray[y:y + h // 2, x:x + w], 1.1, 5):
            eyes.append((x + float(ex + ew / 2), y + float(ey + eh / 2)))
    return [tuple(map(int, f)) for f in faces], sorted(eyes)


def assess(image, orientation):
    checks = {}

    def check(name, passed, metrics, reason, confidence="heuristic"):
        checks[name] = {"status": "unknown" if passed is None else "pass" if passed else "fail",
                        "metrics": metrics, "confidence": confidence,
                        "reason": reason if passed is not True else None}

    width, height = image.size
    check("resolution", min(width, height) >= RULES.min_dimension,
          {"width": width, "height": height}, "Use a photograph at least 640 pixels on each side.", "measured")
    check("orientation", orientation == 1 and height >= width,
          {"exif_orientation": orientation}, "Retake upright in portrait orientation; export with rotation applied.", "measured")
    factor = RULES.analysis_size / max(width, height)
    gray = cv2.cvtColor(np.asarray(image.resize((max(1, round(width * factor)), max(1, round(height * factor))))), cv2.COLOR_RGB2GRAY)
    faces, eyes = detect_geometry(gray)
    gh, gw = gray.shape
    check("face", len(faces) == 1, {"detected_count": len(faces)}, "Show one unobstructed face, facing the camera.")
    region = gray
    if len(faces) == 1:
        x, y, w, h = faces[0]
        region = gray[y:y+h, x:x+w]
        scale = w / gw
        centered = abs((x+w/2)/gw-.5) <= RULES.center_offset_max and abs((y+h/2)/gh-.5) <= RULES.center_offset_max
        margin = min(x/gw, y/gh, (gw-x-w)/gw, (gh-y-h)/gh)
        check("framing", centered and margin >= RULES.border_margin,
              {"center_offset_x": abs((x+w/2)/gw-.5), "center_offset_y": abs((y+h/2)/gh-.5), "margin": margin}, "Center your whole face with space around its edges.")
        check("scale", RULES.face_width_min <= scale <= RULES.face_width_max,
              {"face_width_fraction": scale}, "Move closer." if scale < RULES.face_width_min else "Move farther away.")
    else:
        for key in ("framing", "scale"):
            check(key, None, {}, "Show one centered face so framing can be checked.")
    roll = None
    eye_pair_valid = False
    if len(faces) == 1 and len(eyes) == 2:
        x, y, w, h = faces[0]
        (lx, ly), (rx, ry) = eyes
        eye_pair_valid = (x + .1*w < lx < x + .5*w < rx < x + .9*w and .2 <= (rx-lx)/w <= .7)
        roll = math.degrees(math.atan2(ry-ly, rx-lx))
    check("roll", eye_pair_valid and abs(roll) <= RULES.roll_max if roll is not None else None,
          {"degrees": roll, "eye_pair_detected": eye_pair_valid}, "Keep your head level, face forward, and make both eyes visible.")
    # Frontal detector + both eyes is only a coarse pose proxy, never yaw/pitch degrees.
    check("coarse_front_view", eye_pair_valid, {}, "Face the camera directly with both eyes visible.")
    for key in ("yaw", "pitch", "occlusion", "uneven_lighting"):
        check(key, None, {}, "Not reliably measured by v1.", "unavailable")
    sharpness = float(cv2.Laplacian(cv2.resize(region, (256, 256), interpolation=cv2.INTER_AREA), cv2.CV_64F).var())
    dark = float(np.mean(region <= 10))
    bright = float(np.mean(region >= 245))
    check("sharpness", sharpness >= RULES.sharpness_min, {"laplacian_variance": sharpness}, "Hold still, clean the lens, and refocus.")
    check("exposure", dark <= RULES.dark_fraction_max and bright <= RULES.bright_fraction_max,
          {"dark_clipped_fraction": dark, "bright_clipped_fraction": bright}, "Use soft even light; avoid darkness, direct sunlight, and flash.", "measured")
    required = ("resolution", "orientation", "face", "framing", "scale", "roll", "coarse_front_view", "sharpness", "exposure")
    reasons = list(dict.fromkeys(checks[k]["reason"] for k in required if checks[k]["status"] != "pass"))
    return {"version": VERSION, "decision": "rejected" if reasons else "accepted", "checks": checks,
            "reasons": reasons, "thresholds": asdict(RULES),
            "limitations": ["Acceptance is a heuristic quality screen, not proof of longitudinal comparability.",
                            "Yaw, pitch, obstruction and uneven lighting remain unknown.",
                            "No diagnosis, identity recognition, or skin measurement is performed."]}
