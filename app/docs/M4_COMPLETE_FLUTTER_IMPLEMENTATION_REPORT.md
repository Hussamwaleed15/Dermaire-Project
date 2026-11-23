# Product M4 — Routine, Products, Adherence & Experiments

14 November2026. Implementation evidence for Amr; Salma owns independent QA. Product M4 is distinct from Flutter F4, QA-M4 and historical F6-M M4. No clinical, production, release or milestone approval is asserted.

## A. Repository state

Fetched origin and checked fresh GitHub metadata before coding. Main/base `b995873f2b76e0c37a08f23fbf40322174aba6fe`.

| PR | State | Head | Base |
|---|---|---|---|
|6|Open|25b0e1f9e04861c98736894d1b31fb02933142cb|main@b995873f2b76e0c37a08f23fbf40322174aba6fe|
|7|Open|5d855b499f73866ba6894fe67f950e81ec1b6e51|PR6@25b0e1f9e04861c98736894d1b31fb02933142cb|
|8|Open|a14cd11185816e18befcb90943563346cec5573f|PR7@5d855b499f73866ba6894fe67f950e81ec1b6e51|
|9|Open Draft|83e00a019689b1ff55dc4dc959ab860f9b60c781|main@b995873f2b76e0c37a08f23fbf40322174aba6fe|
|10|Open Draft|32cd9f9e062b8b7bf915658af13015e5d685533f|PR9@83e00a019689b1ff55dc4dc959ab860f9b60c781|
|11|Open Draft|187a0a346766e013502e2aaf7788f5b227698cc9|main@b995873f2b76e0c37a08f23fbf40322174aba6fe|
|12|Open Draft|10507a240661123fc83cef874bc43779b65645c3|main@b995873f2b76e0c37a08f23fbf40322174aba6fe|

Branch `codex/flutter-m4-complete-implementation` from main, earliest sufficient base. All routine/product/experiment source and current PSM entry already exist there; no dependency on PR10 Home priorities, PR11 measurement history, PR12 PSM additions or F8 unmerged operations. No unrelated stack imported or ref changed. Canonical Master Plan v1 previously read in full in this conversation from unchanged PR10; relevant scientific/roadmap sections and app/AGENTS.md rechecked; no nested AGENTS. The plan remains absent on main, so do not pretend its file was merged.

Read-only Backend evidence: schemas/experiments.py MetricContract/EvaluationOut/ExperimentOut; services/experiments.py activation/frozen configuration/evaluate/coverage; actual routine/adherence models and source, frontend repositories/receipt/revision recovery and product/history/warning tests. Current optional MetricContract schema1, experiment engine2, deterministic experiment_v2_rules_1. No live API calls.

## B. Six original requirements

| Requirement | Existing implementation | Demonstrated gap | New change | Test evidence | Final status | External dependency |
|---|---|---|---|---|---|---|
|Integrated daily routine|AM/PM configuration/instructions, day selection, user reports, product/experiment/PSM/reminder navigation|Resume could leave old read represented as current; dependency reuse|Stale read fence/resume GET, rebind, explicit per-slot evidence|New lifecycle/controller/widget tests + routine/integrated suites|IMPLEMENTED — NEEDS EXTERNAL QUALIFICATION|Live/device lifecycle qualification|
|Product inventory/stable references|Owned CRUD, stable IDs, missing/deleted states, ingredient completeness/warnings, linked routine and frozen product|Routine/history and frozen experiment presentation lacked explicit original IDs|Show entry/product/revision and original frozen/saved evaluation references; no current-name substitution|Product authority/revision/receipt suites + frozen-reference widgets|IMPLEMENTED AND VERIFIED|Live ownership/clinical ingredient-rule qualification separate|
|Unknown versus skipped adherence|Explicit completed/skipped POSTs; missing records not auto-written; UTC history/config snapshots|Current slot did not explicitly label unknown or historical configuration|Read-only slot labels; compare original configuration/revision; loaded-history absence stays unknown; original write eligibility unchanged|All four slot states, partial history, stale read, existing duplicate/uncertain/revision cases|IMPLEMENTED AND VERIFIED|Bounded loaded history is not proof of lifetime absence|
|Lifecycle/frozen configuration|Draft/create/edit/activate/finish/evaluate; explicit activation review, original revision/idempotency/receipts; frozen server snapshot|Frozen IDs/window under-presented; late activation/finish context and resume|Frozen snapshot presentation; activation epoch/controller and finish guards; stale reads do not erase unresolved operation identity|New stale-controller/frozen UI + full lifecycle/revision/receipt regressions|PARTIAL|Verified nonclinical engine supported; case-specific clinician-plan baseline contract absent|
|Contextual evidence/evaluation|Saved evaluation plus current coverage and PSM navigation|Returned metric contract ignored; false units-unavailable copy; saved adherence/context/reference evidence under-presented|Typed metric/method/source consistency, saved aggregate validation, original references and context/unknowns|Parser variants, invalid aggregates/confounders, real remote controller, units/zero/null widget cases|PARTIAL|Legacy deterministic engine not qualified plan-linked clinical/image comparison; timing contract missing|
|Insufficiency/association limits|Server labels/limitations, no causal claims|Missing-unit copy now contradicted supplied contract; insufficient detail on unknown evidence|Known versus legacy absent-unit distinction; nonclinical score units; mixed image algorithms cannot carry directional claims; explicit unknown context/adherence limits|New metadata/mixed/null/zero tests plus existing insufficient-evidence suites|IMPLEMENTED AND VERIFIED|Clinical/causal/model qualification not implied|

Four safely code-addressable gaps completed: metric contract/integrity; frozen/saved evidence presentation; adherence configuration/unknown clarity; read lifecycle and route context. No existing product/routine/experiment module recreated.

## C. Delivered production behavior

### C1. Typed metric and aggregate safeguards

app/lib/experiments/metric_contract.dart parses supplied optional schema1 only: metric hydration/texture/redness; score_0_to_100 and score_points; manual/image_proxy; direction per metric; within_UTC_day_mean_then_equal_day_mean; experiment_v2_rules_1; measurement algorithm versions/provenance; clinical_measurement false. Cross-checks observed metric, compared source and provenance algorithm. Enforces finite score/difference bounds and method metadata consistency; rejects directional image labels with mixed method provenance. Null and zero remain distinct, no percentages or capture-fraction conversion.

Saved adherence requires coherent expected/reported/followed counts, supported explicit expected status and user_reported source; supplied fractions must match counts. Known confounder count/Boolean types validated. Empty legacy evidence remains absent, not zero. Missing optional metric contract remains supported as legacy with units/method caveats; malformed supplied contract fails closed. app/lib/experiments/experiment_contract.dart applies this at the actual remote response boundary; new real-controller regression verifies an unsupported refresh becomes stale/error rather than current medical evidence.

### C2. Frozen/current/saved evidence

app/lib/experiments/experiment_evidence.dart introduces FrozenExperimentSummary and ExperimentEvidenceDetails, reused in existing experiment cards. Shows experiment, routine/product IDs and resource revision; validates linked snapshot IDs/source/engine before presenting a frozen product/window. Unsupported legacy snapshots explicitly unavailable. Frozen names/IDs never substituted from a renamed/deleted current product. Baseline records are only those explicitly returned by the frozen snapshot, at most100 shown.

Saved evaluation separately shows returned units/method/source/versions/direction, baseline/current means with null preserved, saved aggregate coverage/unreported unknown slots, supplied confounders, saved frozen references and original observation/adherence/context references (at most100 per source). Missing context stays unknown. Arithmetic unreported slots is expected minus reported within a validated aggregate, not generated adherence records or a new medical assessment. Following a stop-entry experiment means explicitly reported skipped use, not automatic non-use. No date-guessed joins, causal treatment effect, model inference or improvement percentage.

app/lib/experiments/experiment_ui.dart retains server summary/limitations/current coverage and PSM navigation, replaces the old false units copy/details, keeps saved results distinct from current resource verification, and disables expansion animation for reduced motion. Existing supported lifecycle actions remain, no new transition or comparison schedule.

### C3. Slot/history semantics and stable references

app/lib/routine/adherence_evidence.dart reads only loaded selected-day/slot history. No row means adherence unknown in the loaded window; explicit completed/skipped remains the actual report. A configuration/revision mismatch becomes Historical configuration report, not proof of the current step. Multiple conflicting loaded identities require refresh. No record created by this component.

app/lib/routine/routine_ui.dart renders these labels alongside existing explicitly chosen report actions, and shows stable current entry/product/revision and historical product/entry identity. History retains its original product name and snapshot schedule. Original uniqueness, UTC dates, selected-day/server eligibility, pending operation, product and original revision checks remain unchanged; unknown slots never become skipped. Existing product inventory/ingredient warnings remain authoritative and unchanged.

### C4. Lifecycle/context guards

RoutineController and ExperimentController markReadStale fences pending read epochs and disables stale actions without clearing original uncertain sets/API operation intents. An in-progress write is not invalidated into a replacement intent; its existing confirmation/reconciliation flow remains responsible. Background/read invalidation is not proof that an already sent request never ran. Resume performs GET refresh only, never POST replay.

RoutineScreen replaces/disposes controllers on changed state/repository, preventing prior source publication. ExperimentsView rebinds session/controller scope, invalidates pending activation review epochs on background/change, and checks original controller/context after asynchronous activation/finish confirmation. Lifecycle observers removed on disposal. Existing API/session ownership, denied-read wiping, original grant/clinical status and pending operation safeguards retained.

### Preserved source

Product CRUD, ingredient facts/rules/completeness/warnings, stable IDs, missing-product states; routine configuration/editor/history/calendar/reminders; original adherence POST/receipt lookup; experiment creation/edit/activation/frozen engine transitions/receipt and revision recovery; clinical panels/PSM navigation. No Backend/native/Tester/dependency/provider/policy change. English-only established themes/navigation/typography. No broad redesign or unapproved Agent/clinical action.

## D. Validation

Flutter3.44.8 stable, framework058e0af2c2b57e369d905a03ac9748b0ebf543c6, Dart3.12.2. No OAuth/live patient/clinical/provider/production call. Existing test HTTP denial plus explicit synthetic-host assertions.

- `flutter test --no-pub --reporter expanded test/m4_completion_test.dart`:30 passed,0 failed/0 skipped,exit0.
- Related command: `flutter test --no-pub --reporter expanded test/m4_completion_test.dart test/m4_routine_test.dart test/m4_adherence_test.dart test/m4_experiments_test.dart test/m4_products_test.dart test/m4_integrated_test.dart test/product_authority_test.dart test/product_intelligence_test.dart test/routine_authority_test.dart test/experiment_authority_test.dart test/wave_routine_revision_test.dart test/wave_routine_receipt_test.dart test/wave_product_revision_test.dart test/wave_product_receipt_test.dart test/wave_experiment_revision_test.dart test/wave_experiment_receipt_test.dart test/wave_adherence_receipt_test.dart test/wave_p_routine_evidence_test.dart test/personal_skin_model_test.dart test/clinical_status_test.dart test/session_lifecycle_test.dart test/comparison_architecture_test.dart`:682 passed,0 failed/0 skipped,exit0. Final full suite also includes all these tests after final evidence-reference display assertion.
- `flutter test --no-pub --reporter expanded`:2284 passed,0 failed/0 skipped,exit0.
- `flutter analyze --no-pub`:no issues,exit0.
- `git diff --check`:clean,exit0.

New tests exercise production parsers, remote controller over synthetic HTTP, actual stale controllers and widget source/lifecycle/rebinding/layout. Both themes320px200%reduced motion covered. One existing routine stop test now ensures the control is visible before tapping after added evidence text; all confirmation/failure assertions preserved. No tests deleted/weakened.

Disposable exact PR10/11/12/8 archives, clean application of only main→M4 app delta; identical pubspec/lockfile, cached host dependencies, no original refs mutated. All exact-source full suites passed with exit0 and0 failed/0 skipped: PR10+M4 **2337**, PR11+M4 **2311**, PR12+M4 **2315**, PR8+M4 **2372**. Command in each disposable app: `flutter test --no-pub --reporter expanded`. CI final details recorded in delivery supplement. These are source compatibility tests, not real merged/native/live builds. No active workflow on main; inspect actual new head and merge candidate, never substitute PR8 green checks.

## E. Git delivery

Branch/base in A. Source commit b2bf9cfc21a345b8696c3e83845c9ae9367046a2 — feat(flutter): complete M4 evidence, adherence and read lifecycle safeguards. Closeout docs/status commit, normal push, exact final head/Draft URL/clean state recorded in delivery supplement. Local publishing identity verified Amr-A-Abdallah; no force push or modification of PR6–12/main.

Production changes: experiment_contract.dart, experiment_controller.dart, experiment_ui.dart, new metric_contract.dart/experiment_evidence.dart under app/lib/experiments; routine_controller.dart/routine_ui.dart/new adherence_evidence.dart under app/lib/routine. Tests m4_completion_test.dart and routine_authority_test.dart. Documentation: required plan/report/handoff and appended FLUTTER_IMPLEMENTATION_STATUS.md; prior history preserved.

## F. Owner handoff

See M4_EXTERNAL_DEPENDENCIES.md. Actual Backend gap: services/experiments.py activation chooses previous28days and freezes it; no approved plan-linked per-case baseline selection input. Flutter displays the recorded engine window and must not invent a clinician-approved interval, reinterpret the frozen cohort or retrofit client-only plan IDs. Existing durations are editable within actual7–90day contract; no universal28day duration imposed. Hussam owns coordinated API/engine semantics, Amr the product/clinical timing decision. No issue/message sent to Hussam.

## G. Readiness axes

1. Flutter supported source: four identified gaps completed/tested.
2. Backend contracts: repository/schema/mock verified; live deployment compatibility pending.
3. Routine/adherence/experiment integrity: original identities, revisions, frozen records and unknown semantics preserved; no optimistic completion.
4. Evaluation/model: bounded deterministic rule evaluation supported; per-case clinical baseline and validated image/causal model NOT established.
5. Physical/live journey: device/lifecycle/privacy/accessibility and isolated integration pending.
6. Clinical/safety: no medical accuracy/causation/clearance claim; external clinical qualification remains.
7. Independent QA: PENDING SALMA REVIEW.
8. Product M4 closure: PENDING FORMAL CLOSURE; plan timing policy remains PARTIAL.

## H. Remaining real M4 dependencies

- Backend/product: approved case-specific baseline/follow-up authority and immutable plan/evidence binding, preserving revision/idempotency/legacy histories. Current nonclinical engine window is not a universal treatment plan. Cannot safely change Flutter-only.
- Deployment/live/device/QA: verify real endpoints, original operation response loss/revocation and physical lifecycle/read isolation; independent Salma review. Host synthetic suites do not qualify those environments.
- Clinical/model: validate ingredient rules and any intended clinical/image/causal interpretation before such claims. Current deterministic evidence remains labeled observational; no request to enable AI/providers.
- No further independent safe Flutter code gap demonstrated within this review. Optional OCR, scanning, automated schedules, new navigation and new Agent tools are not introduced as mandatory M4 backlog.

## I. Next milestone

M5 — Preferences, Notifications & Offline Recovery: reconcile existing preferences/consent, actual reminder scheduling versus delivery, account-scoped secure cache/drafts and original-operation reconciliation. Then M6 clinician workspace/grants/notes/review/messaging/plans/export/revocation. Existing implementations must be inspected, not recreated. M5 not started; no F9 or roadmap change.

**M4 Flutter implementation:** COMPLETE — supported contract/source scope

**M4 newly identified code-addressable gaps:** 4 completed / 4 identified

**M4 external blockers:** per-case clinician-plan baseline/timing contract and product approval; live/device/privacy/clinical qualification; independent QA

**Routine experience:** VERIFIED — synthetic source scope

**Product inventory:** VERIFIED — existing stable-reference implementation preserved

**Adherence semantics:** VERIFIED

**Experiment lifecycle:** VERIFIED — bounded existing nonclinical engine; clinical timing dependency remains

**Evidence/evaluation:** PARTIAL — deterministic source verified; case-specific clinical timing/model not qualified

**Focused tests:** PASS —30 new,682 related

**Full Flutter tests:** PASS —2284

**Flutter analyze:** PASS —no issues

**Git delivery:** see delivery supplement

**Draft PR:** see delivery supplement

**Independent QA:** PENDING SALMA REVIEW

**Product milestone M4:** PENDING FORMAL CLOSURE
