# F6-Q current handoff to Hussam — 2026-10-20

Source inspected again after Flutter integration; backend last change remains
`8ad2ceafced5b1f06ade5a082d4939503d31c687`. No live requests/backend execution.
This table supersedes historical mobile-integration blockers below. Keyed doctor
notes/reviews and metadata-only readers for all supported requested domains are
now implemented in Flutter. Existing APIs must not be recreated.

| Priority | Actual endpoint / current behavior | Required contract and acceptance criteria | Flutter / privacy impact |
|---|---|---|---|
| P0 before safe replacement recovery | Product/configuration/clinical and other attempt GETs expose committed/unknown/expired; unknown is not terminal rejection or an in-flight fence | Define authenticated operation reservation/in-flight/terminal rejection/fencing and retention. A delayed original after unknown must not allow a second replacement commit. Test wrong owner, expiry and concurrent original/replacement | Flutter keeps original identity and blocks automatic new keys; cannot infer failure from unknown or503 |
| P1 original clinical grant precondition | POST /doctor/patients/{patient}/notes and /reviews call doctor_loop.authorize(), selecting latest active VIEW grant under patient lock. ClinicalNoteCreate/ReviewActionCreate forbid extra fields and expose no original access precondition | Add an explicit documented first-write original-access precondition, validated atomically under the same lock before mutation. Test original A replaced by B between Flutter verify and POST: reject, no new note/review; same-key old-grant replay remains rejected; review expected_sequence CAS preserved | Flutter freezes/checks original grant before write and validates receipt afterward, but cannot make initial verify-to-POST atomic or invent a header. Keyed replay already exists; this asks only for initial original-grant binding |
| P1 if restart recovery required | GET /agent/sessions/{id} requires known ID/original login/TTL; no session discovery/revoke-all | Authenticated minimum discovery and explicit bulk revocation; define cross-login/TTL/owner/original-grant semantics, test revoked/replaced contexts | No stored private session payload or guessed session identifiers |
| P1 completeness/context | GET /agent/requests is limited to100; action_out lacks explicit authorized patient target | Stable authorized cursor + patient reference bound to original grant/session; test>100 rows, revoked and replacement grants | Flutter cannot claim complete inbox/history or infer patient navigation |
| P1 independent original Agent proof | GET /agent/sessions/{session}/action-attempts/{key} returns action_out(row), the mutable CURRENT action. Confirm/submit/doctor decision use current action + CAS/repeat semantics | If independent recovery is required, specify immutable original preview/confirmation/request receipt, operation/actor/session/original grant/revision and retention; test later decisions/changes without rewriting original proof | Existing current-state flows work. A current action is not an original committed confirmation receipt; generic recovery reader deliberately unavailable |
| P1 trusted notification target | GET /notifications exposes message source_id, without authorized thread resolver | Return authorized thread_id or resolver checking current participant/original consent; test revoked/closed/wrong owner | Flutter opens current conversation list and never guesses private thread |
| P1 if cross-device ordering required | PUT /notifications/{id}/read and /unread have no CAS/attempt fencing; preferences/reminders use current CAS | Define monotonic ordered version/CAS and original-operation semantics where required; reversed device writes must have deterministic result | Local serialization cannot prove global ordering; current reads are not original receipts |
| P2 if independent cancellation proof required | DELETE /clinical-plans/{id}/evaluation?expected_revision=N has current/history evidence, no keyed cancellation attempt | Document keyed original cancellation receipt/revision semantics before metadata-only original recovery is expected; test late cancel/newer job/role/grant loss | Existing cancellation remains available; no new key or fake receipt invented. Calendar revision-CAS has the same current-vs-original distinction |
| External reviewed model work | services/model_providers.py: DisabledComparisonProvider; Agent DisabledAgentModel | Reviewed genuine model/private image transport + clinical validation and unavailable behavior | No diagnosis, invented scores, model result or medical clearance |
| External provider + later mobile approval | POST /notifications/devices already exists; services/notifications.py DisabledPushProvider | Reviewed provider/token transport and actual device delivery/revocation/quiet hours validation | Registration/provider acceptance is not delivered Push. No native/provider setup changed |

Already present and consumed: keyed clinical notes/reviews; adherence; product/routine/
experiment receipts; message attempts with original thread consent; follow-up create/
reschedule/ack/cancel/review/capture; plan evaluation/review receipts; grant issue/
revoke/revoke_all and claim. Q2 readers never restore bearer codes, message bodies,
clinical narratives or revoked authority from journal metadata.

These requests are a written handoff only, not permission to edit Backend/Azure/DB
or activate production journaling. No automatic message was sent to Hussam.
Physical device qualification and production activation remain separately deferred.

---

# F6-P reverified handoff to Hussam —2026-10-19

Source verification only. Last backend change remains
8ad2ceafced5b1f06ade5a082d4939503d31c687. No live calls or backend/provider edits.
The earlier detailed ledger below remains historical context; this concise current
table states work actually needed from Hussam.

| Priority / owner | Existing endpoint / exact source | Current behavior and missing contract | Flutter/safety consequence and acceptance requirement |
|---|---|---|---|
| P0 / Hussam | Product/configuration attempt GETs; services/configuration_attempts.py and product_attempts.py | Committed/unknown/expired only; unknown does not fence an earlier in-flight write | To permit safe replacement, define owner-bound terminal rejection/in-flight reservation/fencing and retention. Test delayed original commit after unknown. Flutter preserves original uncertainty, does not auto re-key |
| P1 / Hussam | GET /agent/sessions/{session_id}; api/v1/agent_platform.py | Requires known ID/original login/TTL; no minimal discovery or revoke-all | If restart discovery is required, return authenticated scoped metadata, define cross-login/revocation explicitly. Test wrong owner/login/expired/revoked and replacement grant; no revived context authority |
| P1 / Hussam | GET /agent/requests; service.action_out | Hard limit100; no cursor; action output has no explicit authorized patient target | Add stable authorized cursor + patient reference bound to original grant/session. Test>100/revoked cases. Flutter cannot claim completeness or guess patient navigation |
| P1 / Hussam | GET /notifications; api/v1/notifications.py | Message notice source_id identifies a message; no trusted thread target/resolver | Add authorized thread_id or target resolver with current membership/original consent checks. Flutter opens current conversation list; no guessed thread/private text in push |
| P1 if ordered edits required / Hussam | PUT /notifications/{id}/read and /unread | No revision/CAS/attempt fencing | Define monotonic version/current-state and original-operation semantics; test reversed cross-device writes. Local serialization does not prove global ordering |
| External / Hussam with reviewed provider setup | services/model_providers.py | Agent provider unavailable; DisabledComparisonProvider; no validated live inference transport/artifact | Provide reviewed provider/model/image transport and clinical validation independently. Flutter must keep real unavailable states and never invent diagnostic/assistant results |
| External / Hussam + later mobile/device approval | POST /notifications/devices exists; services/notifications.py DisabledPushProvider | Registration API exists; real mobile token transport/provider/device delivery unverified | Agree real provider and transport separately; test actual delivery/revocation/quiet hours on devices. No duplicate registration API request; provider accepted is not delivered |

Already implemented and **not new backend requests**: routine configuration history
and calendar policy (now consumed by Flutter), product/routine/experiment receipts,
messaging/consent, follow-up scheduling and original receipts, clinical-plan immutable
history including evaluation snapshots, keyed grant and optional doctor note/review
attempts. The older mobile notes/reviews path still needs Flutter keyed integration;
metadata-only journal adapters for adherence/messaging/plans/etc. are Flutter software
work, not missing endpoints. Calendar policy is CAS-only; no receipt was fabricated.

These are contract requests, not authorization to change Azure/database/providers.
Production journal activation and deferred physical device qualification remain Amr's
separate rollout boundary, not something to solve by weakening server authorization.

---

# Verified backend/external boundaries — integration wave2026-10-18

Source8ad2ceafced5b1f06ade5a082d4939503d31c687. Amr edits app/ only.
Historical M4–M6 'missing messaging/consent/scheduling/notifications/Agent' reports
are superseded by real source contracts. Do not recreate those implemented APIs.

- BLOCKED external: genuine push provider/mobile token transport/configuration,
  hosted worker/scheduler and actual device delivery proof. Default provider disabled;
  provider_accepted is not delivered. No credentials/native/provider edits authorized.
- BLOCKED external: validated comparison model artifact/loading/private model image
  transport/clinical validation, and genuine constrained Agent inference transport.
  Backend local broker/job lifecycle is usable independently, not medical inference.
- OPEN actual source: durable committed receipts do not prove rejected/in-flight
  attempts. Unknown cannot permit a new key. General rejected/in-flight registry,
  doctor Agent inbox pagination beyond100 and complete all-domain historic MVCC
  reconstruction remain open in the latest backend ledger.
- Product/server contract for future unauthenticated safety-policy publication:
  register/accept requests have a legacy1.0 default; authenticated GET /users/me
  supplies required_version/current state, but a public versioned policy text
  publication contract is absent. Flutter uses server metadata after login and
  explicit user acceptance; it does not fabricate changed policy text/version.

No live backend/DB/provider verification or deployment performed. Additional gaps
will be added only after source verification during implementation.

## F3 verified boundaries
- Message notification source_id is a message ID without thread_id or a resolution route. Add an authorized thread/deep-link reference to avoid requiring manual conversation selection. Flutter currently opens authorized conversations honestly.
- Read/unread has no revision/attempt identity: cross-device/late-write ordering cannot be proven. If ordered edits are required, add CAS plus current-state/attempt semantics.
- Push provider remains disabled and mobile token configuration is absent. No fake registration. Confirm provider/token/plugin plan separately; no configuration changed.

## F5 verified contract needs
- Agent session GET needs a known ID; there is no active-session list/discovery or revoke-all endpoint. Flutter intentionally does not persist PHI/auth sessions. Add authenticated minimal session discovery + explicit bulk revocation if process-restart recovery is required; define original-login/TTL behavior without reviving old authority.
- Doctor Agent request responses omit patient_id, so Flutter cannot safely link a request to authorized patient context. Add an authorized patient reference/deep link (still bound to original session/grant).
- Doctor request inbox is bounded to100 with no cursor. Add authorized pagination before claiming complete historical request retrieval.
- Model/provider transport remains unavailable. Flutter displays real broker outcomes, not generated assistant replies or autonomous clinical actions.

## Continuation source recheck and actionable priority

Rechecked during F6 continuation from3efe4b5/cdfc8da against current registered
agent_platform/notifications routes, action_out DTO, model_providers and disabled
notification provider. No backend edits or live calls. Existing foundation
product/routine/experiment committed receipt APIs are implemented: they are NOT
backend blockers, and Flutter is now consuming them.

| Priority / endpoint | Verified limitation | Required contract / Flutter consequence |
|---|---|---|
| P0 recovery: foundation attempt GET routes and current domain services | Only committed/unknown/expired; missing row does not fence an earlier in-flight request | If definitive abandonment/replacement is required, design owner-bound server reservation/fencing or terminal rejection semantics. Flutter cannot safely equate unknown with failed or issue a replacement key; current exact replay/unknown lock remains intentional |
| P1 Agent: GET /agent/sessions/{id}, no list route | Known ID and original login/TTL required; no restart discovery or revoke-all | Authenticated minimal scoped discovery plus explicit revocation, defining cross-login behavior without reviving authority; otherwise restart session restoration remains unavailable |
| P1 Doctor Agent: GET /agent/requests and action_out | Newest100 only, no cursor and no patient_id/authorized patient link in output | Add authorized patient reference and cursor. Bind to original session/grant; Flutter otherwise opens no guessed patient context and cannot claim complete history |
| P1 Messaging notice: GET /notifications item | source_id is a message ID; no authorized thread reference | Add thread_id or authenticated resolution, with current original consent/grant recheck. Flutter currently opens authorized conversation list, not an invented direct thread |
| P1 read ordering: PUT /notifications/{id}/read and /unread | No version or attempt identity | If cross-device ordering is required, add CAS/current-state/attempt semantics; UI serialization alone cannot guarantee remote ordering |
| External: provider/model adapters | DisabledPushProvider, unavailable Agent inference and unvalidated comparison artifact/transport remain | Supply reviewed provider/model setup and real device/clinical evidence separately; no frontend synthetic delivery, response or diagnosis |

Secure local restart storage and unavailable mobile emulators are Flutter/platform
constraints documented in FLUTTER_F6_RECOVERY_CONTRACTS.md, not new API tasks for
Hussam. No claim that unknown is rejected, that a new VIEW grant restores an old
request, or that reviewed synthetic output establishes clinical validation.

## F6g-2 withdrawal contract recheck

Actual deps safety exceptions and doctor revoke/consent-attempts routes already
support patient bulk withdrawal before current safety acceptance. Flutter now
consumes them at the real entry gate; no backend work is requested for that flow.
Original committed/expired receipts describe the original operation only, not
new grants or the current permission list. General unknown/rejected/in-flight
limitations and Agent/provider requirements above remain distinct.

## F6-L source recheck —2026-10-18

At dc24dfc, rechecked current registered doctor/clinical_plans/agent_platform/
notifications APIs and services. Selective revoke/list and patient plan cancellation
already exist, including policy-loss exceptions and original receipts; implemented
in Flutter, not backend requests. Patient cancellation does not require restoring a
revoked clinician grant; doctor plan access still requires its original grant.
Evaluation DELETE has CAS/current-job semantics, not a synthetic keyed receipt.

Existing P0/P1 table remains current: Agent GET session needs a known ID (no list),
action_out omits patient identity, doctor inbox bounded100/no cursor; notification
read/unread lacks CAS/attempt and message notice lacks thread context; model provider
still returns unavailable and push provider is not proof of delivery. Required
contracts/security impact/priorities are listed above; no already implemented APIs
are requested again. Durable local storage/native runtime are Flutter/platform
constraints, not additional backend tasks. No live backend verification performed.

## F6-M closing handoff — source reverified2026-10-18

Actual backend tree last changed at8ad2ceafced5b1f06ade5a082d4939503d31c687;
Flutter wave started at a93ab02. Source verification only; no live backend/DB test.
Existing detailed requirements above remain authoritative; concise actionable list:

| Priority | Existing route / observed source | Required contract / acceptance test |
|---|---|---|
| P1 | GET /agent/sessions/{session_id}; no list/discovery | Authenticated minimal session discovery with original-login/TTL/revocation rules. Returning metadata must not revive an old context/session after reauthentication. Test wrong owner, expired/revoked sessions and replacement grants. Flutter currently states discovery unavailable. |
| P1 | GET /agent/requests orders and limits100; no cursor; action projection omits an authorized patient reference | Stable authorized pagination and explicit authorized patient_id/target tied to original grant/session. Test>100 requests, cursor boundaries and revoked grants. Flutter cannot safely infer a patient or completeness. |
| P1 | GET /notifications message source_id is a message ID; no thread target/resolver | Add an authorized thread reference or authorized target resolver. Verify membership/consent again on navigation; never encode clinical text for lock-screen display. Flutter opens current authorized conversations. |
| P1 | PUT /notifications/{id}/read and /unread have no revision/attempt fence | If cross-device ordering is required, supply monotonic server revision/CAS and original operation semantics; test reversed/late concurrent read/unread. Flutter makes no global ordering/delivery claim. |
| P0 recovery boundary | Product/configuration/etc. receipt lookup returns unknown without durable rejected/in-flight proof | Define authoritative in-flight/rejected states and safe retention/replacement rules if replacement is to be unlocked. Unknown is not evidence a prior write cannot still commit. Test delayed original commits after unknown lookup. Flutter retains locks and never re-keys automatically. |

**Historical evaluation is not a missing endpoint.** GET /clinical-plans/{plan_id}/history
already returns ordered immutable events, including evaluation-job snapshots and
next_after_revision. Flutter now consumes that actual contract, with original/latest
job identities separate and bounded metadata. DELETE /clinical-plans/{id}/evaluation
still has no keyed cancellation receipt; current/history proof must not be described
as one. No additional history endpoint requested.

POST /notifications/devices already exists. Real mobile token transport/provider
configuration/actual delivery and validated comparison/Agent model remain external
capability gates owned with Hussam; no fake device or provider success added.
Legacy doctor note/review APIs also already support optional keyed attempts in the
source. Current older Flutter write path still uses local uncertainty correlation;
fully adopting those keyed receipts is Flutter integration work, not a request to
reimplement the API. Do not weaken original-grant authorization to recover old data.

Secure local journal/native key integration and Android SDK setup are Flutter/platform
approval/runtime constraints, not Azure/DB work for Hussam. No backend, provider,
production, database or Tester file changed by this wave.
