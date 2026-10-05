import io
from types import SimpleNamespace
from unittest.mock import Mock
import pytest
from PIL import Image
from pydantic import ValidationError
from app.core.config import Settings, settings
from app.services.azure_vision import AzureVisionService
from app.services.azure_safety import AzureSafetyService

@pytest.mark.parametrize("values", [
    {"AZURE_VISION_ENDPOINT": "https://example.com"},
    {"AZURE_VISION_ENDPOINT": "http://example.com", "AZURE_VISION_KEY": "sentinel"},
    {"AZURE_VISION_ENABLED": True},
    {"CONTEXTUAL_AI_ENABLED": True},
    {"AI_PROVIDER_TIMEOUT_SECONDS": 0},
])
def test_invalid_configuration(values, monkeypatch):
    for name in Settings.model_fields:
        monkeypatch.delenv(name, raising=False)
    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None, **values)
    assert "sentinel" not in str(error.value)

def image_bytes():
    stream = io.BytesIO()
    Image.new("RGB", (20, 20), (120, 100, 90)).save(stream, format="PNG")
    return stream.getvalue()

@pytest.mark.parametrize("mode", ["success", "failure", "malformed"])
def test_vision_transport_and_provenance(monkeypatch, mode):
    monkeypatch.setattr(settings, "AZURE_VISION_ENABLED", True)
    monkeypatch.setattr(settings, "AZURE_VISION_ENDPOINT", "https://example.com")
    monkeypatch.setattr(settings, "AZURE_VISION_KEY", "sentinel")
    import httpx
    response = Mock()
    response.json.return_value = {"tagsResult": {"values": []}} if mode == "success" else {}
    if mode == "failure":
        response.raise_for_status.side_effect = RuntimeError("sentinel")
    client = Mock()
    client.__enter__ = Mock(return_value=client)
    client.__exit__ = Mock(return_value=False)
    client.post.return_value = response
    monkeypatch.setattr(httpx, "Client", Mock(return_value=client))
    result = AzureVisionService().analyze_skin_image(image_bytes())
    assert result["measurement_source"] == "image_proxy"
    assert result["azure_vision_status"] == "ANALYSIS_COMPLETE"
    assert result["vision_provider"]["state"] == ("available" if mode == "success" else "degraded")
    assert "sentinel" not in str(result)
    assert client.post.call_args.kwargs["content"] == image_bytes()
    assert client.post.call_args.kwargs["params"]["api-version"] == "2024-02-01"

def test_invalid_image_never_transmitted(monkeypatch):
    monkeypatch.setattr(settings, "AZURE_VISION_ENABLED", True)
    service = AzureVisionService()
    service._analyze_provider = Mock()
    assert service.analyze_skin_image(b"invalid")["azure_vision_status"] == "ANALYSIS_UNAVAILABLE"
    service._analyze_provider.assert_not_called()

def test_content_safety_current_sdk_and_local_precedence(monkeypatch):
    monkeypatch.setattr(settings, "AZURE_CONTENT_SAFETY_ENDPOINT", "")
    monkeypatch.setattr(settings, "AZURE_CONTENT_SAFETY_KEY", "")
    service = AzureSafetyService()
    service.is_live = True
    service.client = Mock()
    service.client.analyze_text.return_value = SimpleNamespace(categories_analysis=[SimpleNamespace(severity=4)])
    assert service.analyze_message_safety("hello")[0]
    service.client.reset_mock()
    assert service.analyze_message_safety("difficulty breathing")[0]
    service.client.analyze_text.assert_not_called()
    service.client.analyze_text.side_effect = RuntimeError("secret")
    result = service.analyze_message_safety("hello")
    assert result[2]["content_safety_state"] == "degraded"
    assert "secret" not in str(result)
