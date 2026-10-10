# Flutter M1-F1a — truthful photo disclosure

11 October 2026 (Africa/Cairo). Implementation plan recorded before source edits.

## Scope and split decision

The first independently testable increment is F1a: replace misleading photo
privacy copy at Welcome and immediately before the optional capture action.
Keep existing capture states, auth, navigation and visual design. F1b will own
the complete server-authoritative entry lifecycle. M1 and F1b are not completed
by this increment; the current local-only Google acceptance remains a P0 gap.

Source baseline: clean Mac checkout main at
`2075d50af8004c72ed7aed13b25cae0bb705f86f`, matching a fresh GitHub main query.
Reviewed the three 20261010 audit/roadmap reports and actual Flutter/backend
sources. Backend was inspected read-only. Implementation/checks run in a
source-only workspace copy; only selected Flutter files/docs return to main.

## Verified contracts

- `POST /api/v1/captures`: selecting a file immediately sends its pixels to the
  server; accepted captures can be stored in private Azure Blob Storage.
  `storage=not_persisted` must remain visible as not stored. Rejected captures
  retain quality metadata, not the image. Accepted results also include
  nonclinical image proxy measurements; the current panel discards those.
- `DELETE /api/v1/users/me`: returns 204 only after account erasure, including
  owned Capture/CheckIn images; failure must not be labelled deletion complete.
  There is no individual-image DELETE route. Do not promise that feature.
- `POST /api/v1/auth/accept-safety`: authenticated body
  `{accepted: true, policy_version: "1.0"}`, response `UserOut`.
  `GET /api/v1/users/me` returns `id`, `role`, `safety_accepted`,
  `safety_accepted_at`, name/email and optional skin profile fields.
  Neither response exposes `safety_policy_version` or onboarding completion.
- Existing password register sends `accept_safety=true`; Google signup saves
  acceptance locally; Google/password sign-in opens the shell without profile
  hydration. Shared ApiService rejects authenticated late responses after token
  change but entry/navigation/profile reads need coordinated lifecycle guards.

## Implementation and verification plan

1. Replace the device-only claim with clear upload, conditional Azure storage
   and account-deletion disclosure. Place the same disclosure before the
   file-selection action. Say selecting a photo starts upload.
2. Correct the panel's contradictory "does not create measurements" statement
   to acknowledge possible nonclinical image estimates without claiming a
   result, diagnosis or stored image. Preserve server storage-state wording.
3. Check Welcome on narrow screens, light/dark, RTL and enlarged text; make
   content scroll if the longer disclosure needs space, without a redesign.
4. Add regression widget coverage for visible disclosure before upload,
   stored/not-stored/rejected/failure states and preserved navigation. Run all
   existing Flutter tests and flutter analyze. No live API/OAuth calls.
5. Configure the unit/widget suite with an isolated `.invalid` API origin and
   initialize the Flutter test binding in every suite so unmocked HTTP receives
   synthetic status 400 without a socket. Prove the rejection in a test.
   Leave the separate production tester entrypoint/harness untouched.
6. Recheck local status and GitHub main, transfer only reviewed Flutter paths,
   make one meaningful commit and push normally. Never force push or overwrite
   concurrent edits. No build, deployment or backend/provider changes.

Risks: longer copy may overflow on narrow/large-text screens; conditional
storage must not imply every upload is saved. Account erasure disclosure refers
to successful server deletion, not a new photo-only operation. This is local
mock verification, not certification of the live Azure/OAuth runtime.

## Actionable handoff for Hussam (read-only findings)

- **P0, needed before version-aware F1b:** expose persisted
  `safety_policy_version` in `UserOut` on both `/auth/accept-safety` and
  `/users/me`, and define the currently required version. Tests: acceptance
  writes the receipt, readback matches account/version, rejected/old receipts
  never imply current acceptance, owner/logout boundaries hold. Current boolean
  acceptance can be integrated without claiming version verification.
- **Entry/profile contract:** clarify how an all-optional profile is considered
  reviewed. An empty PATCH currently leaves no distinguishable completion
  marker. Define an explicit persisted completion field/action so Flutter can
  route new/incomplete users without requiring sensitive optional disclosures.
  Tests: untouched versus reviewed-with-all-fields-omitted, account isolation,
  readback after restart, failed write never completes onboarding.
- **Existing M1 observation blockers, before observation integration:** make
  `/home` count persisted report-only observations separately from metric
  baseline; give `POST /checkins` owner-scoped idempotency (same key/payload
  returns same ID, changed payload conflicts). Keep metric provenance unchanged.

No message was sent externally; this document is the handoff for Amr to share.

## Next Flutter increment

F1b: one coordinated entry controller for password/Google/register, mandatory
server acceptance/readback, typed owner/role/consent/profile hydration, loading
and retry states, and logout/timeout/account-switch/navigation guards. Include
mocked service/widget regressions; do not test real Google OAuth. Resolve the
completion contract above before claiming correct incomplete-profile routing.

## Completion evidence

**Completed F1a:** Welcome and CapturePanel share truthful upload/conditional
Azure storage/account-erasure disclosure. Capture disclosure is before the
photo action. Nonclinical estimates are acknowledged, no individual deletion
feature is promised, and stored/not-stored/failure states remain server-driven.
Welcome now scrolls when content exceeds the viewport, retaining the current
visual design and navigation. No auth/session behavior was changed.

Changed Flutter paths:

- `app/lib/capture/photo_disclosure.dart` (new shared disclosure)
- `app/lib/capture/capture_panel.dart` (pre-upload copy/estimate limitation)
- `app/lib/onboarding_screens.dart` (Welcome disclosure/responsive scroll)
- `app/test/flutter_test_config.dart` (isolated origin/default HTTP denial)
- `app/test/photo_disclosure_test.dart` (10 new service/widget regressions)
- `app/docs/M1_F1A_TRUST_DISCLOSURE.md` (plan, contracts, evidence, handoff)

Fresh local validation, Flutter 3.44.8 / Dart 3.12.2:

- `flutter analyze --no-pub`: no issues found.
- `flutter test --no-pub --reporter expanded`: **164 passed** (154 existing +
  10 new), including existing auth, account deletion, capture and tester mock
  suites. The production tester app was not launched or modified.
- New checks exercise ready/stored/not-stored/rejected/failure disclosures;
  screen rendering must not start an upload; Welcome navigation remains usable
  on 360x640 at 100%/200% text scale in light/dark and LTR/RTL configurations.
- Unmocked requests, including an explicit production URL sentinel, receive
  the test binding's synthetic empty 400 response without network access.
  Existing explicit MockClients operate against `flutter-tests.invalid`.
- Dependencies resolved offline in the copy. The SDK selected matcher 0.12.19,
  meta 1.18.0, test_api 0.7.11 and vector_math 2.2.0. The repository's dependency
  declarations/lockfile are not changed by this increment. This evidence is for
  that resolved local runtime, not an assertion of the production runtime.

**Deferred F1b:** server-authoritative Google/password acceptance and entry
hydration/routing, with timeout/error/account-switch guards. Existing consent
gaps are still open; no claim of corrected acceptance is made. **Backend
contract questions:** policy version readback and explicit optional-profile
completion (handoff above). Report-only Home/idempotency remains backend-owned.

English copy is implemented; RTL layout checks do not mean Arabic translation
or full accessibility certification is complete. No real OAuth, API calls,
Azure/DB/provider changes, build or deployment were performed. No backend files
or production harness files are included in the change. Commit/push identity is
reported separately after Git confirms it; do not claim all M1 is complete.
