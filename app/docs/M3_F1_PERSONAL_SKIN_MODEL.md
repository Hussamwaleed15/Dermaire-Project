# M3-F1 — Personal Skin Model & Evidence Experience

2026-10-13. Source: clean main `a06eedcd80d2dd6dafaac2879951cb890e36cc53`,
matching local origin/main and a fresh GitHub main read. Read app/AGENTS.md,
relevant architecture/agent audit and roadmap, M2-F3 documentation, current
Flutter API/session/clinical/observation/capture/experiment/shell code and the
actual PSM schema/base service/v2 enrichment/backend tests before editing.
Flutter only. No future AI model, agent, scheduling, comparison or provider enabled.

## Actual PSM contract inspected

GET /api/v1/personal-skin-model, api/v1/personal_skin_model.py,
schemas/personal_skin_model.py, services/personal_skin_model.py and
personal_skin_model_v2.py; tests/test_personal_skin_model.py and v2 tests.
Related current measurements/checkins/baseline/home/safety/doctor/experiments
contracts and current Flutter components were reviewed read-only.

Authentication is get_current_user. Queries filter the signed-in owner's records;
there is no client owner selector and no response patient_id/user_id. The patient
client additionally requires current confirmed safety acceptance and patient role.
Normal deleted/expired session is 401; GET does not mutate records or invoke AI.
Read-time projection is not a persisted model, diagnosis or live production audit.

Core wire fields: schema_version 2; contract_version personal-skin-model-2.0;
derivation_version psm-v2.0; generated_at timezone-aware server instant; status
no_data/insufficient_data/no_meaningful_change/meaningful_change/stale; statement;
strength none/limited/moderate; changing/stable/associations; sufficiency; profile;
products; limitations. Additive v2 sources, summaries, unknowns, optional safety
and assistant_layer. Current assistant layer is ai_inferred, authoritative=false,
included=false; incompatible explicit values are rejected, not presented as PSM.

Finding: code/subject/direction/statement/strength/rule, evidence source/id/fields/
recorded_at/kind/category, evidence_count/latest_evidence_at/confidence/caveats;
nullable reference_value/recent_value/threshold. Strength/confidence are ordinal
rule labels, not probabilities. Evidence sources checkin/daily_context/profile/
product/adherence; kinds user_reported/image_proxy/server_recorded. Category is
patient_reported for user reports, system_observed otherwise. Numeric Finding
reference values have no unit in this schema; the client does not display them as
calibrated measurements or construct improvement percentages.

Sufficiency: confirmed_days (eligible record days, including structured reports),
report_days, legacy measurement_days, excluded_checkins, latest evidence/age/
recency, baseline_ready/reasons; proxy_measurement_days and latest proxy time.
These are distinct streams. Report-only observations and Capture proxies do not
advance the first-five-legacy-score baseline or prove medical clearance.

Base rules exclude future/simulated/unproven rows, take distinct report days in
28 days, and use engineering thresholds for same-source legacy tracking findings.
Reports express symptom presence, not severity; reported associations do not
establish cause. Enrichment independently includes routine, deterministic frozen
experiment evaluation, image-property estimates, profile, safety and visible doctor
context. Sensitive hormonal/cycle/profile snapshots are omitted server-side.

## Typed supported mapping

psm_models.dart maps the actual core contract and selected useful source sections:

| Response section | Client presentation / boundary |
| --- | --- |
| profile + sources.profile | Verified current-account user-reported goals/evidence, optional skin type/concerns/freshness. Profile evidence identity must match current owner. No inferred diagnosis/disclosure requirements. |
| findings/evidence | Deterministic statements, rule/version, source kind/ID/fields/time, provided count and ordinal labels, caveats. Empty/unverified evidence or unknown enums become an explicit unsupported section. |
| sources.history.recent_reports | Actual ID/time, user-reported change, symptoms, nullable routine report and source freshness. No free-text/photo interpretation or guessed Capture linkage. |
| sources.measurements.latest | Known measurement-1.0 image proxies, source/capture/method/time/status and exact fraction_0_to_1 values/limitations; quality/reference/metric provenance validated with existing M2 classes. |
| sources.measurements.latest_measured | Separately labeled historical last measured reference with returned capture receipt/computation times and freshness. Status is validated from returned measured metric fields; no invented root provenance. A prior success never replaces the latest failed/unavailable record. |
| sources.measurements.trend_status | Server status displayed only; no local delta, clinical trend chart or before/after interpretation. Current quality usually blocks comparable status. |
| sources.experiments | Actual definition/status/intervention/date/target and returned deterministic evaluation identity/label/statement/strength/count/freshness/caveats. Stale frozen evaluations remain explicitly historical. No inference of treatment effectiveness or v2 image assessment. |
| safety | Typed separate Safety Engine snapshot, including urgent/unsupported/incomplete warning and evaluation time. Never converted into a model conclusion. |
| sources.doctor.current_decision | Typed labeled clinician-authored PSM snapshot, record/state/recommendation/rationale/time/freshness. Unknown values labeled; a null current decision never falls back to older visible history/notes. Current authoritative clinician GET is displayed independently. |
| unknowns/limitations/sufficiency reasons | Returned missing-data/evidence limits. No fabricated answers or zero substitute. |

IntegratedSources and summaries are dict-based backend fields, not fully versioned
nested schemas. Unneeded raw product-intelligence, routine configuration/history,
private/extra snapshots and duplicated summaries are not retained/rendered as
untyped JSON. No claim that every PSM source dictionary is a full patient explorer.
Existing supported destinations let the patient revisit observation, private image
and clinician records. Primary source arrays are bounded at 500 in the mapper;
oversized/unsupported optional arrays are unavailable rather than silently clipped
and called complete. The existing API transport still buffers metadata responses;
no streaming/pagination or process-memory performance guarantee is claimed here.

Core unknown version/status/time/essential sufficiency fails closed as unsupported
model, not successful no_data. Unsupported optional sources/findings become explicit
partial issues while other verified sections remain usable. If supporting findings
are unsupported, the aggregate model statement is withheld. Unsupported image
versions/units/source IDs/status/value/quality suppress values without erasing valid
report evidence. Optional absent fields remain missing; no defaults imply health.
Typed lists/maps are immutable, and no raw source dictionaries enter application state.

## API / session architecture

ApiService adds readPersonalSkinModel(generation): one protected GET with header
Bearer auth, no owner query/public URL, redirects disabled, 20-second caller timeout
and existing _SessionClient generation/token/current401 behavior. It verifies current
patient+server consent before/after the response, then binds DTO owner to this
request's session. No PSM data is added to chat/assistance/context automatically.
Legacy capture/Tester methods and existing other API methods are unchanged.

RemotePsmRepository and route-local PsmController use existing ChangeNotifier.
Controller gates owner, generation, request revision and disposal; newest refresh
wins and late/old401/reused-token responses cannot update B. Logout/expiry/current401/
account switch/server-revoked profile consent clear model and remembered safety.
No SharedPreferences, health persistence, image download/cache, sensitive log or
analytics introduced. Refresh removes old model; failed read is not empty success.
Previously received PSM safety is retained only within the same active session and
clearly labeled unconfirmed while refresh fails/loads or a later read lacks safety.
It never overwrites the canonical clinical controller. No stale model fallback.

## UI and navigation

Existing ReportsTab uses the existing ExperimentsView.header slot for a guarded
“Understand your skin evidence” card and real Open Personal Skin Model button.
No auto PSM GET at shell render, new bottom tab, Home redesign or duplicate dashboard.

PersonalSkinModelScreen: labeled PSM safety first, independent verified
ClinicalHomePanel, explicit refresh/loading/error, model overview, current-account
reported profile, source coverage, expandable findings/evidence, report rows,
current/historical image estimates, experiment evidence and missing-information
limits. Independent urgent guidance remains visible despite reassuring model status
or a lower clinician snapshot. Sources/age/version never collapse into generic AI.

Uses approved semantic Light/Dark/card typography, reduced-motion EntryReveal and
ExpansionTile alternatives, live-region loading/error/safety, wrapping at 320px/
200% text and native accessible keyboard controls. No fake progress percentage.
Real actions: Record observation (including existing report history), View private
image history, Safety & clinician guidance. Return re-reads PSM via GET, without
optimistic changes to model/Home/check-in/baseline or automatic POST retry.
English only; optional disclosures stay optional. No medical recommendation is
created from the navigation choices.

## Verification and exact completion

Final flutter analyze: **No issues found**.
Final full flutter test: **919 passed = 829 preserved + 90 new**.
Synthetic real-shaped v2 metadata/images/accounts and fake transports only;
invalid-host assertions and existing global Production HTTP denial preserved.

Coverage: valid mapping/versions/UTC/source/kind/category/evidence, nullable/default
fields, partial/malformed/unknown sections, record coverage vs proxies, method/
units/nonclinical values, historical/latest failure distinction, no old clinician
fallback, incompatible AI layer, no implicit assistant call, authenticated GET/no
redirect, empty/insufficient/stale states, 403/404/5xx/offline/timeout/retry, current/
old401/reused tokens, late/concurrent/foreign-owner reads, logout/switch/revocation/
idle expiry, urgent/unsupported safety and lower clinician priority, Light/Dark/
reduced/320px/200%, semantic evidence/keyboard retry, Reports entry and every real
next-action destination with GET refresh on return.

**M3-F1 supported PSM/Evidence experience COMPLETE** after verified commit/push.
No future AI image analysis, autonomous agent, persisted comparison/follow-up or
model action capability was enabled. No local scoring/chart/diagnosis/product-effect
inference, old Home delta repurposing or Capture↔observation association.

Known limits: current PSM is a non-atomic read-time projection; source-specific
freshness differs from generated_at; evidence references identify mutable records
without revision/as-of guarantee; dictionaries may contain unsupported source
formats; aggregate arrays lack pagination; client supports current measurement/
quality versions and selected source fields. See M3_F1_HUSSAM_HANDOFF.md.
External testing team owns physical Android/emulator acceptance and device
performance QA; these were not performed. No production/staging/OAuth call, Azure
resource, provider/config/backend/DB/Tester change or production build/deploy.
M3-F2 was not started.
