"""Typed, fail-closed inference contracts. No transport or clinical model bundled.

Adapters must return validated envelopes and may never turn unavailable inference
into synthetic patient results. Test doubles are explicitly nonclinical.
"""
from typing import Literal, Protocol
from pydantic import BaseModel, ConfigDict, Field, model_validator


class AgentInference(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    schema_version: Literal["agent-model-boundary-1"] = "agent-model-boundary-1"
    status: Literal["unavailable", "generated"]
    provider: str | None = None
    model_version: str | None = None
    invoked: bool = False
    reason: str | None = None
    response: str | None = None

    @model_validator(mode="after")
    def truthful(self):
        if self.status == "unavailable" and (self.response is not None or self.invoked):
            raise ValueError("Unavailable inference cannot contain a generated response")
        if self.status == "generated" and (not self.invoked or not self.provider or not self.model_version or not self.response):
            raise ValueError("Generated inference requires provider provenance")
        return self


class ComparisonInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    schema_version: Literal["comparison-input-1"] = "comparison-input-1"
    plan_id: str
    plan_revision: int = Field(ge=1)
    baseline_capture_id: str
    followup_capture_id: str
    consent_revision: int = Field(ge=1)


class ComparisonEvidence(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    schema_version: Literal["comparison-evidence-1"] = "comparison-evidence-1"
    baseline_capture_id: str
    followup_capture_id: str
    provenance: Literal["nonclinical_image_quality_only"]
    quality_flags: list[Literal["lighting_mismatch","pose_mismatch","blur","occlusion","insufficient_evidence"]] = Field(max_length=5)


class ComparisonInference(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    schema_version: Literal["comparison-model-boundary-1"] = "comparison-model-boundary-1"
    status: Literal["unavailable", "pending_human_review"]
    reason: str | None = None
    model_version: str | None = None
    artifact_sha256: str | None = Field(None, pattern=r"^[a-f0-9]{64}$")
    result: ComparisonEvidence | None = None
    clinical_clearance: Literal[False] = False

    @model_validator(mode="after")
    def truthful(self):
        if self.status == "unavailable" and self.result is not None:
            raise ValueError("Unavailable comparison cannot contain results")
        if self.status == "pending_human_review" and (not self.model_version or not self.artifact_sha256 or self.result is None):
            raise ValueError("Comparison results require versioned artifact provenance")
        return self


class AgentProvider(Protocol):
    def respond(self, *, context: dict | None, message: str | None) -> AgentInference: ...


class ComparisonProvider(Protocol):
    def evaluate(self, request: ComparisonInput) -> ComparisonInference: ...


class DisabledComparisonProvider:
    def evaluate(self, request: ComparisonInput) -> ComparisonInference:
        return ComparisonInference(status="unavailable",reason="validated_model_not_integrated")


class ModelProviderConfig(BaseModel):
    """Public nonsecret configuration contract; transport is never implied."""
    model_config = ConfigDict(extra="forbid", strict=True)
    schema_version: Literal["model-provider-config-1"] = "model-provider-config-1"
    provider: str = Field(default="disabled", min_length=1, max_length=100)
    model_version: str | None = None
    artifact_sha256: str | None = Field(None,pattern=r"^[a-f0-9]{64}$")
    validation_reference: str | None = None
    transport_enabled: Literal[False] = False


def agent_provider_state():
    import os
    requested=os.environ.get("DERMAIRE_AGENT_MODEL_PROVIDER","disabled")
    # Unsupported configuration cannot silently activate external inference.
    config=ModelProviderConfig(provider=requested)
    return config, AgentInference(status="unavailable",reason="agent_model_not_integrated" if requested=="disabled" else "configured_provider_adapter_unavailable")
