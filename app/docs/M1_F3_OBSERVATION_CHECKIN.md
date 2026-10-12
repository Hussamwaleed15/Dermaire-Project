# M1-F3 — Patient Observation & Check-in Experience

## Source / scope

Started on clean main at `fd51823dae708997ca42f9a6f8fdb573a274c622`, matched
origin/main and fresh GitHub main. Read app/AGENTS.md, architecture/product/agent
and roadmap audits, M1-F2 docs, actual check-in/history/Home/baseline/safety/context
source, schemas and existing regression tests. English-only/direct Flutter.
No visual prototype/gallery, backend/infrastructure/provider/tester work or deploy.

## Actual API contracts

Inspected backend/app/api/v1/checkins.py, schemas/__init__.py (CheckInReport,
SafetyDisclosure, CheckInObservation, CheckInResponse), services/baseline.py,
api/v1/home.py, baseline.py, safety.py, context.py and tests/test_skin_history.py,
test_checkin_vision_boundary.py/safety tests. Existing authentication validates
signed access JWT/credential stamp, logout revocation and live account; reads/
writes are get_current_user-owned. Client further requires the authenticated
patient session and server-confirmed acceptance; that is not backend authorization.

- POST /api/v1/checkins: multipart time_of_day Morning/Evening (server defaults
  Morning), optional report JSON/notes<=1500, optional experiment/scores/photo.
  This new journey explicitly selects moment and sends report-only: no scores,
  files, invented timestamps/IDs, context fields or idempotency claim.
- Report: required overall_change better/same/worse; symptoms array of redness,
  dryness, itching, burning, breakouts, sensitivity, texture (default [], max 7,
  server deduplicates); optional routine_status followed/partial/skipped/
  not_applicable; optional safety. Unselected concerns mean not reported, not a
  clinical negative. No optional sensitive answers are required.
- Safety: nullable severity/pain none/mild/moderate/severe and eight bool/null
  fields: breathing_difficulty, facial_or_mouth_swelling,
  eye_or_mucosal_involvement, fever_or_systemic_illness, rapid_spread,
  extensive_blistering_or_peeling, pus_or_hot_swollen_skin,
  new_medication_or_product_reaction. Unknowns are omitted/null, never false or
  zero. No local medical interpretation, severity score or clearance.
- 201 response after database commit: actual id, user_id, created_at, time_of_day,
  nullable notes/scores, ai_vision_analysis.measurement_source, schema-1
  observation with reported values/provenance/server UTC context date/link,
  nullable experiment/image metadata. UTC DB timestamps can serialize naive;
  parser uses documented UTC, validates dates and never invents a timestamp.
- GET /api/v1/checkins: own confirmed rows only; descending created_at/id,
  unpaginated list, no GET-by-record or attempt lookup. Includes report-only and
  confirmed manual/image_proxy tracking rows; legacy/simulated rows quarantined.
  History does not combine Capture records or optimistic save receipts.
- Existing idempotency_key header applies only to the photo branch. Report-only
  POST does not deduplicate. No report attempt key/lookup/read status proves an
  unacknowledged request. Plain matching content/time is not sufficient proof.
- GET /home.today_checked_in/journal and /baseline.completed_days/status use
  confirmed tracking measurements only. Report-only save cannot create a metric,
  baseline day or Home completion. Source projections were not overridden.
- Existing /context/{day} supports only nullable unusual_conditions and cycle_day
  1..60; server assigns current UTC context linkage to the observation at save.
  Existing context navigation is retained, not a new questionnaire. No weather,
  sleep, stress, diet, medication, exercise or other unsupported fields added.
- Auth failure 401 invalidates session; definitive validation/access rejection
  uses 400/403/404/409/422. Server/proxy 5xx, offline, timeout or malformed/mismatched
  acknowledgements are treated conservatively as uncertain, not proof of rollback.

## Before / implemented journey

The former CameraScreen mixed observation fields/capture with immediate POST and
navigation to generic Check-in complete, while TimelineScreen used dynamic maps,
weak session guards and raw timestamp formatting. Existing route names/entry
points now delegate to a single observation screen and the same history route;
no new tab/navigation/Home redesign or duplicate history destination.

Edit -> review -> explicit one-attempt submission -> confirmed receipt OR
rejected/uncertain/session-ended. Change/time chips, optional symptom selections,
routine chips, notes, collapsed optional safety answers and separate capture
panel are interactive native controls using the approved design. Required
change/moment validation is accessible; optional unanswered health fields stay
unknown. Review echoes requested values before any POST. Editing invalidates
review; rapid duplicate taps cannot send another request.

Owned drafts/records/history live in ObservationController memory only. Typed
immutable report/record values validate owner, IDs, timestamps, schema/provenance,
nullable/unknown fields, measurement kinds and metrics. Both API and controller
validate ownership, including injected repositories. Unknown server values are
shown explicitly without defaulting to safe/zero. Invalid/simulated/foreign data
cannot populate confirmed records. Arrays/maps are immutable; raw AI payloads,
credentials and medical data are not logged or persisted in plaintext.

## Save / reconciliation semantics

Confirmation requires 201 plus actual owner/record identity/date and an exact
report-only match of time, notes, selected concerns, routine and every explicit/
unanswered safety field. No success is shown merely after pressing Save.

Submitting is real indeterminate feedback (static text in Reduced Motion).
Definitive rejection permits editing and another explicit reviewed submission.
30s write timeout, network failure, 5xx or unverified 201 becomes uncertain.
There is no automatic POST retry, no direct Save button in that state, and no
exactly-once promise. Reopening the flow retains its uncertainty within session.
Starting a separate observation requires an explicit duplicate-risk dialog;
re-reading empty history never proves the old request failed.

If an own server record ID was returned with an unverified 201, a readonly GET
can confirm that exact ID plus matching recorded fields/owner. Otherwise history
is for patient review only; similar content/time, safety evidence or empty lists
cannot identify this attempt. Reconciliation itself never sends POST. Lost/late
results cannot update a newer attempt/session. The confirmed receipt uses the
server ID/time and actual values; missing history after a valid acknowledgement
is explained without repeating the already-confirmed write.

## History / evidence separation

The existing TimelineScreen is the saved-observation history entry. Loading,
empty successful GET, refresh, stale retained rows, failure and retry are explicit.
Stable server IDs are unique, preserve server order and key history cards. No
local optimistic insertion/merging. Each row displays recorded change/concerns/
routine/notes and available recorded safety fields, actual UTC time, context
linkage and explicit server-linked check-in photo metadata only.

Report-only observation: no recorded measurements. Manual: user-entered tracking
metrics. image_proxy: nonclinical image estimates. Unknown/missing source: no
confirmed metrics displayed. Unknown does not become zero. Standalone captures
stay separate and are not attached by this report-only flow; capture UX/API/
privacy disclosure remain unchanged. No before/after improvement or diagnosis.

## Safety / session / accessibility

M1-F2 panel precedes review/submitting/receipt/uncertainty content. Save-state
changes expose the top guidance without a success animation hiding urgent advice.
Confirmation and uncertain outcomes re-read safety/clinician projections; those
reads are never used as proof of saving. Confirmed writes only refresh Home/
baseline from their existing servers. No local counter/clinical risk classifier.

Session generation binds every edit/review/submit/read/reconcile/navigation.
Independent request revisions reject old/overlapping history or submission
results. Reused-token late 401 cannot invalidate a new account. Logout, switch,
expiry and disposal erase private drafts, receipts/candidates and history; old
screens/actions cannot alter another account or navigate after invalidation.
No insecure draft persistence or medical/account/credential payload logging.

English-only, existing Cream/Ivory/Burgundy and Charcoal/Graphite/Rose palettes,
typography/cards/actions. Optional expansion/press feedback respects shared
Reduced Motion. No fake percentages, local clinical success or expensive visual
work. Native controls, status/live semantics, responsive wraps/scroll and 200%
text preserve access; validation stays reachable. No forced medical disclosure.

## Verification / status

Verified in the actual Flutter checkout: `flutter analyze` reports no issues;
full `flutter test` reports **444 passed** (**388 previous + 56 new**). No
existing auth/consent/profile/safety assertion was removed. All explicit
transports use flutter-tests.invalid and the test binding still denies real
HTTP, including production hosts. No live patient/OAuth/API/provider calls,
release builds or deployments were performed.

New regressions
cover supported/unanswered/unknown fields, provenance/UTC/owner, review gating,
single dispatch and duplicates, 4xx rejection vs uncertain 5xx/offline/timeout,
malformed/foreign/mismatched 201, exact-ID-only GET reconciliation, empty/stale/
failed history, old 401 and overlapping histories, logout/switch/expiry, supported
history provenance, eight theme/large-text/motion journey cases and explicit
safety answers. Existing observation/history widget tests were adapted to the
new authenticated reviewed flow and actual owner/time contract; all their
original authority/no-measurement/no-Home-completion assertions remain.

## Limitations / completion boundary

The supported observation journey passed final checks; delivery completes with
the verified normal main push.
Backend B1 and B2 remain deliberately unresolved: no optimistic Home completion,
report-only baseline reinterpretation or exactly-once delivery. No-ID uncertain
writes cannot be automatically confirmed/resubmitted. Unpaginated history and
no dedicated attempt lookup remain contract limits. Wider context schema,
backdated observations and capture linkage are not invented. See the precise
Hussam handoff. No subsequent milestone, backend/production mutation, real
patient/OAuth/API/provider test or deployment is included.

## Modified files (12)

- `app/lib/app_shell.dart`
- `app/lib/dermaire_state.dart`
- `app/lib/dermaire_widgets.dart`
- `app/lib/services/api_service.dart`
- `app/lib/observations/observation_models.dart`
- `app/lib/observations/observation_controller.dart`
- `app/lib/observations/observation_ui.dart`
- `app/test/observation_test.dart`
- `app/test/skin_history_test.dart`
- `app/test/clinical_status_test.dart`
- `app/docs/M1_F3_OBSERVATION_CHECKIN.md`
- `app/docs/M1_F3_HUSSAM_HANDOFF.md`
