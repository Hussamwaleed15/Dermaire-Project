# Product Intelligence v1

## Authority and model

Backend version `product-intelligence-1.0` owns all normalization and warning computation. Saved `products` remain user-owned records; no existing fields are overwritten by intelligence ingestion. One optional `product_intelligence` row per product stores a bounded, validated JSON evidence document, owner ID, product ID and update timestamp. This is owner-specific evidence, not a shared catalog. No shared intelligence survives deletion in v1.

JSON is intentional: minimum one table, no new global product identity, no ontology tables and no duplicated provenance joins. Every asserted fact references a source ID in its document. Unknown facts are null/absent. IDs in ingredients are response references scoped to the current product document, not immutable historical evidence identifiers.

## Supported facts

Canonical name, brand, manufacturer, category/type, region, formulation variant, dosage form and formulation text are optional sourced strings. Structured ingredients carry original name, source ID, optional label position and optional strength with its own source ID. Strength is explicit source text such as `5% w/w`; it is never parsed or inferred from product names, free-text actives, ingredient order or category. A strength statement can have different provenance from ingredient presence. The response distinguishes known versus unknown concentration. Ingredient list completeness (`partial`/`complete`) itself references evidence. Complete describes only the reported ingredient list, never complete knowledge, verification, effectiveness or compatibility. Region/formulation unknowns remain visible even for a complete list.

Input limits: 30 sources, 300 ingredients, 500 characters per fact/reference, unique source IDs and ingredient positions. Duplicate ingredient identities (including exact aliases) are rejected. Extra fields, missing source references, impossible verification states and future/naive verification times return 422 before mutation. Ingestion replaces the evidence document atomically; database failure rolls back and returns 503.

## Normalization scope

Exact case-insensitive aliases with whitespace normalization, not substring matching or NLP:

| Key | Aliases beyond canonical name | Class |
| --- | --- | --- |
| niacinamide | nicotinamide | none |
| retinol | none | retinoid |
| retinal | retinaldehyde | retinoid |
| tretinoin | retinoic acid, all-trans retinoic acid | retinoid |
| adapalene | none | retinoid |
| glycolic_acid | none | exfoliant |
| lactic_acid | none | exfoliant |
| mandelic_acid | none | exfoliant |
| salicylic_acid | none | exfoliant |
| azelaic_acid | none | none |
| benzoyl_peroxide | none | none |
| ascorbic_acid | l-ascorbic acid | none |

Distinct molecules remain distinct. Generic `vitamin C`, `AHA`, `BHA`, `retinoid`, derivative names and `Retinol 2%` do not become specific active facts. Unrecognized ingredients retain their exact normalized text key for positive presence/disclosure matching. `parfum`, `perfume`, `fragrance`, `عطر` share the non-active `fragrance` key. This is a small explicit vocabulary, not a comprehensive allergy or ingredient ontology. Ingredient class describes membership only, not the role or potency in a particular formulation; class warnings explicitly disclose formulation uncertainty.

## Provenance and confidence

Source types: `manufacturer_label`, `curated_internal`, `user_reported`, `barcode_provider`, `unknown`. Sources include an operator-supplied reference, verification (`verified`, `unverified`, `unknown`), confidence (`high`, `medium`, `low`, `unknown`) and optional `last_verified_at`. Verified evidence requires a timezone-aware, non-future verification time. Other evidence cannot claim a verification timestamp. User-reported/unknown sources cannot assert verified or medium/high confidence. Verification means an authorized operator reviewed the supporting source; it is not clinical validation. The backend does not fetch URLs or certify source authenticity automatically.

Existing product name/brand/category/type/active ingredient fields are exposed as low-confidence, unverified `user_reported` facts if no evidence document exists. They are never silently upgraded. Saved actives form a partial list; they cannot imply that the full ingredient list is known. Once an evidence document exists, it is the intelligence read source; original user fields remain accessible in the existing product API. Changes to user fields never mutate independently sourced facts. Operators must review stale/changed labels and replace documents; no automatic refresh or arbitrary TTL is asserted.

## API and trusted entry

* `GET /api/v1/products/{product_id}/intelligence`: authenticated owner only; 404 for absent/foreign products. Includes single-product caution/disclosure warnings and sourced facts.
* `GET /api/v1/routine/intelligence`: authenticated owner; facts and deterministic warnings for current active routine entries whose product is owned and active. Product markers do not define membership. Repeated AM/PM entries deduplicate the product. Stopped/deactivated entries and inactive/archived products are excluded. No routine products yields incomplete data, never reassurance.
* `PUT /api/v1/admin/product-intelligence/{product_id}`: authenticated database role `admin` only, including when ingesting for another owner. Doctor/patient/support and token role claims cannot grant this permission. The existing authenticated user dependency reads the role from the database and checks session validity. Lock the owner during ingestion to serialize product/account lifecycle writes. No admin provisioning endpoint or public catalog write is added.

Example reviewed document (illustrative payload only; no seeded product truth):

```json
{
  "sources": [{"id":"label","type":"manufacturer_label","reference":"Reviewed package label and variant identifier","verification":"verified","confidence":"high","last_verified_at":"2026-01-01T00:00:00Z"}],
  "region": {"value":"EG","source_id":"label"},
  "ingredients": {"source_id":"label","completeness":"partial","items":[{"name":"Niacinamide","source_id":"label","position":null,"strength":null}]}
}
```

Existing product create/edit remains the user-report submission path. No barcode integration exists in these product flows, and none is invented. `barcode_provider` is a provenance type available for future reviewed ingestion, not a live lookup. The former free-text `/products/check-interactions` endpoint is authenticated and returns 410, directing callers to product/routine intelligence. Its automatic creation-time audit check is removed. It cannot return an unsupported safe verdict or treatment advice.

## Rules and warning semantics

Structured warnings include key, `info`/`caution` severity, explanation, product/ingredient/source evidence references, confidence, data completeness, limitations, optional rule source and exact disclosure reference. Warning confidence is the lowest ingredient-presence source confidence involved, not a calibrated probability of reaction. Strength facts are exposed separately; these rules never use strength to estimate risk. Rule output is not persisted.

1. `duplicate_active` (info): the same supported active is reported by two distinct current routine products.
2. `duplicate_retinoid_class` / `duplicate_exfoliant_class` (caution): different supported actives in the same class occur across distinct products. This describes multiple exposures, not incompatibility.
3. `retinoid_exfoliant_caution` (caution): a supported retinoid plus supported exfoliant appears in current routine products, including a single formulated product. Wording is limited to possible irritation; actual co-application, concentration and formulation effects are unknown. This conservative class-level interpretation is grounded in [AAD guidance on exfoliation](https://www.aad.org/public/everyday-care/skin-care-secrets/routine/safely-exfoliate-at-home), which discusses increased sensitivity/peeling with retinoid/retinol products and irritation with exfoliation. It does not assert chemical deactivation, prescribe a schedule or recommend treatment.
4. `disclosed_sensitivity_match` (caution): structurally known ingredient matches an explicit Profile v2 `sensitivities_allergies` entry after exact alias normalization. Evidence includes the disclosed term. This does not diagnose an allergy or predict a reaction.

No inference from skin type, concerns, medications, hormonal context or undisclosed conditions. No substring extraction from prose disclosures. No negative allergy assertion from absent matches. Positive matches may be emitted from partial/unverified evidence and retain that confidence; incomplete lists never generate reassurance. Unknown lists yield explicit incomplete/unknown notices and no unsupported warnings. Empty warning arrays never mean safe; every response supplies limitations. No prescription, product ranking, purchase recommendation, emergency semantics or LLM reasoning.

## Flutter and experiments

Saved product details show loading, unknown, sourced facts, warnings, partial data and failure/retry. The client reads product intelligence plus routine intelligence, selecting only server warnings with evidence referencing the displayed product. It computes no ingredient identities, strengths, interactions or risk verdicts. Pre-save UI labels entered details as user reports. No local safety fallback remains in that flow. Session changes reload the panel; authenticated API responses are rejected if the session changed while they were in flight. Users can refresh after profile/routine changes.

Experiments keep their existing definition/evaluation semantics. The owned product ID provides access to current facts/provenance via the intelligence read endpoint; this does not claim that current facts were frozen at experiment activation. Historical intelligence snapshots and interpretation in experiment evaluation are intentionally deferred. Personal Skin Model, Contextual AI and Doctor Loop can consume this authoritative evidence later; no deep integration or doctor permission change is included. Safety Engine remains a separate milestone.

## Deletion and production migration

All documents are owner-specific, including reviewed labels. Account deletion removes evidence before products/users, with external blob cleanup and existing rollback behavior preserved. Product deletion cascades its document; product history protections remain. There is no shared knowledge entity and no residual user-specific evidence after deletion. Cross-account inconsistent evidence linkage blocks deletion rather than modifying another owner.

Manual migrations: `docs/migrations/product-intelligence-v1-postgresql.sql` and `product-intelligence-v1-sqlite.sql`. They create one table, unique product reference, owner index and product deletion cascade, with no backfill or fake catalog. Existing product schema is unchanged. Back up the database, apply the appropriate SQL once transactionally before deploying backend, verify table/index/FKs, then deploy backend before Flutter. SQLite connections must enable foreign keys. PostgreSQL JSON matches the SQLAlchemy JSON column. Runtime `create_all` is not a substitute for reviewed production migration. PostgreSQL execution and production deployment/smoke are external release steps; local tests exercise SQLite migration, constraints and cascade. Rollback after data exists requires retaining/exporting owner evidence securely or accepting its removal before dropping the new table; do not discard evidence casually.

## Intentional limits and next milestones

No global catalog, scraper, live provider, source URL fetching, shopping, diagnosis, recommendations, schedule prescriptions, broad interaction matrix, full INCI ontology or regulatory claims. Verification is a trusted manual review process. No UI for admin curation, automated source changes, historical intelligence revisions or independent medical validation. Safety Engine, Contextual AI, Personal Skin Model v2 and Doctor Loop are future consumers; they do not start in this milestone. No storage infrastructure, notifications or animation work.
