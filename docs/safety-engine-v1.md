# Safety Engine v1

Deterministic backend-authoritative overlay; `engine_version: safety-1.0`.
Not a diagnosis, clinician replacement, causal analysis, validated triage instrument or
regulatory compliance claim. No external AI, LLM or Vision is needed for evaluation.

## Contract and schema
Authenticated GET /api/v1/safety has no body or owner parameter; JWT user owns all queried evidence.
200: status (track/low_risk_self_care/doctor_review/urgent), engine_version, UTC evaluated_at,
reasons [{code,state,summary,evidence}], evidence_status, guidance, limitations. Unauthorized
or deleted users: 401. Reasons preserve record/source IDs, timestamps, structured reports or
ingredient/source provenance and profile disclosure. Sorted by severity, code, evidence;
multiple reasons may have the same code with different evidence.

Computed on read. No writes, safety history, tables, columns, migration or backfill. Existing
account deletion removes source evidence; no persisted safety conclusion survives deletion.

POST /api/v1/checkins retains multipart `report` containing JSON. New optional report.safety:
- severity, pain: none/mild/moderate/severe or null.
- Eight strict bool/null flags: breathing_difficulty, facial_or_mouth_swelling,
  eye_or_mucosal_involvement, fever_or_systemic_illness, rapid_spread,
  extensive_blistering_or_peeling, pus_or_hot_swollen_skin,
  new_medication_or_product_reaction.
Unknown fields/types return 422 before any mutation. Existing reports still validate.
Absent flags are UNKNOWN, never default false. Clients must ask before submitting false.
Example: {"overall_change":"same","symptoms":["dryness"],"safety":{"severity":"mild","pain":"none"}}
This example is incomplete and conservatively requires review. Low-risk requires all eight
flags explicitly answered, severity/pain answered and the conditions below.

## Rule/state matrix
Highest severity always wins: urgent > doctor_review > low_risk_self_care > track.
Current window: last 72 hours inclusive UTC. History: last 14 days inclusive UTC.
Every positive current signal survives later reassuring reports. Historical concerns beyond
72h require an updated clinician assessment, rather than declaring an active emergency.
Older-than-14-day reports cannot establish current safety. Time windows and longitudinal
thresholds are product heuristics, not validated clinical thresholds.

| State | Deterministic trigger | Reason codes |
|---|---|---|
| urgent | Current breathing difficulty, face/mouth swelling, eye/mucosal involvement, rapid spread or extensive blistering/peeling | Same as the flag names |
| urgent | Severe severity OR pain | severe_symptoms |
| urgent | Fever/systemic illness plus symptoms, mild+ severity/pain, or pus/hot swollen skin in SAME report | systemic_with_skin_concern |
| doctor_review | Pus/hot swollen skin or newly reported medication/product reaction | Same as flag names |
| doctor_review | Moderate severity/pain or worse overall change | concerning_current_report |
| doctor_review | Legacy worsening/burning/sensitivity without safety screen | uncertain_current_concern |
| doctor_review | ANY current symptomatic report lacks a complete screen | incomplete_symptom_assessment |
| doctor_review | Symptoms >=3 distinct history days spanning >=7 days OR burning/sensitivity >=3 distinct history days, plus current report | persistent_or_repeated_irritation |
| doctor_review | History outside current window contains worse, positive flag, moderate/severe pain/severity | historical_concern_needs_update |
| doctor_review | Ingredient matches explicit sensitivity in active owned routine | explicit_sensitivity_match |
| doctor_review | Latest owned v2 outcome per experiment in history, limited/moderate evidence, no_meaningful_change or likely_associated_worsening, plus latest current report has symptoms | experiment_concern_not_improved |
| low_risk_self_care | Latest current report symptomatic, mild severity, none/mild pain, same/better change, complete screen, no higher concern, PI warnings or incomplete ingredient lists | mild_report_no_disclosed_red_flags |
| track | Incomplete active ingredient facts (blocks low-risk) | unknown_product_facts |
| track | Other Product Intelligence warnings (block low-risk; no diagnosis) | product_duplicate_active, product_duplicate_retinoid_class, product_duplicate_exfoliant_class, product_retinoid_exfoliant_caution |
| track | Remaining no-concern monitoring / insufficient-but-not-concerning evidence | monitoring_or_insufficient_evidence |

Track and low-risk do not establish that any product or care is safe. No warning is not
compatibility. A sensitivity match requires clinician advice without claiming exposure or
allergic reaction. A new reaction report requires review; severe/red flags override it.
Emergency guidance asks for urgent assessment, with local emergency services for breathing
difficulty or face/mouth/throat swelling; no location or emergency number is inferred.

## Authoritative evidence boundaries
Only schema-v1 check-ins with user_reported/server_recorded provenance qualify. Future,
simulated/mock/fake records are quarantined. Never parse notes, images or model prose.
Profile: explicit sensitivities only, no undisclosed trait inference.
Routine/PI: existing active RoutineEntry + owner-scoped active Product membership; legacy
in_routine, inactive products and inactive entries are excluded by existing PI service.
Experiment: read stored v2 evaluations, scoped to owned v2 definitions. GET never runs/saves
the experiment evaluator. Insufficient/confounded/improved results cannot clear safety concerns.
Guided Capture/Measurements: unavailable FOR medical triage, including accepted/measured
images; quality/comparability do not clinically validate red flags. Owner-scoped IDs are
included for traceability. Baseline scores never grant medical clearance. Daily Context and
active-entry adherence IDs are context only: no causal, sensitive-trait, or failed-care inference.
Persistent reports and supported experiment outcomes ground escalation longitudinally.

Existing /api/v1/chat evaluates safety before calling its model. Doctor Review/Urgent return
server guidance directly with authoritative_safety in safety_details and skip external AI.
Other states attach canonical safety to details while preserving existing chat guardrails.
No model output can downgrade the four-state result. Flutter already displays server chat
responses, so it is untouched. Its legacy local helper is not canonical four-state safety.
Dedicated questionnaire/status presentation is deferred; API clients can submit fields now.

## Medical references and limitations
AAD Rash 101: https://www.aad.org/public/everyday-care/itchy-skin/rash/rash-101
NHS Anaphylaxis: https://www.nhs.uk/conditions/anaphylaxis/
These support escalation for reported signals, not validation of exact engine thresholds,
grouping or accuracy. Broad urgent classification includes prompt medical assessment and
is not always an ambulance emergency. Clinician review of rules/wording remains advisable.
Self-report accuracy, missing symptoms and this finite screen limit coverage. No visual
diagnosis, medication-specific contraindications, prescription/treatment recommendations,
doctor override or disagreement persistence. No regulatory compliance claim.

## Production rollout (not performed)
1. Review rules and wording; verify deployment dependency versions against the tested environment.
2. After explicit authorization, deploy with existing Azure backend process. No migration.
3. Verify health, authenticated safety, all four states, mixed-signal precedence, uncertainty,
   explicit sensitivities and chat bypass using disposable accounts.
4. Delete accounts, verify old tokens rejected; inspect cleanup if authorized.
5. Coordinate future minimal server-backed questionnaire; older reports remain unknown.
Rollback to a0af3b0 if needed. Additive stored JSON remains compatible, but old request
validators reject incoming safety fields; clients must stop sending them on rollback.

Stop after this milestone: no production deployment, Contextual AI, Doctor Loop v2,
Personal Skin Model v2, Blob work or UI polish.

## Validation record
Final full backend suite: 377 passed (41 Safety Engine cases), 64 existing Starlette
HTTP-422 deprecation warnings. Python 3.12 isolated environment installed from the existing
requirements; no dependency manifest changes. Flutter untouched, tests/analyze not run.
git diff --check passed; no production smoke/deployment performed.
