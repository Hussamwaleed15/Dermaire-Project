# F6-P source-grounded backlog and execution
Start2026-10-19,745b26ee5224632fe121ccde31d6bd6091d757c7; clean main, official origin
fetch/push verified and fetch matched. Fresh pub get/analyze clean,2021 tests pass.
No native/backend/Tester changes or real calls authorized. Journal remains disabled.

| Feature/source/tests | Actual API / current status | Missing behavior / priority |
|---|---|---|
| Auth/entry/account: onboarding_screens,entry,account; entry/safety/profile tests | /auth + /users/me + completion receipts; DONE bounded contract | Preserve current safety/profile gates and role/session semantics |
| Home: home/patient_home,home_controller; home tests | /home,/baseline,/safety,/checkins; PARTIAL product integration | P1 direct care navigation and visible reliable actions; no fake report-only metric completion |
| Observations/capture: observations,capture; observation/guided/history tests | /checkins,/captures; DONE bounded software / PARTIAL device | P1 restore centered bottom action; keep separate observation/capture provenance |
| Products/routines/experiments: products,routine,experiments; receipt/CAS tests | real keyed mutations and original receipts; PARTIAL integration | Preserve existing related refresh; P1 add actual prospective configuration history |
| Timeline: ObservationHistoryScreen and doctor evidence | /checkins + separate histories; PARTIAL | P1 connect recorded routine history; label cutoff/provenance/unknown legacy evidence |
| Calendar | /routine/calendar-policy exists, no mobile consumer; NOT STARTED | P1 explicit prospective timezone/CAS UI without relabeling UTC adherence or reminders |
| PSM: psm; evidence tests | /psm versioned evidence; PARTIAL | Preserve unavailable model, improve reachable evidence context if source supports |
| Grants: doctor/patient_access,access_invitation; withdrawal tests | actual VIEW/EXPORT and keyed grants; DONE bounded / PARTIAL restart | P3 current grant loss + uncertain identity preservation; no false export support |
| Messaging: messaging; stable-scroll/consent/workflow tests | /messaging enrollment/threads/receipts; PARTIAL connectivity | P2 patient-filtered doctor conversation entry, preserve grant/consent rechecks |
| Plans/comparison: plans,comparison; plan/history/withdrawal tests | /clinical-plans + evaluation/history; PARTIAL | P2 contextual patient plans and refresh after navigation; real model BLOCKED |
| Doctor: doctor_portal,doctor/*; doctor/current/private tests | /doctor/patients + current grant; PARTIAL | P2 current patient contextual messaging, truthful scope feedback, patient-switch tests |
| Notifications: notifications; inbox/reminder tests | /notifications + preferences/reminders/history; PARTIAL | Preserve loaded-only filters; safe targets, no invented thread; delivery BLOCKED |
| Agent: agent/server_agent*; lifecycle tests | real broker/session/action/requests; PARTIAL | current request lifecycle and consent; discovery/pagination/model remain verified contract gaps |
| Account UX: app_shell; entry/privacy tests | no export endpoint; PARTIAL | P1 remove fake export/accessibility success, truthful methodology and real navigation |
| Cross-domain privacy: integration/private_view,controllers,images | current session/original grants; PARTIAL | P3 verify late/denied responses and forms/navigation, preserve only uncertainty identity |
| Secure recovery: recovery + N tests | SQLCipher + product reader isolated; PARTIAL | P4 add real configuration/adherence/clinical readers where source permits, never production activation |
| Connected workflows | existing8 care +4 withdrawal + separate foundation tests; PARTIAL | P6 extend real widget journeys across foundation/care and context switching; no fake E2E claims |

Planned verified increments: patient navigation/trust/accessibility; prospective routine
history/calendar; contextual doctor journey; cross-domain privacy; extra software-only
journal readers; consolidated workflow/UX checks and reverified Hussam handoff. Adjust
from actual failures/source evidence without dropping blocked domains. Every meaningful
increment requires focused/full tests, analyze, diff, normal commit/push/remote check.

P1a DONE bounded navigation/trust increment: central camera action restored without
changing six existing state indices/destinations; semantic tappable labels/tooltips,
icon-only small/large-text navigation and reduced motion. Home connected-care entry
returns through actual server projection refresh and captured-session guards. Account
export/accessibility placeholders replaced by honest data-review and real preference
readback/appearance controls; methodology no longer claims on-device extraction or
available AI. Existing Home test now ensures actual button visibility before tap;
all result assertions retained.10 new regressions, focused81, full2031, analyze clean.
No native/backend/Tester or journal activation changes.

P1b DONE bounded prospective routine evidence/calendar: actual signed-cursor history
and owner/filter/order/provenance validation; current calendar readback + explicitly
approved forward-only IANA-zone change under original CAS. No UTC adherence rewrite
or reminder change. Lost response retains frozen original draft; same-revision
unknown locks replacement, explicit exact original retry only. A fresh higher
calendar revision fences old CAS under the verified account lock; this is NOT an
original receipt. Account-expiry quarantine still has no calendar receipt reader.
Links from Routine, Reports and observation timeline;320px/200% consent resets on
draft change.24 new tests, focused64, full2055, analyzer clean. No native changes.

## P2/P3 — contextual doctor care and grant-loss privacy

- Added patient-specific conversation entry points from patient detail and clinical
  review, alongside the existing patient-specific plans. Current recorded and
  effective scopes are surfaced when returned; VIEW never implies EXPORT.
- Contextual care routes remove their private subtree when selected patient or
  original authorization changes. Conversation/plan list controllers rebind on
  patient prop changes, avoiding cached patient A results in patient B's view.
- Grant loss quarantines raw uncertain clinical intents into minimum original
  identities. A late note/review response can retain a validated result ID but
  cannot restore its narrative or receipt cache. Replacement writes stay blocked.
- Legacy denied-read tests now require this stricter cleanup for 403 as well as
  session loss; 503 retains uncertainty without pretending permission was denied.
- Added five regressions: note/review late replies, context removal, real
  conversation list switch, real plan list switch. All transports deny live hosts.
- This is software privacy/navigation work, not doctor license verification,
  encrypted-journal activation, or a new backend receipt protocol.

## P4 — additional minimum-identity recovery readers

Implemented read-only adapters for actual routine ConfigurationAttempt and
experiment ConfigurationAttempt contracts. Existing parser now accepts minimum
identity directly; no reconstructed payload, replacement key, or generic receipt
interpretation. Routine create/update/stop and experiment create/edit/activate/
finish/cancel/evaluate/legacy-pause paths are explicitly checked. Original owner,
actor, domain, operation, resource, revision, availability and DTO are validated.
Current resources are separate reads; newer/missing rows require review. Activation
and evaluation always require additional related/derived-state review, rather than
claiming the whole intervention/current evaluation is verified from one revision.

The existing in-memory quarantine review UI now exposes those two domains for a
currently authorized patient. Product behavior is preserved. Explicit logout still
purges session memory under the previously approved lifecycle; auth expiry/401
retains minimum identity for the same account. No disk wiring into actual mutations.

Recovery audit of current software:

| Domain | Actual original lookup / guard | Additional disk reader status |
|---|---|---|
| Products | products/attempts or per-resource operation-attempts; owner/revision | Existing product reader, isolated qualification |
| Routine config | routine/configuration-attempts/{operation}/{key}; owner/resource/CAS | Added configuration reader; stop preserves row |
| Experiments | experiments/operation-attempts/{operation}/{key}; experiment CAS + activation Routine-If-Match | Added reader; activation/evaluation related state requires review |
| Adherence | routine/adherence/attempts/{key}; original report/config snapshot | Existing in-session parser; metadata-only reader NOT IMPLEMENTED (exact report fields not in minimum identity) |
| Messaging | messaging/threads/{id}/attempts/{key}; original thread/grant + messaging consent | Existing in-session parser; metadata-only disk adapter NOT IMPLEMENTED |
| Follow-ups/plan changes | clinical-plans/{id}/attempts/{operation}/{key}, creation-attempts/{patient}/{key}; original grant/revision | Existing in-session reconciliation; disk adapter NOT IMPLEMENTED |
| Comparison evaluation/review | clinical-plans/{id}/attempts/evaluate or evaluation_review/{key}; current job/grant/consent | Existing domain controller; disk adapter NOT IMPLEMENTED |
| Doctor grants | keyed issue/revoke supported by actual backend, legacy mobile withdrawal remains local correlation | No new disk adapter; do not label history GET a keyed receipt |
| Doctor notes/reviews | backend keyed route exists; legacy mobile collection reads remain unkeyed | Minimum quarantine only; domain upgrade NOT IMPLEMENTED |
| Agent action/request | agent/sessions/{id}/action-attempts/{key}; known session/login authority; doctor request decisions separate | Existing in-session logic, restart discovery BLOCKED; disk adapter NOT IMPLEMENTED |
| Calendar policy | routine/calendar-policy read + revision CAS only | No keyed receipt exists; pending original review only |

21 new regressions cover both domains, malformed scope/snapshot, unknown/expired/
erased/403, late session response, real SQLCipher close/reopen + coordinator,
original-key preservation/no resend, and actual recovery UI at320px200% boththemes.
Encrypted reopen uses fake platform keys with actual SQLCipher; it is NOT process
termination, native device validation or production activation. Production journal
remains DISABLED/NOT APPROVED; no native changes or protection bypass.

## P5 — notification-to-capture continuity and plan guidance

Patient inbox entry points now carry the current DermaireState into the plan opened
from an authorized notification. This repairs a real missing guided-capture entry:
previously a scheduled comparison reached from inbox had no capture state, while
the same plan reached from the plans list did. Doctor inbox stays role-separated.
The plan is always independently reread; notification source_revision is not promoted
to current plan authority. Added a responsive semantic next-step card using actual
plan state/role, with no elapsed-time completion, diagnostic progress, or inference
claim. Cancellation/review states request no new capture. Existing typed controls,
revision checks, schedules, consent and evaluation workflow remain authoritative.
Six widget workflows verify inbox -> current revision8 despite older notice ->
capture availability/state identity -> logout cleanup,320px200%,both themes. Actual
camera hardware is not invoked or claimed by these navigation tests.
