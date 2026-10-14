# H1-B — grant and revocation validation

2026-10-14. Independent tests/documentation milestone after H1-A `094c794f8c2c7ffab32c2e0c991c3fb4327bbbfd`; no new business routes or source changes required by the additional tests. Authorized origin is https://github.com/Hussamwaleed15/Dermaire-Project.git only.

| Acceptance | Actual result / evidence |
|---|---|
| Parallel two-doctor claim after both read pending | SQLite separate sessions/barrier: exactly 200 + 409, unchanged winner binding, exactly one claim audit; `tests/test_doctor_grant_races.py:test_parallel_claimers_cannot_reassign_or_replay` |
| Selected revoke or all revoke commits between claim read and transition | Separate session commits revoke while claim is held at conditional UPDATE: claim 409, revoked status preserved, no claimed_at/doctor reassignment/claim audit; `test_change_committed_during_claim_cannot_be_overwritten` |
| Expiry changes between claim read and transition | Same controlled interleaving: claim 409, no active grant/claim audit |
| Multiple grants with different scopes | Older explicit export grant can authorize export despite newer view-only grant. Revoke explicit export and VIEW remains through the other valid grant, EXPORT/unknown scopes denied; `tests/test_doctor_grant_hardening.py:test_scopes_resolve_eligible_grant_without_broadening_newer_view` |
| Export requires current actor/owner/grant/evidence | Revoked, expired, other clinician, other patient, missing audit and legacy true boolean all 403; `test_export_permission_requires_current_owned_evidence` |
| Patient-owned selected revoke and reliable readback | Other patient 404, doctor 403, repeated owner revoke returns equal timestamp/actor/receipt with one revoke audit; GET matches; token/email/internal session/credential fields absent from denial/receipts; `test_revoke_is_owned_repeatable_and_never_leaks_private_intent` |
| Current doctor identity, not stale JWT role | Logged-out or credential-changed doctor claim 401, role changed to patient 403, pending grant unchanged and no claim audit; `test_claim_checks_current_doctor_identity_not_stale_jwt` |
| Existing clinical authority retained | Full tests retain immutable notes, review expected_sequence 409 CAS, clinician evidence/image checks, safety/private-current decisions, capture idempotency, adherence uniqueness and account erasure |

## Completed local checks

- Focused doctor consent/grant/loop suite: **93 passed, 27 dependency deprecation warnings, 74.10 seconds**.
- Full backend suite: **736 passed, 99 dependency deprecation warnings, 203.89 seconds**. Workspace-only runner invoked pytest with `tests -q --basetemp=../.pytest-h1b-full --tb=short`, set ENVIRONMENT=test and a separate SQLite startup DB, cleared provider credentials/disabled provider flags for the test process, and rejected non-loopback socket connections. No production HTTP, cloud mutation, real account or patient fixture used. Standard reproducible pytest suite command is `python -m pytest tests -q --basetemp=../.pytest-isolated --tb=short` from backend with isolated test environment and no .env/cloud credentials. TestClient calls are local ASGI calls.
- `python -m compileall -q app tests`, `git diff --check`: passed. No configured repo lint/static tool found; no claim of ruff/mypy/etc.
- Existing Alembic upgrade/check on a workspace-only SQLite DB: head `20261008_01`, no new upgrade operations. No H1 DDL or live database migration.
- Source inventory: 18 registered modules, **70 API operations / 53 OpenAPI paths**, confirmed by local `app.openapi()` without HTTP. See `H0_REGISTERED_ROUTES.md` for handlers, locations and response models.

## Verdict and exact limitations

H1-B local grant hardening coverage **DONE**; PostgreSQL runtime/concurrency release gate **BLOCKED locally**. The Docker client exists but its desktop-linux daemon is unavailable; Docker Desktop was not found at its standard installed path and no local PostgreSQL installation directory was found. SQLite conditional-update races are real, but they do not prove PostgreSQL row-lock/deadlock behavior, concurrent clinical writes versus revoke/account deletion, or cloud readiness. No new installations/resources or live credentials were requested or used. Historical October PostgreSQL/Azure drill reports are not current verification.

Before separately authorized rollout, use a disposable PostgreSQL database for simultaneous claim/revoke, note/review/revoke, source-session logout/credential rotation, account deletion, expiry and connection/statement-timeout races. Preserve current patient/grant locks and recheck authorization per request. This is a release gate, not a reason to migrate a live DB or enable Flutter linking now.

Additional retained limitations: no registered export execution API, no global operation receipt lookup/exactly-once claim recovery, no doctor license verification/directory, legacy no-body view-only QR remains a first-authorized-clinician bearer invitation. A clinician can save already-viewed bytes; separate export consent is not DRM. New explicit export requires a selected doctor, and legacy grants cannot prove export consent. Audit consent evidence must be retained for live explicit grants; account deletion scrubs it. Pre-H1 rollback must keep QR generation closed.

## Proposed H2 — do not start without fresh authorization

1. B1: expose report-only observation acknowledgement/today/journal independently from confirmed measurement baseline; add owner/UTC/report-only acceptance cases without synthetic metrics.
2. B2: owner + key + normalized payload hash for report/manual check-ins, conflict 409, persisted result recovery and concurrent same-key deduplication; preserve existing image/capture idempotency.
3. Atomic revisions: expected_version/If-Match for products/routine entries/draft experiment definitions, readback revision and two-stale-edit 409/412 tests; retain current business constraints and clinical review CAS.
4. Shared operation attempt/receipt contract: durable owner/actor/resource/key/payload/revision binding, atomic commit/receipt, queryable committed/rejected/pending/unknown/expired semantics, retention/erasure/restore and lost-response tests. Settle this design before extending it across mutation families.

Notifications, clinician messaging/typed scheduling, safety currency/onboarding, stable history/PSM completeness and Agent execution remain their own future waves. No H2 implementation was started.
