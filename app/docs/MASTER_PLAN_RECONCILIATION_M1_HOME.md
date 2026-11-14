# Master Plan reconciliation and M1 Home observation readback

2026-11-14. Amr A. Abdallah. Scope: Flutter only, no production/provider activation.
Authoritative supplied Master Plan v1.0 (12 November2026) is now retained as
DERMAIRE_PROJECT_MASTER_PLAN_HANDOFF.md, through section20. Unrelated copied
chat/UI text following that document was excluded without changing its wording.
This reconciliation supersedes the earlier missing-document/F9 scope assessment:
the owner has supplied the actual Master Plan and authorized implementation from
its M1–M6 requirements. F-numbers and QA milestones are not product milestones.

## Verified repository and sequencing

Fetched origin successfully before coding. main=b995873f2b76e0c37a08f23fbf40322174aba6fe.
PR6 OPEN at25b0e1f9e04861c98736894d1b31fb02933142cb, base main.
PR7 OPEN at5d855b499f73866ba6894fe67f950e81ec1b6e51, base PR6 branch.
PR8 OPEN ata14cd11185816e18befcb90943563346cec5573f, base PR7 branch.
Dependency inspection confirms the changed Home/clinical/state/test seams are
identical in main and PR8. The delivery branch
codex/flutter-m1-home-observation-readback therefore starts from main at b995873f,
the earliest sufficient base, rather than importing unrelated unmerged F8 work.
PR6/7/8 ancestry and refs remain untouched. The first integration check on the
PR8 stack passed2363 tests; final delivery-base checks are reported separately.
Open PR code counts as implemented source, not merged/deployed software.

## A. M1–M6 traceability

IDs below refer to the actual Master Plan section14 milestone/bullet names,
not invented F9 requirements. Grouped bullets share the cited implementation.
I=implemented/host-tested; Q=implemented but not fully qualified;
P=partial; B=external blocker; U=undecided. None implies clinical/deployment approval.

| Master Plan ID | Requirement | Code/test/contract evidence | Status | Remaining gap | Dependency | Priority |
|---|---|---|---|---|---|---|
| §14 M1 account/session hydration | Current account and profile | entry/account controllers, PatientEntryGate, api_service; entry/profile/session tests | I/Q | Real OAuth/device qualification | Approved environment/device | P0 |
| §14 M1 safety acceptance | Server readback and onboarding/Google | safety_consent_controller, onboarding_screens, users/me and auth/accept-safety; F8 policy tests | I/Q | Approved policy document/rollout | Owner/Hussam | P0 |
| §14 M1 structured observation | Patient report and unknown answers | observations/observation_models/controller/ui; observation_test; backend checkins schemas | P | Richer structured concern/location/onset beyond current report contract | Contract/product scope; notes are not structured fields | P1 |
| §14 M1 report-only vs image/metric baseline | Distinct authoritative completion | backend home.py + schemas/home.py observation_status; **this increment** home_response/HomePersonalStatus; home_observation_status_test | I/Q after increment | Live compatibility qualification | No new API needed | P1 selected |
| §14 M1 Safety/visible clinician | Priority and provenance | clinical_models/controller/ui; HomeNextAction; clinical_status_test/home tests | I/Q | Clinical/device qualification | External | P0 |
| §14 M1 Home authority/freshness | Independent current sources | home_controller, baseline_controller, refreshPatientHome; home_authority/home_state tests | I/Q | No atomic snapshot inferred from separate reads | Existing clinical snapshot separate | P1 |
| §14 M1 image privacy copy | Upload/storage disclosure | entry copy, capture screens; trust disclosure tests/docs | I/Q | Live retention assurance outside Flutter | Hussam/operations | P0 |
| §14 M1 typed models/async | Loading/error/unconfirmed/stale | entry, clinical, observations, home response models/controllers; privacy/error tests | I/Q | Broad qualification not universally complete | Device/E2E | P1 |
| §14 M2 camera/fallback | Live camera or honest upload | NativeCameraPort/CameraSession/GuidedCameraScreen; guided_capture_test | Q | Hardware/performance | F8-6 deferred | P1 |
| §14 M2 quality/permission | Denied/restricted/retake states | camera_session, guided_capture_controller/models; capture quality/session tests | Q | Real permission/runtime matrix | Device | P1 |
| §14 M2 actual measurements | Values/unit/version/provenance | CaptureMeasurement/CaptureProxy/CaptureResult; guided/history tests | I/Q | Clinical validity not asserted | Model/clinical validation | P1 |
| §14 M2 private image access | Authenticated account-bound bytes | private capture image repository/widgets and limits tests | I/Q | Live storage/transport qualification | Backend/device | P0 |
| §14 M2 history/noncomparable | Private records and honest unsupported comparison | capture_history_controller/screen; comparison_domain/controller/ui; private_capture_history_test | P/Q | Real comparison/artifact qualification | Model/artifact contracts | P1 |
| §14 M2 plan-linked comparison readiness | Original plan/grant/source boundaries | plans/plan_controller/models/ui; comparison and F8 integration tests | I/Q | No validated comparison results | Hussam/model/clinical | P1 |
| §14 M3 PSMv2 | Deterministic model projection | psm_models/controller/screen; personal_skin_model_test | I/Q | Live contract qualification | Backend environment | P1 |
| §14 M3 evidence source/freshness | Unknown/partial/provenance | Psm evidence views, clinical/assistance metadata | I/Q | Product-wide device comprehension | Owner/device | P1 |
| §14 M3 assistant metadata/uncertainty | Grounded provider status | assistance/*, chat/*, contextual_chat_test | I/Q | Genuine inference unavailable | Provider/model | P1 |
| §14 M3 safe suggestions | Nonexecuting contextual steps | assistance controller/UI, Agent broker; tests | I/Q | No autonomous medical action | Retain current constraints | P0 |
| §14 M3 clinician decision | Visible original guidance | ClinicalStatusPanel and PSM screen, clinical tests | I/Q | Clinical qualification | External | P0 |
| §14 M3 return after absence | Refresh current facts without inferring nonadherence | main lifecycle/resumePatientHome and stale guards | P | Explicit resumable journey presentation beyond refresh | Owner-bounded future slice | P2 |
| §14 M3 no autonomous tools | Explicit confirmation/allowlist | server_agent_controller/models and wave_agent_test | I/Q | Model inference remains unavailable | Provider/model | P0 |
| §14 M4 daily routine | Real configuration + use reports | routine_controller/ui; m4_routine/routine_authority tests | I/Q | Device/full journey qualification | External | P1 |
| §14 M4 inventory/stable refs | Product ownership != usage | products/*, routine references; product tests | I/Q | Final card style is open | Owner | P2 |
| §14 M4 unknown/skipped | Separate reported states and missing data | routine/adherence models/controller/UI; authority tests | I/Q | No gap inferred from absent records | Preserve | P0 |
| §14 M4 experiment/frozen config | Key/revision/activation boundaries | experiments/*; m4_experiments/wave revision tests | I/Q | Case-specific timing/clinical policy not generalized | Owner/clinician | P1 |
| §14 M4 context/evaluation | Record context and inspect evidence | context_controller, experiments/evaluation; context tests | P/Q | Broader factors constrained by actual schema | Product/Hussam if expanded | P2 |
| §14 M4 insufficiency/association | No causal improvement claim | experiment/PSM/comparison views, authority tests | I/Q | Validated model absent | Scientific/clinical | P0 |
| §14 M5 inbox/preferences | Actual app notification state | inbox_controller/models/ui, F8 CAS tests | I/Q | Push not implied | Preserve | P1 |
| §14 M5 reminder consent/scheduling | Distinct consent/CAS/outbox state | routine reminders and notification settings; wave inbox tests | I/Q | Hosted worker/device delivery | Hussam/provider | P1 |
| §14 M5 device registration | Permission-bound integration | notification_availability and API boundaries | B | Real mobile token/provider setup not authorized | Native/provider/device | P2 |
| §14 M5 real Push | Actual delivery proof | Unavailable provider explicitly surfaced | B | Transport/device proof | Hussam/provider/device | P2 |
| §14 M5 secure cache/drafts | Scoped in-memory views; isolated SQLCipher journal | recovery/*, secure_recovery_session, journal tests | P/B | Production journal composition disabled; device storage qualification | Separate activation/qualification | P0 |
| §14 M5 reconciliation/cleanup | Original identity + current proof | RecoveryReaderCatalog/domain readers; F7/F8 recovery tests | P/Q | Agent/calendar/notification current CAS != independent original receipt | Actual Backend semantics | P0 |
| §14 M6 doctor workspace | Authenticated doctor role | doctor_portal/doctor_controller; m6 workspace tests | I/Q | Professional-license verification not claimed | Owner/clinical process | P0 |
| §14 M6 real connection | Server grants/claim/revoke | patient_access/access_invitation/doctor_connection; grant tests | I/Q | Device QR/deep-link qualification | Device | P0 |
| §14 M6 VIEW/EXPORT | Separate scope/consent | access_control, grant models and connection guards | I/Q | VIEW is never export authority | Preserve | P0 |
| §14 M6 records/notes/review | Original grant/key/CAS + visible/private | doctor_clinical_*, evidence UI, api_service; F8 original-grant tests | I/Q | Live PostgreSQL/clinical workflow qualification not Flutter proof | Hussam/QA | P0 |
| §14 M6 messaging/followup | Authorized current context | messaging/*, plans/*; role/workflow tests | I/Q | Live delivery/E2E | Backend environment | P1 |
| §14 M6 export/report | Controlled export workflow | Account export explains unavailable; scope gating exists | B/P | No verified export-generation contract integrated | Hussam + approved export/retention design | P2 |
| §14 M6 revoke/expiry/audit | Original authority and uncertain identities | doctor_connection, recovery/grant readers, privacy/session tests | I/Q | Full operational audit/device qualification | External | P0 |

Source review confirms earlier NOT IMPLEMENTED entries for domain recovery readers
were superseded by F6-Q/F7; no duplicate reader was added. New F8 code already
addresses original-grant binding/discovery/notification CAS/cancellation. Existing
components establish implementation, not automatic completeness of each product M.

## B. Selected requirement and acceptance

Selected **M1: report-only observation versus measurement/baseline, authoritative
Home** (Master Plan §§7.1,9.1,14 M1). Before this change validateHomeResponse and
HomePersonalStatus ignored the already implemented observation_status field.
Home showed today's confirmed measurements but no authoritative daily observation
completion. Existing history is a separate read and cannot substitute for /home.

Verified Backend (read-only): app/schemas/home.py ObservationStatus/Summary,
app/api/v1/home.py home_projection and tests/test_home_authority.py
test_report_only_completion_is_separate_and_owned. Field exists on main; no
Backend route/schema change or live call is required. Earlier P0 safety/consent
source gaps have bounded implementations; policy activation remains deliberately
blocked. Richer structured observation fields need a separately scoped contract.

Acceptance for this first slice:

1. Show server-confirmed today_completed separately from today_checked_in and
   baseline; report-only never increments a measurement counter.
2. Typed schema1/UTC projection with matching summary kinds/measurement flags,
   valid times/order/unique IDs and internally consistent today status.
3. Missing additive field supports old deployments as unavailable, never false.
   Supplied malformed/unsupported/contradictory data fails Home read closed.
4. Show read time/record provenance; no capture, diagnosis or improvement implied.
5. Loading/stale/failure/new session/disposal cannot show old completion as current;
   refresh recovers only from current valid server data.
6. Existing navigation, Safety priority, themes, large text and reduced motion remain.

## C. Implementation

- home/home_response.dart: typed HomeObservationStatus and Summary, parser validation.
- home_controller.dart: current-only typed observationStatus getter.
- home/patient_home.dart: independent daily observation text and recent server
  summaries inside existing personal-status card, with explicit limits.
- home_observation_status_test.dart: new model/controller/widget coverage.
- home_state_integration_test.dart: preserve existing semantic/theme/navigation
  assertions; expect no AnimatedSize under reduced motion and allow bounded scroll
  discovery across longer 200% text content.

Tests exposed RenderAnimatedSize self-layout mutation when changing this card's
height under zero-duration reduced motion. The card now bypasses AnimatedSize in
that mode, while normal motion retains180ms. No error suppression was added.
Initial fixtures also needed typed Map copies; those were test construction errors,
not a reason to weaken production parsing. All final evidence is recorded at delivery.

No new API, local completion flag, measurement mutation, migration, Backend/native/
Tester/provider edits, live OAuth, production calls or journaling activation.
Malformed observation metadata makes the entire Home projection unavailable;
independent Safety/history sources remain separate. This intentional fail-closed
choice may show unavailable Home on an incompatible server response.

## D. Validation

Final delivery-base results: focused21 passed, related215 passed, full2275
passed (0 failed,0 skipped); analyzer clean. All final commands exited0;
diff-check clean. The separate PR8-stack compatibility run passed2363 tests.
Exact publication SHA/draft PR are recorded in the delivery report. Commands (from app):

```text
flutter test --no-pub test/home_observation_status_test.dart --reporter expanded
flutter test --no-pub test/home_observation_status_test.dart test/home_authority_test.dart test/home_state_integration_test.dart test/observation_test.dart test/clinical_status_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
git diff --check
```

All synthetic HTTP uses invalid-host guards/test binding. No Backend/live/device
qualification is inferred. Baseline counters are asserted unchanged by report-only
completion; session/dispose/superseded replies cannot restore current status.

## E. Five concrete next candidates (not claimed implemented here)

| Candidate | Master Plan | Development vs dependency | Acceptance boundary |
|---|---|---|---|
| Complete Home next-action use of verified daily observation state | M1 §§9.1/14 | Flutter presentation over existing projections; bound ranking by Safety/clinician/uncertainty | A saved historical row must not alone outrank today's incomplete recording; no locally invented due schedule |
| Add structured concern/location/onset beyond notes | M1 §7.1 | Contract/product dependency before fields are implemented | Approved nullable schema, unknowns and server readback; do not smuggle fields into report |
| Add measurement-history trend view | M2 §§7.3/14 | Read-only Flutter over verified capture data; define bounded accessible display without clinical deltas | Units/method/quality/provenance and noncomparable states; no improvement score |
| Explicit return-to-journey presentation after absence | M3 §§8.4/14 | Existing refresh guards implemented; owner-bounded resume rules still needed | Missing days remain unknown; fresh current guidance precedes suggestions |
| Controlled clinician export/report | M6 §§9.5/14 | Backend/export policy dependency, not just a button | Separate EXPORT grant, authenticated generation, revocation/retention and no public URL |

These candidates are backlog evidence/proposals, not approvals of new contracts
or UI design. The next specific coding candidate is the bounded M1 HomeNextAction
presentation correction using the new authoritative observation projection, after
checking its existing ordering cases; it is not an unrelated QA milestone.

## F. Delivery status

The selected Home observation readback slice does not complete all M1 or M1–M6.
Policy, physical devices, model/Push and production qualification remain separate.
No PR is merged or approved, and QA closure remains independent.
