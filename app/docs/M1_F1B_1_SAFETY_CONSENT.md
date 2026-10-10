# M1-F1b-1 — server-authoritative safety consent and session lifecycle

11 October 2026 (Africa/Cairo). Plan recorded before implementation.
Baseline: clean main at `a8327fbfc9c89d304a6529eb1607dfb1d6f753c2`,
matching fresh GitHub main. Reviewed F1a documentation, all three audit reports,
Google/password/register entry, SafetyResponsibilityScreen, ApiService and
session/state tests; backend auth and UserOut inspected read-only.

## Contract and bounded plan

- GET `/users/me` exposes `id`, boolean `safety_accepted`, optional acceptance
  timestamp. Match `id` against the authenticated token response's `user_id`.
  Existing accounts with true acceptance and null timestamps remain supported.
- POST `/auth/accept-safety` takes `accepted`; omit `policy_version` and let the
  existing schema's default apply. A successful POST is only acknowledgement:
  GET readback must confirm true for the same account/session before entry.
- Password registration retains `accept_safety=true` and its existing
  account-created/profile flow, with GET confirmation added. Successful signup
  followed by failed readback must retry readback, not duplicate registration.
- Introduce a patient consent controller and entry gate used by all official
  shell entry paths. No patient shell is built before successful confirmation.
  Keep current UI; errors/loading/retry/sign-out are functional additions only.
- Remove SharedPreferences/local setters as acceptance authority. Keep receipt
  in memory, derived only from validated GET and bound to session generation.
- Add authentication/session generation guards, including delayed login,
  Google picker, consent/write/readback, logout, expiry and account changes.
  Keep tester files/entrypoint untouched; shared service fixes must pass its
  existing mock regressions without introducing a tester consent gate.
- Bound consent reads/writes and auth requests; handle timeout/offline/401/
  403/5xx/malformed/mismatched owner/false readback honestly. Reconcile uncertain
  consent writes with GET before an explicit retry. No sensitive error logs.
- Unit/widget mocks only. All tests retain the `.invalid` API origin and denied
  real HTTP. Run analyzer and full Flutter suite, then reconcile/check main,
  commit only Flutter sources/tests/docs and use normal push. No build/deploy.

F1b-2 profile hydration/completeness, screen redesign, safety assessment, Home,
backend and production tester changes are excluded. This increment verifies
the existing boolean receipt, not policy currency or onboarding completion.

## Risks/tests

Test both Google buttons using an injected token-picker mock, password entry,
registration, old accepted users and legacy local preferences. Exercise retry
after failed readback without re-registering, duplicate taps, pending writes,
false/malformed readback, 401/403/5xx/offline/actual timeout, logout/expiry and
account switches while OAuth/auth/consent requests are pending. Assert no shell
or confirmed receipt before GET and no restored session from late auth results.
Preserve existing auth/deletion/profile/product and tester mock regressions.

## Completion evidence

Completed F1b-1 only. Official password/Google entry now passes through
PatientEntryGate. False server acceptance renders SafetyResponsibilityScreen;
checking/unavailable/ended states cannot render AppShell. Registration keeps its
existing safety-first `accept_safety=true` request and account-created/profile
navigation, but the server receipt must be read before that confirmation UI.
The `onboarding` route argument preserves that existing navigation choice; it
is not a server completion field or persisted onboarding flag.

The acceptance button sends `{"accepted":true}` and waits for owner-matched GET
readback. A POST body claiming true, a legacy preference or a token response
cannot establish acceptance. GET false/missing/malformed/mismatched ownership
keeps entry blocked. Confirmed memory state is scoped to session generation;
logout/expiry/new auth attempt invalidates it. All official shell entry paths,
including existing profile save/skip, use the gate. No profile-completeness
inference or new mandatory health disclosure was introduced.

Auth attempts also carry a generation so unauthenticated late login/register/
Google results cannot revive logout or replace a newer session. Auth and consent
requests have 20-second bounds. Authenticated response guards check generation
as well as token, including synthetic same-token reuse. Main removes old routes
without transition delay, rechecking any rapidly authenticated replacement
session. Google picker results are discarded after session change/disposal.
Consent screens offer sign-out during checking or writing. Retrying an uncertain
write first reads the server; registration readback failure retries only GET.

Changed paths:

- `app/lib/services/api_service.dart` — receipt calls and session/auth guards
- `app/lib/entry/safety_consent_controller.dart` — consent lifecycle/reconciliation
- `app/lib/onboarding_screens.dart` — patient entry gate and consent UI binding
- `app/lib/dermaire_state.dart` — read-only confirmed receipt; local setter removed
- `app/lib/main.dart` — discard routes across logout/expiry/fast account switch
- `app/test/safety_consent_test.dart` — 53 new unit/widget regressions
- `app/test/widget_test.dart` — real-contract fixtures; unauthenticated consent denial
- `app/test/product_authority_test.dart` — consent readback in existing entry fixture
- `app/docs/M1_F1B_1_SAFETY_CONSENT.md` — plan and implementation evidence
- `app/docs/M1_F1B_1_HUSSAM_HANDOFF.md` — separate future contract questions

Fresh Flutter 3.44.8 / Dart 3.12.2 checks in the isolated source-only copy:

- Full `flutter test --no-pub --reporter expanded`: **217 passed** (164 previous
  + 53 new). Existing tester tests passed without changing its source/tests.
- `flutter analyze --no-pub`: **no issues found**, after the final style-only
  test brace repair (no behavior change).
- New cases: both mocked Google buttons/password entry; registration with GET
  failure and no duplicate register; true/null timestamp for older accounts;
  local preference denial; POST acknowledgement/false GET; invalid JSON, owner,
  and bool types; 401/403/503/offline/timeout at GET, POST and readback; duplicate
  taps; reconciliation without duplicate POST; late auth/consent responses after
  logout/account switch; same-token/new-generation; actual 20-second auth/read/
  write timeouts; expiry during GET; sign-out during pending read/write; removal
  of private routes during a fast account switch. No sensitive diagnostics remain.
- New mock transports assert the `.invalid` origin. F1a test config still blocks
  unmocked network, including production-host sentinels. No live OAuth/API calls.
- Offline resolution selected matcher 0.12.19, meta 1.18.0, test_api 0.7.11 and
  vector_math 2.2.0 to match the local SDK, as in F1a. The repository lockfile and
  dependency declarations remain unchanged; evidence applies to this resolved
  local runtime, not the live production dependency set.

Production tester entrypoint/harness/tests were checked byte-for-byte unchanged.
Shared ApiService auth/response lifecycle guards also apply to its existing
requests, but no patient gate was inserted in the tester. No backend, Azure,
database, provider settings, production, build or deployment was changed.

No backend blocker remains for the requested boolean consent gate. Version-aware
renewal and explicit optional-profile completion remain separate backend work
in the Hussam handoff. F1b-2 and other M1 work were not started. Commit/push SHA
is reported after Git confirms it; this is not completion of all M1.
