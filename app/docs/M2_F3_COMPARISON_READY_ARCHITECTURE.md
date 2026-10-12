# M2-F3 — Comparison-Ready Flutter Architecture

Date: 2026-10-13. **Architecture readiness only**, not a delivered AI comparison,
scheduling service or patient follow-up feature. Source: clean main
`c7f5bd5b44dbb6b02562322cd0abe9495dfb820e`, matching local origin/main and a fresh
remote main read. Permanent app/AGENTS.md, relevant architecture/agent audit and
roadmap sections, M2-F1/F2 documentation, current Flutter source and real backend
schemas/routes/services/model inventory were inspected before implementation.
English-only/direct Flutter, no prototype, deployment, provider or infrastructure work.

## Existing supported contracts, inspected read-only

| Capability | Real source / boundary |
| --- | --- |
| Routine | api/v1/routine.py, schemas/routine.py, services/routine.py. Owned entry CRUD, AM/PM/BOTH daily configuration, start/end dates and user_configured source; adherence completed/skipped, dated slots, user_reported and frozen configuration snapshots. Routine adherence supports limit/offset. These are not comparison schedules. |
| Experiments | api/v1/experiments.py, schemas/experiments.py, services/experiments.py. Owned v2 draft/activate/finish/evaluate/results and routine-entry intervention; target_days 7..90, current_day, coverage and persisted deterministic evaluation. Evaluation compares check-in/adherence/context evidence to an activation-frozen prior UTC window; it is not an AI assessment of a scheduled baseline/follow-up image pair. Existing evaluation labels/provenance remain unchanged. |
| Doctor review | api/v1/doctor.py, schemas/doctor_loop.py and schemas/__init__.py, services/doctor_loop.py. Patient /doctor/review-status and authorized clinician reviews/notes/timeline. Sequenced review actions include follow_up_needed; note follow_up is optional free text (100 chars), not a structured instant/timezone/due state/image plan. Never parse that prose into a schedule. |
| Captures / images | Existing owned captures list/by-ID; authenticated /captures/{id}/image; capture Idempotency-Key; M2-F1 receipt/controller and M2-F2 private image store/screens. No public/SAS image dependency or camera rebuild. |
| Measurements | api/v1/measurements.py, services/measurement.py. Stored deterministic measurement-1.0 appearance proxies and comparison metadata exist. The comparison searches prior measurements, has not_comparable reasons and a reserved engineering-delta branch. Current genuine quality leaves yaw/pitch/occlusion/uneven_lighting unknown, so validated comparability is blocked. This existing comparison is not a doctor/AI scheduled plan or explicit intervention/image association. No new clinical scores or reinterpretation were added. |
| Personal Skin Model | api/v1/personal_skin_model.py, schemas/personal_skin_model.py, services/personal_skin_model_v2.py. Owner-scoped deterministic PSM v2 integrates sources, freshness, unknowns, experiments, image proxies, safety and doctor context. Assistant layer is nonauthoritative and not included. It is not the proposed AI image comparison model or a scheduling API. |
| Assistance / chat | api/v1/contextual_ai.py, chat.py, schemas/contextual_ai.py, services/contextual_ai.py. Bounded contextual assistance, fixed task/next-step vocabulary, safety/clinician precedence, grounded/degraded modes. No executable comparison scheduler, persisted follow-up plan or AI image assessment job/result contract. |
| Notifications | Existing Flutter templates; no device-token/preference/follow-up delivery contract found in router/model inventory. No notification implementation or provider activation. |

Current Routine/Experiment/Clinical controllers, ApiService session guards,
GuidedCaptureRecord, PrivateCaptureImages/PrivateCaptureImage, shell and entry
were inspected. Backend models contain Capture/Measurement, routine/experiment
and clinician records, but no confirmed comparison-plan/assessment-job entity.
No existing wire DTO or route was changed. These observations describe the
checked source, not a live production runtime attestation.

## Product and authority rules

Routine or experiment completion never schedules comparison. No hardcoded
three-week interval, device-chosen medical date, oldest/newest history pairing,
filename/time/similarity association or proxy-to-clinical baseline conversion.
Follow-up timing and image relationships must come from a persisted, authorized
future server record. AI proposal, clinician decision and patient confirmation
remain separate. Flutter does not resolve disagreements or silently replace
clinician authority. Existing independent Safety/Clinician guidance remains
unchanged; a future real screen must compose those current authoritative panels.

## Proposed domain, distinct from wire DTOs

New app/lib/comparison/comparison_domain.dart is explicitly marked **proposed**.
It contains no fromJson/toJson, API paths, provider invocation, local inference,
numeric medical score/percentage/confidence field or persisted synthetic state.
The names below are internal integration concepts, not supported JSON fields,
server enum codes or backend promises. A future verified adapter must map the
real schema and authorization evidence before constructing these objects.

- ComparisonPlan: owner/ID, positive revision, recorded UTC instant; lifecycle;
  immutable SchedulingDecision records; optional server-resolved decision and
  resolution note; patient confirmation, schedule, explicit intervention and links.
- SchedulingSource distinguishes doctorDirected, aiProposed, patientConfirmed,
  unknown. Decision identities and server resolution are preserved; no local rank
  chooses a medical winner. Unknown stays unknown.
- FollowUpSchedule: nullable canonical UTC instant, nullable server-reported
  timezone label and nullable serverDue. No DateTime.now comparison, DST guessing,
  default date or timer changes medical status. Naive/local instants are rejected.
  A past date with unknown/false due remains unknown/not due as supplied.
- Lifecycle: not scheduled, pending confirmation, scheduled, awaiting date, due,
  awaiting capture, requested, processing, available, rescheduled, cancelled,
  rejected capture, insufficient evidence, failed, expired, superseded, unknown.
  These can be represented, but there is no local transition command/state machine.
- InterventionReference: routine/experiment/product intervention/follow-up plan/
  unknown kind plus actual record and explicit relationship-record identity.
- PlanCaptureAssociation: owner, plan, revision, baseline/follow-up role, capture ID
  and relationship-record identity. Optional owned M2-F1 by-ID metadata. Parent
  identity/revision/role, capture owner/ID and distinct pair are validated. A
  missing link or metadata stays missing; rejected/not-stored metadata does not
  load an image. These reference strings are adapter attestations, not proof that
  a server contract already exists or cryptographic verification by Flutter.
- ComparisonAssessment: identity, owner/plan/revision, assessment revision/status,
  nonclinical/AI-observation/clinician-authored/unknown source, nullable version and
  generation UTC instant, explicit pair references, evidence records, observations,
  limitations, uncertainty and review state/record. Available reports require a
  generation instant and matching explicit pair; recorded review requires a record.
  Failed/pending/insufficient states cannot contain successful observations.
- ComparisonSnapshot: verified plan + optional assessment, UTC read observation
  and supplied fresh/stale/unknown status. Assessment links/owner/revision must
  match the current plan. Unknown source observations are not displayed.

For conservative presentation, a confirmed schedule requires a known doctor/AI
resolved source, explicit date, confirmed patient state and an active supported
lifecycle beyond not-scheduled/pending-confirmation. Patient confirmation alone
cannot act as a scheduling authority. This is a read-presentation guard, not
medical/AI-processing permission. Doctor plans with notRequired confirmation are
representable, but not enabled for the prepared viewer/camera handoff until the
future consent/authorization contract is verified. Adapt these domain policies
when the actual contract is agreed; do not make the server conform blindly to
speculative client fields.

## Repository / controller boundary

comparison_repository.dart exposes proposed readPlans/readPlan operations with
owner/session-generation context. **UnsupportedComparisonRepository is the actual
default**: both methods throw explicit unsupported capability, make no HTTP and
return neither fake empty records nor schedules/AI replies. There is no real
backend adapter, new ApiService method or application-state registration.
Synthetic implementing repositories exist only in tests.

ComparisonController is a route-lifetime ChangeNotifier for a selected plan.
It binds authenticated patient owner, confirmed safety acceptance and generation,
then validates response plan identity, revisions and request sequence. Every
refresh removes the displayed snapshot. Missing read, unsupported capability,
loading, timeout/error, stale, ready and ended are distinct. A successful null
from a future repository is an empty read; unavailable is not empty success.

Newest request wins. Lower plan revisions or conflicting same-revision schedule/
source/link definitions cannot replace newer state. Observed revision watermarks
are retained even for stale records: a stale newer cancellation cannot be followed
by an older fresh response restoring images. A temporarily missing assessment
does not remove the remembered revision for that assessment. Watermarks are
in-memory defenses within this route, not a substitute for a real server
revision/conflict/freshness/assessment-supersession contract.

Logout/account switching/expiry/revoked consent clear state and watermarks and
invalidate pending work. Reused tokens do not bypass generation boundaries.
Future HTTP adapters must use existing ApiService session transport; the
controller never interprets an old 401 as a reason to log out the newer account.
No plaintext persistence, medical payload/token/account/image log or analytics.

## Prepared components and camera context

comparison_ui.dart provides small reusable components, **not a new routed screen**:

- ComparisonPanel: schedule/UTC/source/confirmation/explicit context, status/read
  retry and assessment source/limits/uncertainty/review. Unknown/failure/pending
  states do not show successful conclusions; model observations are not relabeled
  clinician diagnoses. Inactive/unconfirmed schedules do not show current results.
- PlanReferenceImages: requires controller-validated fresh confirmed plan. Two
  explicitly associated references displayed side-by-side at wide normal text,
  vertically at narrow/large text. Reuses M2-F2 authenticated PrivateCaptureImage,
  bounded shared transfer/decode, ui.Image lease disposal, zoom/pan and accessible
  controls. No arbitrary-ID pair picker, image URL parameter, clinical alignment,
  normalized Before/After or computed improvement claim.

Existing semantic themes/cards are reused; no new dependencies or framework,
custom expensive motion or extra loading animation. English-only, reduced-motion
presentation, keyboard read retry, semantic controls and 320px/200% text are tested.
No Home/bottom-nav/camera/history/observation/auth/Tester modification or
production comparison entry point. Fixtures are only in test files.

FollowUpCaptureContext is a data handoff, not an association receipt. It is exposed
only for a current confirmed plan with explicit date, server due=true, linked
baseline and due/awaiting-capture state. recognizesUnassociatedCapture checks that
context is still current by plan/revision/owner/session, and the received M2-F1
capture is accepted/stored/owned. It does not mutate the plan, designate the
capture as follow-up or prove quality/comparability. Old contexts fail after
reschedule/cancel/logout/switch. canAssociateCapture and canRequestAssessment
remain false. No camera-launch action, attach/assessment POST or automatic retry
is added until the missing write contract exists.

## Verification / limits / completion

Final flutter analyze: No issues found.
Final full flutter test: **829 passed** = **703 preserved** + **126 new**.
New regressions cover the proposed states/sources/unknowns/date/zone/intervention,
strict relationship/assessment evidence, disabled adapter/no HTTP, null vs stale/
error, timeout/retry/concurrent/late responses, revisions/cancel/reschedule,
missing assessments, camera context invalidation, current/old401 with reused
synthetic token, account/consent/expiry, unimplemented production navigation,
Light/Dark/reduced/large text/keyboard/semantics and private paired-image disposal,
missing data, bounds/reused store and account isolation. Existing M2-F2 encoded/
source/decoded limits and cache regressions remain passing. All fixtures are
synthetic and HTTP denial remains enabled. No real accounts/Production/staging/
OAuth or device/emulator acceptance/performance profiling was used.

**M2-F3 architecture readiness COMPLETE** after verified commit/normal main push.
The full scheduled AI comparison feature remains unavailable: no actual plan,
schedule, association, assessment model/job/result, AI consent or notification
contract was implemented/enabled. No restart/offline comparison retention,
image alignment, clinical evaluation, slider algorithm, export/share or new
provider. The existing image viewer is reused without claiming clinical alignment.
Future adapter/schema work may refine domain concepts; this is not a promise of
wire compatibility with an unbuilt AI model.

See M2_F3_HUSSAM_HANDOFF.md for existing vs proposed contract requirements.
External testing team owns Android/device/emulator acceptance. No M2-F4 started.
