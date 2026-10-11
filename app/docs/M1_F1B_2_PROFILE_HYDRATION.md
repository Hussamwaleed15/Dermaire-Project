# M1-F1b-2 — authoritative profile hydration and synchronization

Plan recorded before editing. Source main `0218d14bc8f624635ef45a52e9870427256c3dff`,
clean and matching fresh origin/main. Read F1a/F1b-1 docs and the three Flutter
audits; inspected DermaireState, ApiService/session transport, entry/consent,
Google/password/register, ProfileTab, SkinProfileScreen, existing profile,
session and deletion tests. Backend UserOut/SkinContext/SkinProfileUpdate and
users.py inspected read-only.

Existing behavior: token/current-user maps live in ApiService; consent GET saves
a current-user map but entry does not hydrate DermaireState. State defaults to
"Skin Lab User"; preference loading contains an unreachable/unguarded profile
path after memory-session init. SkinProfileScreen separately loads/saves maps
and copies only goal/concerns; identity/role is not synchronized. Session guards
reject old authenticated transport responses, but same-session overlapping
profile requests and editor navigation/drafts need explicit guards.

## Bounded implementation

1. Add a narrow immutable AccountProfile adapter for real UserOut identity/role
   and supported profile fields. Preserve null, omitted, empty and disclosure
   enums; reject malformed identity/owner/role, never infer sensitive fields.
2. Add a ChangeNotifier account controller owned by DermaireState: guarded
   loading/ready/partial/unauthorized/unavailable, server-only values, clear on
   logout/expiry/deletion/account change, latest-request wins within a session.
3. Reuse a protected same-session consent GET snapshot for initial hydration.
   Distinguish it from mutable/currentUser/token/draft data. Integrate the same
   hydration path after consent in every entry flow, before shell/confirmation.
   Failure blocks unverifiable identity without discarding valid consent.
4. ProfileTab and Home read verified identity; show unknown/partial profile
   values honestly. SkinProfileScreen uses the same controller, clears drafts
   on session change, bounds requests and disables concurrent saves. Existing
   PATCH remains the contract, with strict official-account validation and
   explicit confirmed-write versus failed-readback handling.
5. Preserve tester methods/interfaces and harness files. No new persistent
   auth/profile storage, provider access or backend endpoints. No completion or
   policy-version inference. No UI redesign or F1b-3.
6. Mock-only regression coverage for all requested auth, optional-data, session,
   concurrency, update/readback/error cases. Analyze and full Flutter suite;
   check shared main again, copy only reviewed Flutter files/docs, commit/push
   normally and leave clean.

Risks: strict identity checks require contract-correct existing fixtures;
controller/editor/gate notifications must stay outside build; old GET must not
override a newer PATCH or clear a newer session; a confirmed save with failed
readback needs honest feedback rather than an invitation to duplicate writes.

## Implemented lifecycle and completion

**Supported Flutter implementation complete; Git completion is reported after
push verification.** Google/password/register all converge on the existing
consent gate, then AccountController hydration. The owner-matched F1b-1 GET is
copied privately and reused only within the same session/data revision. Initial
entry requires one GET, not a second hydration request. Identity id/role must
match authenticated token-response claims; name/email must have supported types.
Token names, mutable currentUser maps, preferences and editor drafts are not
hydration authority. Invalid identity blocks shell/registration confirmation;
retry fetches a fresh GET while preserving valid safety acceptance.

AccountProfile is a narrow immutable adapter, not a broad model rewrite. It
retains absent/null/empty/unknown optional fields and known context keys without
inference. The `partial` state describes limited shared data and is still ready
for entry; it does not mean incomplete onboarding. Empty profiles are allowed.
Name/email/role and supported profile values reach DermaireState through
read-only getters; ProfileTab displays them and Home uses the verified name.
No hardcoded identity fallback or local profile-completion flag remains.

Session generation plus latest-request revision prevents old reads/writes from
repopulating cleared data, overriding a newer load/PATCH, navigating an invalid
editor, or clearing a newer session with old 401. Logout/deletion/expiry/new auth
invalidate profile state. Editor listeners clear drafts at session change and
never display the replacement account within an old editor route. Disposal also
releases controller profile data. No plaintext profile persistence or AI access
was added; only the existing device theme preference is retained.

Hydration has loading/ready/partial/unauthorized/unavailable states. Loading and
failure do not present previous profile data as a new empty profile. 401 clears
the session; 403/5xx/offline/timeout/contract failure support safe retry. Verified
consent survives non-consent profile failures; a fresh valid server false receipt
invalidates consent and prevents entry. Official GET/PATCH have 20-second bounds.
Messages contain no raw responses, credentials, identifiers or stack traces.

Profile edits use existing PATCH fields. A valid owner/role-matched 200 UserOut
confirms the write; fresh GET reconciles normalized/latest values. Failed PATCH
remains unconfirmed and retains the draft. Confirmed PATCH with failed GET keeps
the acknowledged server profile, labels the latest view unavailable, stays in
the editor and offers refresh instead of a duplicate save. Concurrent saves are
denied; a user making a new edit can explicitly submit a new change.

## Modified Flutter paths

- `app/lib/account/account_profile.dart` — immutable schema adapter
- `app/lib/account/account_controller.dart` — hydration/write/readback lifecycle
- `app/lib/account/account_summary.dart` — actual identity/profile/error display
- `app/lib/services/api_service.dart` — protected consent snapshot, strict official
  GET/PATCH, session/role/revision checks; tester-compatible default APIs retained
- `app/lib/dermaire_state.dart` — authoritative getters and account cleanup
- `app/lib/onboarding_screens.dart` — shared entry hydration and guarded editor
- `app/lib/app_shell.dart` — verified identity/Profile summary, neutral missing name
- `app/test/account_hydration_test.dart` — 46 new contract/controller/widget tests
- `app/test/profile_v2_test.dart` — authenticated profile fixtures
- `app/test/account_deletion_test.dart`, `app/test/session_lifecycle_test.dart` —
  server-backed/read-only identity fixtures rather than mutable local identity
- `app/test/safety_consent_test.dart`, `app/test/widget_test.dart`,
  `app/test/product_authority_test.dart` — full UserOut/token identity fixtures
- `app/docs/M1_F1B_2_PROFILE_HYDRATION.md`,
  `app/docs/M1_F1B_2_HUSSAM_HANDOFF.md` — plan/evidence and future contract gaps

## Fresh verification

Flutter 3.44.8 / Dart 3.12.2 in isolated source-only workspace copy:

- `flutter analyze --no-pub`: **no issues found**.
- Full `flutter test --no-pub --reporter expanded`: **263 passed**, comprising
  217 previous tests and 46 new tests. No tests were removed; prior fixtures were
  made contract-correct and mutable-identity test setup was replaced by server GET.
- New coverage includes mocked Google/password/register parity and one-GET
  hydration; existing/empty/partial/unknown immutable profiles; wrong identity,
  role and types; local/token data denial; logout/login, A-to-B isolation with
  late 200/401/403/503; overlapping requests; expiry/logout during load; actual
  20-second timeout; 401/403/500/503/offline/malformed data and retry; failed
  replacement login; PATCH errors/duplicate denial/late response; old GET versus
  newer PATCH; confirmed write with failed readback and GET-only retry; editor
  draft erasure; displayed server-normalized readback; account deletion; consent
  preservation and a fresh false receipt blocking profile/entry.
- New transports assert `.invalid` origin; existing F1a test binding denies
  unmocked network and its production-host sentinel regression still passes.
  Google tests use injected token-picker mocks, never real OAuth/provider calls.
- Offline SDK-compatible resolution matches F1a/F1b-1: matcher 0.12.19,
  meta 1.18.0, test_api 0.7.11, vector_math 2.2.0. Repository dependencies and
  lockfile are unchanged; this is the tested local runtime, not production E2E.
- Tester entrypoint/harness/readme/tests checked byte-identical; its existing
  mock regressions pass. No patient hydration gate added to tester; original
  getCurrentUser/updateSkinProfile default interfaces remain available unchanged.

## Limitations, boundaries and next increment

No backend blocker for supported hydration; actual GET/PATCH identity/role
schemas are compatible. Identity remains read-only: skin-profile PATCH cannot
edit name/email/role. Existing registration still supplies its existing generic
full_name; hydration displays the server value, never a client-personalized name.
Optional reviewed/completed receipt and policy-version currency remain future
Hussam work, not inferred locally. No medical/sensitive fields are mandatory.

Backend/Azure/database/providers/AI/production and Tester Client files were not
changed; no build/deployment or live API call was performed. F1b-3 was not started.
Next recommended Flutter-only increment is the separately reviewed Entry UX &
Motion milestone, preserving these verified account/consent states. Final commit,
normal push confirmation and clean-tree status are reported in the delivery.
