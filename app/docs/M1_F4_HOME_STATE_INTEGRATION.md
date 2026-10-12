# M1-F4 — Intelligent Patient Home State Integration

## Source and completion scope

Source: `41511eb4a0b48c6139822ab0150527eea99a7194`, clean main, matching
origin/main and fresh GitHub main before editing. Inspected app/AGENTS.md,
the architecture/product, agent capability and patient roadmap audits, M1-F2/F3
implementation/handoff docs, current Flutter Home/state/account/clinical/
observation/capture/routine/experiment/navigation/theme code and backend source.

Supported M1-F4 Flutter scope is implemented and validated; delivery completes
with the verified normal main push recorded in the completion report. This is not completion of all M1 or resolution of backend B1/B2.
No new milestone, prototype, visual gallery or separate approval stage.

## Actual contracts (source inspection; no live API certification)

Inspected backend/app/api/v1/{home,baseline,checkins,users,safety,doctor,
experiments,routine}.py, schemas/{__init__,safety,doctor_loop,experiments}.py,
services/{baseline,safety,doctor_loop}.py and existing authority tests/docs.
All patient reads use signed authenticated owner from get_current_user; no
patient selector is sent. Doctor review additionally requires patient role.
Flutter's patient/confirmed-consent guard does not replace server authorization.
401 revokes local session through existing transport; 403/5xx/timeout/offline
are unsuccessful reads, never empty positive results.

- GET /api/v1/home: as_of timezone-aware UTC calculation time, date UTC day,
  today_checked_in strict bool, experiment nullable and journal list <=2.
  experiment is latest owned active/paused/baseline row by created_at/id:
  id, status, current_day, target_days, primary_concern, nullable product_name
  and three nullable finite delta_percent fields. Day is schedule, not reported
  adherence. v2 deltas are null; legacy deltas compare tracking values against
  an unlinked reference but this reduced projection omits engine/source/quality
  details. Home therefore does not display improvement percentages.
  journal contains newest confirmed tracking rows by created_at/id, including
  experiment-linked rows: id, UTC created_at (DB can serialize naive UTC),
  time_of_day, measurement_source manual/image_proxy and three finite 0..100
  scores. No symptom-only completion, clinician decision or event feed fields.
- GET /baseline: status collecting/ready, required_days=5, completed_days 0..5,
  checkin_ids, metrics map empty until ready then hydration/texture/redness
  mean/stddev, today_checked_in strict bool. First five distinct UTC days of
  owned, unlinked, confirmed tracking values before cutoff form the reference;
  later entries do not silently replace it. today_checked_in uses all qualified
  unlinked rows, not only those five. No server as_of, source breakdown or
  clinical interpretation. Client labels retrieval time distinctly and hides
  prior-UTC-day baseline from current views. It does not calculate new scores.
  Home and baseline have different scopes and separate read times; disagreement
  is displayed, not resolved locally.
- GET /checkins: owner-filtered, descending created_at/id, unpaginated list;
  record id/user_id/actual UTC created_at/time_of_day, nullable user-report,
  notes/metrics/image metadata. Existing M1-F3 typed adapter validates ownership,
  schema/provenance/date/source/metrics and rejects simulated/invalid records.
  Report-only source=none has no metrics. manual is user-entered tracking;
  image_proxy is nonclinical estimate; unsupported source shows no confirmed
  metrics. Actual server records alone populate recent activity. Receipt/draft,
  stand-alone Capture, routine and experiment events are not guessed or merged.
- GET /safety: safety-1.0, evaluated_at, exact statuses track,
  low_risk_self_care, doctor_review, urgent, reasons/evidence_status/guidance/
  limitations. track/low-risk and absent reports never mean medical clearance.
  Reuses M1-F2 parsing and ClinicalHomePanel unchanged.
- GET /doctor/review-status: doctor-loop-2.0, patient_id, workflow state,
  latest_sequence, nullable changed_at/by/current_decision and embedded current
  safety. Workflows not_requested/pending/in_review/reviewed/follow_up_needed;
  current decision must be owned, current, patient-visible, clinician_authored
  with valid sequence/state/date. Private latest action never falls back to
  older visible history. Decision may have no recommendation. M1-F2 retains
  independent engine/clinician sources and differing embedded evaluations.
- GET /users/me: owned UserOut full_name/email/id/role/safety_accepted,
  nullable skin_type/selected_goal/profile_context, concerns etc. Reuses
  M1-F1b-2 AccountController identity only; no sensitive data requested for
  personalization. Initial shell still requires server consent and hydration.
  Manual refresh/resume reads account again; while unavailable/loading greeting
  is neutral, and old-account data is cleared. No fabricated policy/onboarding
  version/status.
- Existing /experiments/current and list/read routes remain in ExperimentTab;
  Home uses the owned existing /home summary, opens that tab and adds no new
  experiment HTTP queries. RoutineScreen is already under Products, using
  /routine/entries and /routine/adherence. Product.in_routine is configuration,
  not adherence; this milestone supplies a truthful Products & routines entry
  with no configured/due/completed claim or extra routine read.
- Existing /context/{UTC day} supports nullable unusual_conditions, cycle_day
  1..60 and recorded; retained destination with no expanded questionnaire.
  Existing CapturePanel remains an optional separate quality-check entry within
  the observation flow; no guided-camera redesign or new Capture activity read.

## Existing Home audit and architecture

Previously app_shell Home was one static experimental dashboard. It displayed
legacy delta tiles, a schedule progress bar, a generic completed check-in label
for metric-only /home, two journal rows with decorative light brown thumbnails,
a local-date greeting and a disconnected products link alongside journal.
M1-F2 guidance was already correctly above it. Observation history/report-only
records were not a concise Home source. Home retry refreshed one projection;
resume refreshed only clinical data. No new state-management framework added.

HomeTab now delegates to session-keyed PatientHome with three reusable widgets:
HomePersonalStatus, HomeRecentActivity and the existing ClinicalHomePanel.
HomeNextAction is a small explicit presentation policy. Stable section identities,
order and shell/tab structure remain. Main navigation, auth, clinician panel,
CapturePanel, observation write/uncertainty and existing route names are retained.

Stable hierarchy: verified greeting → Safety/clinician guidance → current tracking
status/reference/experiment schedule → next action → at most two server activity
records → journey buttons → independent refresh feedback. No decorative gallery,
fake AI personalization, due dates, streaks, health grades or completion rings.

## Dynamic card/action rules

1. Any urgent standalone or embedded server warning, including labelled prior
   warning, routes to guidance. It cannot be displaced by positive tracking.
2. Fresh supported patient-visible clinician urgent/review/follow-up action
   routes to clinician details before ordinary routine/history actions.
3. Fresh supported server doctor_review routes to engine guidance.
4. Missing/loading/failed/stale/unsupported safety or review routes to details
   to verify guidance. Missing information never means no safety concerns.
5. An uncertain observation routes to the same guarded M1-F3 flow for review;
   it never offers automatic resubmission.
6. Fresh nonempty owned history routes to the existing history screen.
7. A confirmed existing Home experiment routes to ExperimentTab.
8. Otherwise start observation is available without an invented due/completion
   rule. Fixed observation/history access remains available independently.

This policy selects destinations, not a canonical medical status or AI advice.
ClinicalHomePanel retains F2's source precedence, divergence and stale labels;
urgent engine guidance and lower clinician recommendation both remain visible.
Buttons also route to existing Products & routines, Profile and Context screens.
Context navigation testing found a build-time ChangeNotifier notification: its
initial read now starts after the frame and callbacks/save/late read bind to the
opening session. No context schema/controller/write algorithm was redesigned.

## Observation/activity/progress semantics

Recent activity uses only GET history, first two in server order, stable record
IDs and exact UTC recorded times. It shows reported values as reported, does not
interpret better/same/worse as clinical improvement and does not fabricate event
relationships. Manual values and image estimates have distinct labels; report-only
explicitly has no recorded measurements. Full history stays in one destination.

No optimistic /home override. Confirmed observation now rereads history alongside
Home/baseline and existing clinical refresh. The acknowledged receipt remains
M1-F3-owned even when latest history is unavailable; Home does not insert it into
history or infer today's completion. Uncertain writes retain all F3 safeguards:
no automatic POST retries, content/time match, empty-history proof or fake save.

Current metric-day text refers exactly to /home.today_checked_in. Baseline days
are a separate tracking reference, never report-only completion or medical
progress. Experiment day is schedule without a completion bar. Unsupported or
failed projection is unconfirmed, not zero/false/all-clear. Differing Home/
baseline measurement flags are exposed with their distinct scope and read timing.

## Loading, errors, freshness and session isolation

Resources render independently; Home failure does not erase fresh history,
baseline or clinical guidance. Read-only refresh is pull-to-refresh or button;
read retries are safe. Home 15s, baseline/history 20s bounded controller reads
also cover injected repositories; remote clinical reads retain F2's 20s timeout.
No raw error bodies or sensitive logs are shown.

Refresh marks prior snapshots stale. Home/baseline hide prior facts from current
views; labelled previous clinical/activity records can remain useful. Recorded,
calculated and client retrieval times are distinct; no arbitrary clinical TTL or
server revision is invented. Resume marks all health sections stale and rereads
with profile hydration. Existing F2 profile readback may trigger a clinical
reread; this protects guidance after profile updates. Independent reads cannot
promise an atomic shared snapshot. No new background polling.

Home and baseline now bind request revision and snapshot availability to session
generation. API parsing also rejects changed generation. History already has
owner/session/revision guards and now retrieval metadata/timeout/stale invalidation.
Confirmed metric projection refreshes dispatch together, avoiding a second Home
request accidentally starting after logout while awaiting baseline. Retained
Home action/refresh callbacks cannot navigate/read another session. Account
switch/logout/expiry clears private snapshots, history, receipts and identity;
old 401 cannot invalidate a newer session even with a reused token. In-memory
only: no insecure health cache or new plaintext persistence.

## Design, motion, accessibility

Approved cream/ivory/burgundy and charcoal/graphite/rose tokens remain unchanged.
Removed Home's brown fake thumbnails/light-only colors and tiny header date.
Native buttons/feedback, theme-based surfaces/text, responsive scrollable columns,
semantic live loading/error/status and source text support narrow/large-text use.
Clinical meaning retains explicit icons and words, not color alone. Urgent
panel appears without entrance delays. Actual status height changes use 180ms
AnimatedSize, zero duration with Reduced Motion/accessibility navigation;
primary action uses existing EntryPress feedback. No fake progress percentages.
All owned copy is English; no language switcher/RTL work. Tests validate actual
surface colors, motion durations, semantics and 100%/200% text in both themes at a 320px viewport.
These are widget checks, not physical-device performance/accessibility certification.

## Validation evidence

Final required validation recorded in the completion report: flutter analyze clean;
full flutter test **510 passed** = **444 previous + 66 new**. No old test removed.
Existing Home widget regression is updated for authenticated entry and truthful
metric/status/history wording, preserving stale suppression/real data assertions.
New tests cover: explicit action policy incl unknown/stale/embedded urgent;
primary and fixed route buttons; name/neutral greeting; empty/confirmed/report-only/
manual/image activity; true UTC timestamps/order/two-record bound; projection
schema rejection; partial failures/retry; stale clinical/activity/hidden metrics;
real timeout/late result; 401/403/503; logout/switch/reused-token old 401; overlap;
retained callbacks; UTC baseline day boundary; light/dark/reduced/large text and
source/button semantics. Previous Google/password consent/profile, F2 clinical,
F3 uncertainty/idempotency limitations and all tester tests remain passing.
Test config denies unmocked HTTP; explicit fake transports require
flutter-tests.invalid and synthetic records. No real production/staging/OAuth,
patient/provider tests, release build or deployment performed.

## Changed files (13)

- app/lib/home/home_policy.dart
- app/lib/home/patient_home.dart
- app/lib/home_controller.dart
- app/lib/baseline/baseline_controller.dart
- app/lib/observations/observation_controller.dart
- app/lib/dermaire_state.dart
- app/lib/services/api_service.dart
- app/lib/main.dart
- app/lib/app_shell.dart
- app/test/home_state_integration_test.dart
- app/test/home_authority_test.dart
- app/docs/M1_F4_HOME_STATE_INTEGRATION.md
- app/docs/M1_F4_HUSSAM_HANDOFF.md

Backend/Azure/database/provider/production/tester files untouched. Supported
Home work is complete; B1/B2, consistent freshness and richer activity/provenance
contracts remain backend-owned per M1_F4_HUSSAM_HANDOFF.md. Stop after M1-F4.
