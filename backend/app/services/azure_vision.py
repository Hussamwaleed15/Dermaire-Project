import io
import math
from typing import Dict, Any
from app.core.config import settings
from app.core.observability import operation_event

class AzureVisionService:
    def __init__(self):
        self.is_live = settings.is_vision_live

    def analyze_skin_image(self, image_bytes: bytes) -> Dict[str, Any]:
        # Validate/decode locally before any transmission. Provider metadata never
        # supplies clinical scores or changes deterministic measurement provenance.
        provider = {"provider": "azure_vision", "state": "disabled", "authoritative": False}
        # Smart fallback image metrics calculation based on image properties
        try:
            from PIL import Image, ImageStat
            image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
            stat = ImageStat.Stat(image)
            r, g, b = stat.mean
            
            # Redness ratio (Erythema index proxy)
            red_ratio = r / (g + b + 1e-5)
            redness_score = min(100.0, max(5.0, round(red_ratio * 40.0, 1)))

            # Smoothness/texture proxy from variance
            variance = sum(stat.var) / 3.0
            texture_score = min(100.0, max(20.0, round(100.0 - math.sqrt(variance) * 0.5, 1)))
            hydration_score = min(100.0, max(0.0, round((100.0 - (redness_score * 0.4) + (texture_score * 0.6)) / 1.2, 1)))

            if settings.AZURE_VISION_ENABLED:
                provider = self._analyze_provider(image_bytes)
            return {
                "vision_provider": provider,
                "azure_vision_status": "ANALYSIS_COMPLETE",
                "measurement_source": "image_proxy",
                "measurement_method": "Local image-property proxy; not Azure clinical analysis",
                "image_resolution": f"{image.width}x{image.height}",
                "erythema_redness_score": redness_score,
                "surface_texture_score": texture_score,
                "estimated_hydration_score": hydration_score,
                "lighting_quality": "optimal" if 80 < (r+g+b)/3 < 200 else "suboptimal",
                "clinical_disclaimer": "Visual estimates are for self-tracking experiments and do not constitute a diagnostic claim."
            }
        except Exception as e:
            return {
                "azure_vision_status": "ANALYSIS_UNAVAILABLE",
                "error": "Invalid or unsupported image"
            }

    def _analyze_provider(self, image_bytes):
        import httpx
        try:
            with httpx.Client(timeout=settings.AI_PROVIDER_TIMEOUT_SECONDS,
                              follow_redirects=False) as client:
                response = client.post(
                    settings.AZURE_VISION_ENDPOINT + "/computervision/imageanalysis:analyze",
                    params={"api-version": "2024-02-01", "features": "tags"},
                    headers={"Ocp-Apim-Subscription-Key": settings.AZURE_VISION_KEY,
                             "Content-Type": "application/octet-stream"}, content=image_bytes)
                response.raise_for_status()
                result = response.json()
                # Deliberately discard tags: general image labels are not medical facts.
                if not isinstance(result.get("tagsResult", {}).get("values"), list):
                    raise ValueError("Invalid provider envelope")
                operation_event("vision", "available")
                return {"provider": "azure_vision", "state": "available",
                        "authoritative": False, "feature": "tags",
                        "clinical_measurement": False}
        except Exception:
            operation_event("vision", "degraded")
            return {"provider": "azure_vision", "state": "degraded",
                    "authoritative": False, "reason": "provider_failure"}

azure_vision_service = AzureVisionService()
