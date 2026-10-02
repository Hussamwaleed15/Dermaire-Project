"""Bounded evidence documents. Each asserted value references explicit provenance."""
from datetime import datetime, timezone
from typing import Annotated, Literal
from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator

TextValue = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Source(StrictModel):
    id: Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_-]{1,50}$")]
    type: Literal["manufacturer_label", "curated_internal", "user_reported", "barcode_provider", "unknown"]
    reference: TextValue
    verification: Literal["unverified", "verified", "unknown"]
    confidence: Literal["unknown", "low", "medium", "high"]
    last_verified_at: datetime | None = None

    @model_validator(mode="after")
    def evidence_state(self):
        if self.type in ("user_reported", "unknown") and (self.verification == "verified" or self.confidence in ("medium", "high")):
            raise ValueError("User-reported/unknown evidence cannot assert verified or medium/high confidence")
        if self.verification == "verified" and self.last_verified_at is None:
            raise ValueError("Verified evidence requires a verification time")
        if self.verification != "verified" and self.last_verified_at is not None:
            raise ValueError("Only verified evidence may have a verification time")
        if self.last_verified_at is not None:
            if self.last_verified_at.tzinfo is None or self.last_verified_at > datetime.now(timezone.utc):
                raise ValueError("Verification time must be timezone-aware and not in the future")
        return self


class Fact(StrictModel):
    value: TextValue
    source_id: TextValue


class Ingredient(StrictModel):
    name: TextValue
    source_id: TextValue
    position: int | None = Field(None, ge=1, le=300, strict=True)
    strength: Fact | None = None  # Verbatim explicit strength; no inferred numeric concentration.


class IngredientList(StrictModel):
    source_id: TextValue
    completeness: Literal["partial", "complete"]
    items: list[Ingredient] = Field(min_length=1, max_length=300)

    @model_validator(mode="after")
    def ordering(self):
        positions = [item.position for item in self.items if item.position is not None]
        if len(positions) != len(set(positions)):
            raise ValueError("Ingredient positions must be unique")
        return self


class IntelligenceDocument(StrictModel):
    sources: list[Source] = Field(min_length=1, max_length=30)
    canonical_name: Fact | None = None
    brand: Fact | None = None
    manufacturer: Fact | None = None
    category: Fact | None = None
    product_type: Fact | None = None
    region: Fact | None = None
    formulation_variant: Fact | None = None
    dosage_form: Fact | None = None
    formulation_text: Fact | None = None
    ingredients: IngredientList | None = None

    @model_validator(mode="after")
    def references(self):
        ids = [source.id for source in self.sources]
        if len(set(ids)) != len(ids):
            raise ValueError("Source IDs must be unique")
        refs = [value.source_id for value in (getattr(self, key) for key in type(self).model_fields)
                if isinstance(value, (Fact, IngredientList))]
        if self.ingredients:
            for ingredient in self.ingredients.items:
                refs.append(ingredient.source_id)
                if ingredient.strength:
                    refs.append(ingredient.strength.source_id)
        if any(ref not in ids for ref in refs):
            raise ValueError("Every claim must reference a source in this document")
        if not refs:
            raise ValueError("At least one supported fact is required")
        return self
