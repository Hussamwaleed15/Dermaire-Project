# Personal Skin Model v2

## Architecture and scope

PSM remains a deterministic, owner-scoped compute-on-read projection behind authenticated
`GET /api/v1/personal-skin-model`. There is no persistence, new table, migration, provider
request or external LLM dependency. Existing v1 personal-baseline, report and context rules
remain; a separate v2 adapter composes the current authoritative systems. Lazy adapter
loading avoids circular imports: Safety consumes PSM report helpers; Contextual AI and
Doctor Loop consume PSM, but PSM does not invoke their context/timeline builders.

Only this milestone is implemented. No production deployment or Git mutation is performed.
Flutter is unchanged: the current app has no PSM endpoint consumer/version parser.

## Exact contract changes

Top-level fields retained with their existing names and meanings:
`generated_at`, `status`, `statement`, `strength`, `changing`, `stable`, `associations`,
`sufficiency`, `profile`, `products`, `limitations`.

- `schema_version`: integer 1 -> 2.
- `derivation_version`: `psm-v1.0` -> `psm-v2.0`.
- Added `contract_version`: `personal-skin-model-2.0`.
- Each Finding adds `category=deterministic_derived`, `evidence_count`,
  `latest_evidence_at`, `confidence`, `caveats`. Confidence equals its existing rule-based
  strength (`none|limited|moderate`), never a probability. Evidence count is distinct
  `(source,id)` references, not independent subjects or necessarily days.
- Evidence retains `source,id,fields,recorded_at,kind`, adds `category` mapped from
  `kind`: user_reported -> patient_reported; image_proxy/server_recorded -> system_observed.
  `adherence` is an additional permitted evidence source.
- Sufficiency adds `proxy_measurement_days` (distinct accepted capture receipt days with a
  measured Measurement Engine record), `latest_proxy_measurement_at` (computation time).
  Existing counts/age/recency retain their v1 tracking-channel scope; per-source freshness
  is required when inspecting newly integrated sources.
- Added top-level `safety`: the full existing SafetyEvaluation contract. Every successful
  endpoint response populates it. Its reasons, guidance, version and evidence are unchanged.
- Added `sources`, with fixed keys documented below. Nested projections deliberately reuse
  existing source contracts and explicit whitelists instead of retyping every engine document.
- Added `summaries` and `unknowns` as documented below.
- Added `assistant_layer`: exactly `{category: ai_inferred, authoritative: false,
  included: false}`. Existing Contextual AI remains accessible through its own endpoint.
  No AI response is read or persisted in canonical PSM.

Status enum remains `no_data|insufficient_data|no_meaningful_change|meaningful_change|stale`.
Routine/product presence alone does not establish a skin observation. A measured proxy-only
history can now produce insufficient_data, or stale when historical, rather than no_data;
no overall skin trend is inferred solely from one proxy measurement. Existing v1 trajectory
findings retain their rules. Measurement-engine trend status is reported separately.

All returned datetime objects are normalized to UTC. Freshness objects have
`latest_at` (UTC datetime or null), `age_days` (integer or null), `state`
(`missing|fresh|stale`). More than 14 elapsed days is stale. Recency is record age, not
clinical validity; product source verification timestamps remain available in provenance.
Capture receipt determines proxy recency; later computation cannot refresh an old capture.
Capture receipt does not verify when the original photo was taken.

## Integrated source matrix and field inventory

| Source key | Inputs and returned fields | Authority / treatment |
|---|---|---|
| profile | skin_type, skin_concerns, freshness; retained profile.primary_goals and evidence | patient_reported. Sensitive demographic/hormonal/medication/cycle fields omitted. No inference. Explicit sensitivity disclosure feeds existing PI/Safety only. |
| history | freshness, recent_reports: id, recorded_at, report {overall_change,symptoms,routine_status}, freshness | patient_reported, validated report provenance. Last 28 days, one report per UTC day. Simulated/fake/mock/future evidence excluded. |
| baseline | snapshot from existing engine {status,required_days,completed_days,checkin_ids,metrics,today_checked_in}, caveats | deterministic_derived. Personal first-five-day reference. No clinical clearance; mixed-source conclusions blocked. |
| daily_context | days {id,date,unusual_conditions,freshness}, caveats | patient_reported. Owner/date join; mutable snapshots, not edit history. Cycle context omitted. Future updated rows excluded. |
| routine | configured {id,product_id,schedule,frequency,start_date,freshness}, adherence, historical_snapshots | patient_reported configuration/application; adherence aggregate is deterministic_derived. Active entries require active owned products and start_date <= today. |
| experiments | id,category,status,change_type,product_id,start_date,target_days,stopped_at,baseline_window,evaluation | v2 only. Configured definition patient_reported; immutable engine evaluation deterministic_derived. Legacy experiments excluded. |
| measurements | category,latest,freshness,trend_status,latest_measured | deterministic_derived proxies; accepted owned captures only. Algorithm, quality and metrics preserved. Comparison recomputed with the existing engine. |
| product_intelligence | existing routine_intelligence output plus category and product freshness; ingredient category | normalized facts deterministic_derived; ingredient evidence patient_reported or system_observed according to original source. Source/confidence/verification/known concentration retained. |
| safety | full SafetyEvaluation plus category in sources (also typed top-level safety) | deterministic_derived, authoritative Safety Engine. Does not accept AI/clinician downgrade. |
| doctor | category,state,freshness,current_decision,history,notes,safety_precedence | clinician_authored decisions/notes. Latest sequence controls state; patient visibility strictly applied to decisions and notes. |

Routine `adherence` fields: `window_days=14`, `expected_known_slots`, `reported_slots`,
`completed_slots`, `unknown_slots`, `completed_fraction`, `category`, `source`,
`freshness`, `caveats`. Current day is incomplete and excluded. Only days after the latest
entry edit, within start date and the last 14 days, have a known denominator. AM/PM/BOTH
and matching product/schedule/frequency/active snapshots determine eligible slots.
Missing slots stay unknown, even though the completed fraction uses the known denominator.
Zero known denominator produces null fraction. This is reporting consistency, not verified use.

Historical adherence retains `category,id,entry_id,date,slot,status,recorded_at` and
`configuration {id,product_id,schedule,frequency,active,start_date,end_date}`.
Deactivation/archive excludes current participation, not historical adherence. Top-level
legacy `products` remains an inventory/status list, including inactive inventory; active
routine participation is defined only by sources.routine / sources.product_intelligence.

Experiment evaluation fields: `id,category,label,strength,confidence,comparison,adherence,
confounders,evaluation_window,evidence_count,freshness,statement,caveats`.
Comparison exposes `start,end_exclusive,strategy,baseline_days,experiment_days,measurement_source`.
Evidence count is baseline_days + experiment_days if both are valid nonnegative integers;
otherwise null. Adherence exposes `expected_status,expected_slots,reported_slots,
followed_slots,coverage,followed_fraction`. Confounders expose `unusual_days,
baseline_unusual_conditions,routine_changed_after_activation,product_changed_after_activation,
baseline_inconsistent_routine_reports,inconsistent_routine_reports`.
Evaluation window exposes start and elapsed_days. Raw definition/evaluation provenance,
profile snapshots, notes, cycle counters and arbitrary prose are never copied to PSM.
Missing evaluation remains null. Stored evaluations are not silently rerun on GET.

`measurements.latest` reuses Measurement response fields `id,capture_id,algorithm_version,
status,measured_at,metrics,capture_quality,comparison,provenance`. Comparison is freshly
validated against the nearest earlier measured capture of the same algorithm/owner.
It is deliberately conservative and does not search past an incompatible predecessor.
`trend_status` is unknown (no attempts), not_comparable, comparable, or stale.
`latest_measured` is null or {id,capture_id,algorithm_version,metrics,quality_reference,
received_at,measured_at,freshness}; it remains visible if a newer attempt failed.
Persisted foreign comparison IDs or unsupported deltas are never emitted.

Doctor decisions expose `id,category,state,recommendation,rationale,recorded_at,freshness,
diverges_from_current_safety,lower_than_current_safety`. Notes expose
`id,category,content,priority,follow_up,recorded_at,freshness` only when patient_visible.
State may remain visible when the latest decision is internal; current_decision is then
null. An older visible decision is historical and never promoted to current. With no review,
state is pending when a current active/pending access grant exists, otherwise not_requested.
Access tokens, raw grants, safety snapshots and private notes are not projected.

## Deterministic associations and summaries

- Existing personal tracking score rule: five same-source baseline days, at least three
  recent later days; threshold max(10, 2 baseline standard deviations), at least 2/3
  directional agreement. Inconsistent large changes yield unknown, not stability.
- Report rule: at least six distinct report days in 28 days, latest three within 14 days;
  symptom frequency shift >=2 of three, or agreement on latest three overall changes.
- Context association: three paired report days with explicit unusual_conditions=true and
  three with false, all in 14 days; worse-report frequency gap >=2/3. Null is not false.
- Added adherence association: three paired report days with exclusively completed reported
  active slots and three with exclusively skipped reported active slots, within 14 days;
  absolute worse-report frequency gap >=2/3. Mixed or unreported days excluded. Historical
  recorded configuration is used, not today's membership. Evidence includes report and log
  references. Strength/confidence remains limited; actual use and confounding are unknown.
- Product facts are relevant context/cautions, never proof of exposure or product effects.
  No unsupported product/measurement association is manufactured.
- Experiment association labels/strength are the existing engine's immutable outcome. PSM
  does not convert them into causal claims, recalculate them, or improve their confidence.
- Stale findings are not presented as current. Weak/no conclusion and continue tracking
  remain valid results. No diagnosis or population reference is added.

Summary keys: `current_skin_state`, `recent_changes`, `routine_consistency`,
`relevant_factors {products:[{id,data_completeness,unknowns}],warnings}`,
`experiment_learnings` (only fresh evaluations), `measurement_trend_status`,
`safety_status`, `safety_guidance`, `doctor_review_status`, `remaining_unknowns`.
The full sources retain historical/stale inputs with explicit freshness. Unknowns include
insufficiency reasons, unsupported exposure/causation, non-comparable measurement trends,
incomplete ingredients, unknown concentrations and stale profile/routine/measurement/review.

## Safety / doctor precedence

Safety Engine is returned intact and prominently at top level and in summaries. Clinician
recommendation is a separate fact with divergence flags. A clinician track recommendation
cannot hide urgent Safety. Positive structured red flags survive reassuring tracking findings
under existing Safety rules. Missing risk fields/ingredients are not interpreted as normal
or safe. Internal clinical notes and internal decision rationale never reach patient output.

## Compatibility, migration and limitations

No database migration, backfill, canonical cache, credential provisioning or AI persistence.
Existing field names and status enums retained. External consumers that insist on version=1
must accept v2 before rollout; no separate frozen v1 endpoint was added. No current Flutter
PSM consumer was found, so Flutter files and tests/analyze are not touched.

The existing engineering windows/rules are not clinically validated. Guided Capture v1's
unknown yaw/pitch/occlusion/lighting dimensions keep genuine current comparisons non-comparable;
valid future/test metadata can exercise the existing comparable branch without changing it.
Context/config/product rows are mutable; only stored adherence/experiment snapshots retain
history. PSM cannot reconstruct edits or verified exposure. Reads currently load owner history
without pagination; large histories may need a separately scoped bounded/paginated contract.
Multiple query reads use the existing session transaction; no new cross-source snapshot
isolation is introduced. Historical clinician-authored visible outputs remain history after
access revocation; access revocation controls clinician access, not deletion of authored notes.

Deferred: Blob infrastructure, live Vision, notifications, broad Flutter/UI work,
Imagine Cup final layer, new clinical/causal models, population ranking and production deployment.

## Validation and rollout

Focused tests cover integrated routine/adherence and snapshot retention; inactive/archived
products; ingredients/concentration unknowns and explicit sensitivities; profile omission;
all measurement availability states, algorithm/owner isolation, comparability, latest failure,
staleness and backfill recency; active/completed/stopped experiments; private snapshot
omission; evidence counts/recency/confidence/wording; conflicting reports; urgent Safety with
lower clinician decision; internal notes/decisions; AI/provider exclusion; future records;
no-data; foreign isolation; authenticated access and deletion/session invalidation.
An existing context association test now records its fixture timestamp within its supplied
historical evaluation clock, matching the new future-update exclusion.

Production rollout after explicit authorization:
1. Review and commit only the six files below; run backend CI on the committed revision.
2. Check any external v1 consumers for strict version assumptions; stage the backend build
   through the existing deployment process. There is no migration.
3. Smoke authenticated PSM for no-data and integrated-history users, foreign isolation,
   unknown measurements/products, urgent safety versus a lower clinician recommendation,
   hidden clinician content and deleted/revoked sessions. Use temporary accounts, remove
   them afterward, and never print credentials/tokens.
4. Confirm payload size/latency on representative histories, then explicitly authorize
   production rollout. After deployment repeat the focused smoke and cleanup.
5. Roll back application code to the prior validated backend release if necessary;
   there is no PSM v2 persisted state to migrate back.

Changed files (repository-relative, all under C:\Users\Hossam\Desktop\Dermaire-Project):
- backend/app/schemas/personal_skin_model.py
- backend/app/services/personal_skin_model.py
- backend/app/services/personal_skin_model_v2.py
- backend/tests/test_personal_skin_model.py
- backend/tests/test_personal_skin_model_v2.py
- docs/personal-skin-model-v2.md


Final validation: full backend suite **523 passed, 0 failures/errors**, in 69.94 seconds.
This includes **28 new v2 cases** and 25 existing PSM cases (53 PSM cases total).
There were 90 existing Starlette HTTP_422 deprecation warnings. Tests ran with a workspace
basetemp and disabled pytest cache to accommodate the sandbox; no product logic was changed
for those environment settings. `git diff --check` passed. Flutter tests/analyze were not
run because Flutter was not modified.

Repository status: branch main, HEAD b3b0777d7d128aa2218570b9103d8dd52c7a43da.
Three tracked files modified, three new files untracked; exactly the six files listed above.
No branch creation, staging, commit, push, production deployment or production smoke was done.

Ready-to-review Git commands (provided only; create an isolated branch before committing):

```powershell
Set-Location 'C:\Users\Hossam\Desktop\Dermaire-Project'
git switch -c codex/personal-skin-model-v2
git add -- backend/app/schemas/personal_skin_model.py backend/app/services/personal_skin_model.py backend/app/services/personal_skin_model_v2.py backend/tests/test_personal_skin_model.py backend/tests/test_personal_skin_model_v2.py docs/personal-skin-model-v2.md
git commit -m "feat: integrate authoritative longitudinal Personal Skin Model v2"
git push -u origin codex/personal-skin-model-v2
```

Stop point: Personal Skin Model v2 implementation and local verification only. Production
milestone completion remains pending an explicitly authorized rollout and smoke test.
