# PHASE 4 COMPLETE — disposable production smoke, 9 October 2026 Cairo

Only authorized disposable synthetic accounts/data were used. Phase 5 did NOT start.
No rollback, source deployment, provider-flag change, infrastructure change, direct
SQL deletion, temporary alert rule, or unrelated user-row inspection was performed.

## Build and fresh safety gate

- Deployed source: `5b5c7b694a4e6e55ff338a72c88e53848e778cc5`.
- Active/complete successful deployment: `36572db2-b7b5-4557-a82c-65caff6201a1`, status 4.
- Worker: `b8d0f702-15e9-4f1c-9499-c400282b7c90`; unchanged from Phase 3.
- Exact Phase 3 built ZIP SHA256: `789749b6b26db786d636098388601bb68d713b93d5026496cb121e0fc6efa813` (historical artifact fingerprint; this phase freshly verified all 119 deployed manifest files, not a new ZIP download).
- Fresh `current_user` and `session_user`: `dermaire_runtime`; revision `20261008_01`.
- Private Blob and required deletion journal healthy; existing 23 signed intents verified.
- Health precheck: live **200**, ready **200**, database/storage/journal available.
- 11 reviewed production-scoped monitoring rules enabled; zero Fired production alerts before smoke.

Precheck: **06:11:20.854330–06:12:26.476497 UTC**, **09:11:20.854330–09:12:26.476497 Cairo**.
Smoke: **06:14:38.422575–06:15:07.821976 UTC**, **09:14:38.422575–09:15:07.821976 Cairo**.
Final monitoring verification began **06:18:51.793089 UTC / 09:18:51.793089 Cairo**;
final live was observed **06:19:18.158173 UTC / 09:19:18.158173 Cairo** and ready
**06:19:18.767228 UTC / 09:19:18.767228 Cairo**. Provider flags/configuration-presence
were independently rechecked unchanged at this final gate. Full request timestamps are in the sanitized evidence.
Smoke run ID: `3e2d0a3f-a31e-4296-b081-3941d19593b1` (synthetic run identifier, not an account ID).

## Registration, authoritative APIs and ownership

Two unique synthetic patient accounts were registered through the real public HTTPS
`POST /api/v1/auth/register`: **201** each. `example.com` identities were used;
the inspected registration path sends no email. Password reset/email delivery was
not invoked. Passwords and tokens existed only in the execution process; no values
were printed, saved in evidence, or passed in command arguments.

Both real login flows returned **200** and tokens resolved to their own profile.
Profile GET, profile PATCH and authoritative Home returned **200**. A profile update
on account A did not appear on B. One minimal synthetic structured check-in returned
**201**, and B's check-in list remained empty. Routine/experiment/product creation
was unnecessary for the minimal account/profile/check-in path and was not performed.

## Assistance and deterministic safety

The preserved configured/enabled contextual provider was invoked once and returned
**200**, metadata `availability=available`, `mode=grounded_ai`; escalation matched
the authoritative Safety Engine. A second request after a synthetic structured urgent
flag returned **200**, `mode=safety_guard`, `reason=safety_precedence`, urgent
escalation, and **provider not invoked**. No personal or real medical data was used.

No clinician records were created in production. Clinician precedence and provider
failure/fail-soft metadata are verified by the selected local synthetic regressions,
not represented as live clinician/provider-failure drills. Provider states remained
contextual AI=true, Azure Vision=false; neither was changed.

## Synthetic image boundary and Blob scope

The runbook does not require a persisted accepted photo for this minimal smoke;
account-deletion end-to-end coverage is used under Phase 4C's conditional scope.
A non-person geometric PNG was submitted to the actual `/captures` endpoint.
The endpoint returned **201** with **state=rejected, storage=not_persisted** and
no image reference, as expected under its face-quality requirement. No detector
was bypassed or patched. Cross-owner capture/image GET returned **404**;
anonymous image GET returned **401**.

**Accepted-image upload, stored-image owner read and image-only deletion intent
were NOT exercised.** No image Blob was created, so no image-only intent was expected.
Account namespace inventory included live/deleted/version/snapshot objects and
was zero before and after each deletion. Private Blob health/policy passed.
This is not a claim of a production accepted-image upload/delete round trip.

## Account deletion, durable journal and denial

Each account was deleted through the real `DELETE /api/v1/users/me` endpoint:
**204**. Each retry with the same prior token returned **204**, without adding
another intent. Subsequent profile and Home access with the prior token returned
**401**. Account B's profile remained **200** after A's deletion and before B's
own intended deletion.

The pre-delete signed inventory contained no intent for either synthetic owner.
Each actual delete created exactly one signed, path-bound **schema 2 account
intent**, with an empty image list because no image was stored. The deployed
account-deletion source was freshly hash-verified against the release manifest:
durable create and exact signed read-back occur before Blob or SQL removal.
Independent post-response signed inventory/read-back and Blob LastModified prove
durability before the successful response. This combines deployed source ordering
with live durable evidence; it is not separate instrumentation of SQL commit time.

| Synthetic label | Intent path SHA256 | Blob LastModified UTC | Delete response completed UTC |
| --- | --- | --- | --- |
| A | `1a39d27431d5a1ba0fe876b2b9df0270b47e25c9ac498abbd4736c28eb00dc2d` | 06:15:02 | 06:15:03.303458 |
| B | `3fed7c802a2690b580b10a606ea4280d42e366a51c2c7c056bb96fe6f95e2da4` | 06:15:05 | 06:15:05.649774 |

Journal inventory increased **23 → 25**. The two synthetic account intents remain
indefinitely under the append-only recovery/legacy retention design; they must not
be removed. Evidence labels them synthetic without publishing HMAC tokens/keys.

## Cleanup and unrelated-data preservation

Ownership-scoped counts after each deletion were **zero** for users and every
owned/linked business model, including check-ins/captures/measurements, products,
experiments, routine/context, doctor access/actions/notes and reward records.
Raw actor audit rows: **zero**. Namespaced Blob copies: **zero**, including
live/deleted/version/snapshot inventory. No synthetic account, live business record,
image or temporary alert rule remains.

As designed, **8 scrubbed pseudonymous synthetic audit rows remain** (A=5, B=3):
empty details, null IP, no original actor ID. These are retained audit history,
not live account fixtures. They were not manually deleted or altered outside the
application deletion path. The two immutable journal intents also remain as above.

All **16 business/audit tables'** unrelated row counts and deterministic aggregate
hashes were calculated inside PostgreSQL and exported only as counts/hashes.
They matched immediately before and after each deletion. No unrelated raw row was
returned or inspected. This proves preservation over the measured deletion window;
it does not claim an independent whole-day change audit.

## Structured logging, monitoring and final health

All **29/29** HTTP smoke request IDs appeared in production structured telemetry.
The scoped query returned only aggregate counters: 35 total structured events,
29 unique request events, **0 unexpected keys, 0 raw email matches,
0 token/body/exception-marker matches, 0 HTTP 5xx**. Two available journal-write
events and one available OpenAI event were observed; OpenAI degraded=0.
No raw log rows/bodies, credentials or unrelated user records were exported.

Final: **11 enabled rules**, **zero Fired production alerts**, **zero temporary
alert rules**. No transient smoke alert fired. Final `/health/live` **200** and
`/health/ready` **200**, database/storage/deletion journal available, same worker.
Rollback/remediation: **not needed and not performed**. Existing Phase 3 narrow
startup margin and uncertified end-to-end RTO <=30m remain unchanged.

## Checks and documentation

Selected isolated local regression suite: **148 passed, 9 existing deprecation
warnings, 9.01s**. It covers account erasure/isolation/idempotency, signed journal,
contextual AI/clinician precedence/fail-soft, Safety Engine and logging/error privacy.
Initial attempt had 146 passes and two temporary-directory fixture permission errors;
the complete selected suite passed after using a workspace temporary directory.
Additional isolated doctor-loop suite: **54 passed**, 19 warnings, 27.49s;
clinician-assistance suite: **9 passed**, 1 warnings, 0.84s.
**211 total regression checks passed** across these completed runs.
No application source changed. Sanitized JSON parsing, documentation diff checks
and secret/raw-data screening passed before the documentation-only main push.
Commit identity/push confirmation is supplied alongside this report after commit creation.

**PHASE 4 COMPLETE. Phase 5 did NOT start and no final traffic/open decision was made.**
