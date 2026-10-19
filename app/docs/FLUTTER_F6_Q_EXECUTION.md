# F6-Q implementation and acceptance matrix

Start2026-10-19 at1df9822adb9690f2146fc754258f724a1b3b0c19, clean main,
correct official fetch/push, fetch matched. Fresh pub get/analyze clean and2087
isolated tests passed. No backend/native/Tester/live service edits or calls.

| Stream | Current source / verified contract | Acceptance / tests / dependency | Initial status |
|---|---|---|---|
| Q1 clinical | doctorResource local intent + clinical controller collection readback; POST notes/reviews optional Idempotency-Key, GET patients/{patient}/attempts/note-or-review/{key}; backend/services/clinical_attempts.py | Freeze original scope/body/key/sequence; send key; strict original envelope + independent current history; lost replies/duplicate/CAS/grant/newer/current/denial/session tests. Notes and reviews required | NOT STARTED |
| Q2 adherence | routine/adherence/attempts/key; own specific envelope/snapshot | Metadata reader with no raw note restoration; separate current report proof; actual scoped DTO/owner; no replacement | NOT STARTED |
| Q2 messaging | messaging/threads/id/attempts/key and current thread grant/consent | Original thread + actor + original grant checks before/after read; no message restoration from identity | NOT STARTED |
| Q2 plans/comparison | clinical-plans/creation-attempts/patient/key and per-plan attempts/operation/key | Strict plan/job domain snapshots, original grant/revision; current separately; no generic receipt or inference | NOT STARTED |
| Q2 grants | actual consent-attempts and clinical claim attempts | Issue receipt never revives bearer; original grant + current permission; metadata only | NOT STARTED |
| Q2 clinical | same verified clinical envelope as Q1 | Reuse strict parser with minimum identity; recheck current original grant; never restore revoked narrative | NOT STARTED |
| Q2 Agent/notifications | preview keyed action lookup; confirmed request/current CAS semantics; notices read/unread no keyed lookup | Implement only actual original proof; classify unavailable semantics honestly, no synthetic universal endpoint | PARTIAL |
| Q3 uncertainty | current recovery review + domain controllers | Accessible explicit verification/retry-read states; retained identity and locks; no automatic sends | PARTIAL |
| Q4/Q5 journeys | existing care/foundation/domain widgets and workflow fixtures | Connect actual missing actions; broaden patient and selected-patient doctor widget journeys; fake HTTP host denial | PARTIAL |
| Q6 privacy | session-generation + original grant; deny cleanup; SQLCipher isolated | Late/overlapping replies, policy/role/account/grant change; raw data separated from minimum identity | PARTIAL |
| Q7 UX | approved tokens/nav/plan summaries | Improve useful state/loading/error/navigation, themes/textscale/reduced motion; no redesign | PARTIAL |
| Q8 quality/handoff | full2087 baseline; source backend8ad2cea | Focused/full/analyze/diff/scope/normal commit+push per increment; Arabic final report; source-verified Hussam needs | PARTIAL |

Q1 plan: upgrade all notes/reviews POST through existing doctorResource to send a
frozen original key and actual attempt path. Keep compatibility with existing
callers; no raw payload in disk storage. Typed clinical receipt validates
actor/patient/access/operation/resource/timestamps/original snapshot and review
sequence. Refresh can recover a lost original response from actual attempt lookup,
then match current authorized history without replacing a newer decision. Unknown,
expired, erased or contradictory evidence stays locked; verification performs no
POST. Add real verification controls. Existing fake server fixtures must implement
actual envelopes rather than fabricate success from collection membership.

Risk: backend chooses latest current VIEW grant at authorize(), while request
schemas forbid extra fields and expose no original-access precondition. Flutter
checks original current grant and receipt scope; cannot invent a header to eliminate
the initial verify-to-first-write race. Record this exact boundary if verified;
repeated keyed attempts already reject replacement grants. Production journal
remains DISABLED/NOT APPROVED, physical device qualification DEFERRED.

## Q1 — implemented keyed notes and reviews

All doctorResource clinical POSTs now freeze/send the original Idempotency-Key,
actual note/review attempt lookup path and patient/doctor/original-grant scope.
Compatibility map IDs keep their legacy prefix internally; they no longer imply
unkeyed transport. Scope-less convenience callers discover/validate current detail
before freezing; an overlap after that await cannot mint a second pending key.

DoctorClinicalController verifies actual clinical_attempts envelopes and versioned
DTOs, original payload and review expected_sequence+1, with original authorization
rechecked around lookup. Current notes/history remain independent reads. Lost
response can resolve from keyed original receipt; a newer decision stays current.
Unknown/expired/erased/contradictory/current-missing results stay locked. Explicit
verification buttons read only. Grant-loss raw cleanup/minimum quarantine remains.

37 new regressions; focused131 and full2124 pass; analyze clean. Existing fixtures
were upgraded to emit actual clinical schemas and attempt lookup, including routed
connected-care transport. Assertions retained. Fake duplicate-key replay/conflict
checks are isolated contract tests, not backend E2E. No journal activation.

Q1 DONE for real notes/reviews UI keyed integration and tested reconciliation.
Initial-write original-access precondition race remains a precise backend boundary:
POST schemas do not accept access_id or an access-match header; authorize selects
latest current VIEW grant under patient lock. Client validates current/original grant
and receipt scope and refuses mismatches; only backend can atomically require the
reviewed grant on first write. Existing keyed replay already rejects changed grants.

## Q2a/Q3 — clinical and adherence metadata-only review

ClinicalReceiptReader validates the specific clinical envelope/DTO from Q1, checks
original doctor/patient/grant around receipt and current reads, and returns only
resource/sequence metadata. A replacement grant is denied even for the same patient.
Current review must be the original decision; a newer decision requires review,
not replacement with the receipt. Clinical note current proof is authorized immutable
record identity, not restored narrative.

AdherenceReceipt.parseIdentity reuses the actual distinct AdherenceAttemptLookup,
with owner/actor/configuration revision/nested receipt/UTC timestamp validation.
In-session parse still checks exact original body. Metadata reader reconstructs no
note. Current report lookup validates bounded100-row pages (max5000), rejects overlap,
and never treats a bounded offset miss as deletion or new-key permission. Current
routine revision is deliberately separate from the original report configuration.
Neither receipt nor reported completion proves actual product use.

Existing account-scoped review UI now supports doctor clinical and patient adherence
identities; denial says original authorization is unavailable rather than failed
write. Unknown/expired/read errors keep identities and replacement locks. No new
storage fields, raw PHI persistence, native edits or production journal composition.

26 new tests; focused118, full2150, analyze clean. Includes replacement grants,
original/current/newer review distinction, unknown/expired/erased/403/401/503,
malformed adherence scope/snapshot, late session response, real SQLCipher
close/reopen of doctor metadata with fake platform keys, and actual doctor review
UI at320px200% both themes. Host reopen is not process/device security proof.
Q2 overall PARTIAL; messaging/plans/grants/Agent/notification contracts continue.

## Q2b/Q3 — messaging, follow-up and comparison attempt readers

MessageReceiptReader reads current authorized thread pages with bounded cursors,
checks original participant/grant/separate consent, validates actual message attempt
ID/actor/thread/sequence and then reads the exact current message sequence. No message
body is returned/persisted. Missing/replaced/closed original authority fails closed.

PlanReceiptReader uses actual creation and per-plan attempt paths, role-specific
operations, original patient/doctor/grant and expected revision. Plan DTOs, comparison
job DTOs and clinician inference reviews are parsed separately. Original and current
plan revisions are independent; original jobs never become a new current job and
cancelled jobs do not prove active processing consent. New plan intents retain
explicit patient/doctor metadata; old create identities can derive only the scoped
patient route from their actual creation lookup path. No arbitrary image pair,
image score, analysis result, delivery or clearance is generated.

Existing review UI exposes message/plan/comparison receipt checks for both roles.
28 new tests; focused123, full2178, analyze clean. Tests include both-role message
permission/expiry/original-scope checks, plan creation/ack/cancel/reschedule/review,
comparison capture/evaluation/clinician review and current replacement/cancellation,
plus four real retained-message UI variants at320px200% with no body restoration.
No native edits, production mutation wiring, journal activation or automatic send.

## Q2c — patient consent and doctor claim metadata readers

GrantReceiptReader implements the distinct patient GrantAttempt and doctor claim
ClinicalAttempt envelopes. Issue review returns metadata only and never restores
or advertises bearer validity, even when a historical receipt is committed. Selected
withdrawal verifies that original grant separately; bulk withdrawal checks current
permissions independently and cannot claim new later grants were withdrawn.

Claim intents retain a minimum patient routing hint + actual lookup path when the
untrusted code contains a syntactically valid candidate. The hint grants no authority:
server-owned original attempt, actor/patient/original access and fresh current grant
must all validate. No code, QR payload or narrative is restored from metadata. Opaque
codes without a candidate keep the existing safe original-session behavior; no fake
lookup is constructed. Role/session guards and original grant replacement denial hold.

12 new tests; focused118, full2190, analyze clean. Issuance/unavailable/unknown/expired,
claim/replacement, malformed actor/grant, selected/bulk withdrawal and new later grants
are exercised through actual controllers. Existing policy-loss withdrawal tests still
pass without accepting safety terms. Journal activation remains disabled.

Q2 contract audit: Agent action-attempt GET returns CURRENT action_out(row), not an
immutable original preview/confirmation snapshot. Confirm/submit/doctor decision use
current action/session + CAS/exact supported repeats, with no independent original
confirmed-request receipt endpoint. Notifications read/unread/preferences/reminders
likewise have current-state/CAS contracts, not an original attempt lookup. No reader
fabricates such receipts. Comparison evaluation DELETE has current/history evidence
but no keyed cancellation receipt. Calendar is revision-CAS only. These domains stay
explicitly PARTIAL/BLOCKED for independent original proof; existing in-session flows
remain functional. No new backend route is assumed or production setting changed.
