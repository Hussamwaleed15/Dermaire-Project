# Flutter F8-2 to F8-5 integration

Date: 2026-11-13. Developer/publisher: Amr A. Abdallah (`Amr-A-Abdallah`).
Stacked base: `codex/flutter-f8-original-grant` at
`25b0e1f9e04861c98736894d1b31fb02933142cb`, PR #6 still open.
Feature branch: `codex/flutter-f8-2-to-5-integration`.
No Backend commits were merged or imported into this branch.

## Contract revisions

PR #4 remains open at `edf37a5bdba2b5c7be3fffffca05e4edd6109c1c`.
PR #5 remains open at `e1154667d71bc9c909514b911f186afbe6700bb2`.
The auth route and policy_consent service were read from PR5. Main's existing
Agent, notifications, comparison_jobs and clinical_plans source supplies the
F7/F8 additive contracts. Integration/F8/F7/B3/B4-B5 handoffs were inspected
in this task or the preceding recovery/F8-1 work on these unchanged revisions.
The integrated 116 paths/119 schemas/1168 PostgreSQL CI result is historical
server evidence, not a local Backend run or deployment qualification.

## Feature inventory and rollout

| Package | CODED | HOST-TESTED | Remaining deployment/owner gate |
|---|---|---|---|
| F8-2 policy | Typed metadata, exact-byte digest and plaintext display, explicit reviewed version, refresh/review after failure, registration and acceptance integration | Parser/transport integrity and failure cases; existing entry regression preserved | Reviewed document and compatible release required; rollout disabled |
| F8-2 reset | ASCII 8-digit code; email validation; password 8–128; no trimming; generic response and discarded debug fields; bounded HTTP; same-generation session cleanup | Validation/privacy/password preservation plus existing widget/session tests | Real delivery intentionally unverified |
| F8-3 | Typed session summaries, cursor paging, account/role lifecycle; doctor inbox paging and authorized patient reference | Discovery paging/logout; existing Agent regression | Compatible Backend release, no inference provider enabled |
| F8-4 | Trusted conversation target and reauthorization; notification state CAS and 412 readback | New CAS success/conflict/missing revision/target tests plus existing inbox tests | Old servers lacking revision cannot mutate read state |
| F8-5 | Distinct cancellation intent/key, original revision/job/grant, read-only original receipt recovery | Committed/unknown/expired, status failures, late logout, no repeat | No persistence rollout or live worker qualification |

None is BACKEND-INTEGRATION-TESTED, DEVICE-TESTED or DEPLOYED in this task.
F8-6 remains postponed. No new camera/OAuth/native-storage/Push/AI/clinical
validation is claimed.

### Policy document gate

`GET auth/safety-policy` must supply schema_version1, required_version,
document_status, nullable document{url,sha256}, acceptance_ready and
enforcement_enabled. Contradictions/unsupported values fail closed.
HTTPS only, no credentials/fragments/numeric/localhost hosts, redirects disabled,
text/plain UTF-8 only, 256KiB cap, bounded requests/stream and overall verification
time. Hashing precedes decoding; SHA-256 checks the exact downloaded bytes.
Other formats are intentionally unavailable until an approved rendering contract
exists. No invented policy wording is supplied.

`DERMAIRE_VERIFIED_POLICY` is an explicit compile-time rollout switch, false by
default. It must NOT be enabled until the owner supplies the reviewed document,
stable HTTPS reference, digest/version/approval and Hussam confirms compatible
Backend rollout. This preserves the existing server-authoritative onboarding
behavior on the currently deployed legacy service instead of globally imposing
an unapproved-document gate. With the switch enabled, registration and acceptance
require the reviewed document/version; failed acceptance reloads policy and
requires review again. A metadata404 does not bypass the enabled gate.
Google/password flows retain users/me readback and profile hydration. The rollout
UI is coded but has not been qualified with an actual approved document; F8-2
overall remains PARTIAL for release acceptance for this explicit owner dependency.

The document is unauthenticated legal text, never fetched with bearer headers.
Late document responses are scoped to the screen request and session generation;
logout clears retained verification. Download is not acceptance. Existing
withdrawal/logout/deletion routes and independent scopes remain unchanged.

### Password recovery

Forgot-password ignores returned token, note and account-specific message.
The UI says eligible addresses may receive a code, not guaranteed delivery.
Reset preserves password bytes, blocks double submission in UI, never retries
automatically and uses a20s timeout. Failure messages do not expose provider
payloads. Success clears only the session generation that initiated the reset;
a late reset response cannot clear a different newly signed-in account.
Existing session test's synthetic code changed from invalid text to eight digits;
widget assertion changed to the truthful generic copy, without removing checks.

### Agent discovery and clinician navigation

`GET agent/sessions?limit=20&before=` returns metadata only, with
context_included=false and turns_included=false; no turn/context payload is
retained by summaries. Selected sessions are independently re-read through the
existing authorized session controller. Duplicate/nonadvancing pages fail closed.

`GET agent/requests?limit=100&before=` uses next_before. Existing decisions,
consent, expiry and withdrawal remain. Optional patient_ref is accepted only with
authority=current_original_grant and matching result.access_id. Missing ref does
not synthesize navigation. The patient route verifies the referenced grant again,
then may open the existing clinician record with expectedGrant pinned. A replacement
grant cannot open that request's patient record. Models remain unavailable.

### Notifications

Message target must have type=conversation, authority=current_server_authorized,
matching message_id and a valid thread_id. The thread is fetched and participant
authorization parsed before opening CareConversationScreen; no source_id is
used as a thread. Legacy/missing target opens only the independently authorized
conversation list. No locally fabricated private target is inferred.

`PUT notifications/{id}/read|unread?expected_revision=state_revision` uses the
loaded row's revision and single in-flight mutation. Missing revision blocks the
action. A412 triggers GET refresh/history without another PUT. Malformed/denied
readback cannot restore a successful mutation claim. Preference/reminder CAS is
separate and unchanged. App read status never proves Push delivery.

### Evaluation cancellation

`DELETE clinical-plans/{id}/evaluation?expected_revision=N` sends the distinct
preserved Idempotency-Key. Pending identity includes original patient, grant,
job and revision; all subsequent plan mutations are blocked while unresolved.
`GET clinical-plans/{id}/attempts/evaluation_cancel/{key}` reconciles that key.
Committed result must parse as a cancelled envelope for the original job;
fresh authorized current plan/evaluation are read separately. Unknown/expired/
erased/invalid/denied evidence retains the intent and never generates a new key.
HTTP403/404/409/410/412/503 and timeout do not manufacture cancellation success.
No automatic replay. Session cleanup fences late responses; no private payload
is restored into a stale controller. Historical receipt != current job state.

## Test evidence and review boundaries

New synthetic tests: f8_policy_recovery_test.dart and
f8_integration_contracts_test.dart. Existing F8-1/F6/F7/Agent/inbox/comparison/
entry and privacy tests remain. Fixtures model server revisions explicitly.
No test HTTP against Production/Staging, real OAuth/email/Push/model/patient data.
Final exact counts, commits and PR URL are provided in the delivery report.

Hussam/owner action: reviewed policy/rendering approval and compatible Backend
release/capability decision; no missing endpoint is falsely reported for these
already implemented contracts. Real Agent inference, comparison validation and
Push require their own external qualification. F8-6 hardware is postponed.
Independent review should especially inspect opt-in policy rollout and the
distinction between receipt history and current authorization. No automatic merge.
