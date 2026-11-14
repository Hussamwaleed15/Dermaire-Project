# M4 external dependencies —14 November2026

No Backend issue/message, provider activation, live service mutation or deployment performed.

## Hussam + Amr: approved per-case baseline/timing contract

Master Plan§7.4/§9.4 requires case-specific plan authority and rejects universal baseline/follow-up schedules. Current source backend/app/services/experiments.py activation sets baseline_start=row.start_date-timedelta(days=28), then freezes actual records. ExperimentCreate has no plan identity/authorized baseline window; target_days is editable7–90, default28, a different concept from baseline selection.

Needed coordinated decision/contract, not a guessed new endpoint: explicit authorized plan/revision and original clinician grant where applicable; approved baseline start/end or stable authorized baseline record selection; exact eligibility/source/method/quality; immutable frozen cohort/product/routine identity; server-validated ownership/consent/current authority; revision/precondition and payload-bound idempotency for activation; original attempt reconciliation after response loss. Historical definitions/receipts must never be retroactively rewritten. Unknown or unavailable evidence cannot be replaced by client-selected dates or unrelated nearby records. Timing cannot be a client-only field or inferred from product use.

Amr/clinical owner defines allowed intended use and timing authority; Hussam owns API/engine/migrations. Flutter can consume the returned saved window and explicitly disclose legacy engine scope now. It cannot safely implement the missing policy alone. Existing experiments remain nonclinical user-configured tracking, not clinician treatment changes. No backend change is requested to be executed by this Flutter task.

## Hussam: qualify current endpoints and optional metric metadata in isolated integration

Current implementation uses existing products/routine/adherence/experiments endpoints, original keyed receipts, If-Match/revisions and frozen snapshots. Confirm deployed MetricContract(schema1) fields:
metric hydration/texture/redness; unit score_0_to_100; delta_unit score_points; source manual/image_proxy; direction per metric; aggregation within_UTC_day_mean_then_equal_day_mean; evaluation_algorithm experiment_v2_rules_1; measurement_algorithm_versions/provenance recorded/missing/mixed; clinical_measurement false. Cross-field consistency and finite values required. These are legacy tracking-score units, not fractional capture proxies or validated clinical measures. Absent legacy contract remains explicit, malformed supplied contract is not treated as known units.

Saved adherence expected/reported/followed slots and fractions must be internally consistent, user_reported and expected_status completed/skipped. Missing reports remain unknown. Original configuration snapshots/product IDs and context Boolean/count types retained; absent context remains unknown. Confirm auth401/403, account isolation, missing products, revision conflict, lost-response receipt lookup and newer-current-versus-original semantics in authorized synthetic nonproduction integration. No production calls made here.

## Clinical/model owner

Current deterministic evaluation is observational evidence. Do not claim treatment effectiveness, causation, clinical image comparison, medical accuracy, complete ingredient safety or confidence probabilities. Actual clinical/model qualification is required for those intended-use changes; no new provider, model or medical tool authorized.

## Amr / Salma: independent device/QA qualification

Review new source/evidence distinctions and actual Android/iOS background/resume/account-switch/navigation, slow/failed reads and pending writes. Ensure server-bound original pending identity survives, no POST replay or fake completion, and stale controls remain disabled. Verify320px/large text/screen-reader/reduced-motion on devices. Salma owns independent QA; formal product closure pending. Host tests and disposable branch assemblies do not qualify clinical, live or production behavior.
