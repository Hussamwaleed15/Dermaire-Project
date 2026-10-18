# F5 — Consented server Agent request broker

2026-10-18. Read actual agent_platform API/schemas/service, context schemas,
model_providers and WAVE_AGENT_COMPARISON_HANDOFF; no inference/provider/native or
backend changes. English-only actual Flutter screens, not a synthetic chatbot.

Patient Profile opens ServerAgentScreen; verified doctor Workspace opens the
clinician request inbox; Agent notifications open the corresponding authorized
workspace. Existing informational Dermaire guide remains separately labeled.

Implemented patient capabilities: explicit independent longitudinal/context and
proposal consent; POST sessions + owned GET readback; server session references
only within current authenticated login; consent scopes, <=1h expiry, tool budget,
context freshness, bounded fact provenance/unknowns/Safety read time and non-atomic
multiple-read label. Context refresh uses actual revision CAS. Current context and
preview expiration update idle UI; session expiry clears displayed private memory.
Saved user turns use exact key and owned history readback; user text cannot invoke
tools and no assistant turn is invented. Backend returns no generated replies.

Allowlisted requests have explicit preview -> separate confirmation -> optional
separate current-original-grant clinician submission with its own consent. Routine
proposals select an actual active routine revision. Notification read selects an
actual owned unread item and requires preview + confirmation. Only that real
nonclinical action can display executed; check-in/follow-up/routine proposals are
requests, never created check-ins/plans/treatment. Backend Safety/digest/freshness
checks remain authoritative. Rejected/stale/conflicting operations never appear
saved. UI shows source rationale as user input and current actual outcome.

Creation/turn/preview preserve exact session-only key/body after uncertain replies;
preview has actual attempt lookup. Confirmation/submission use the server's exact
original CAS/repeat semantics. Every success rereads owned session/actions/history;
original receipts do not replace newer action revisions. Context can reconcile a
newer GET revision without blind POST replay. Unknown is never failure. Different
unresolved operations cannot be substituted; revoking an unrelated session/request
does not discard their original identities.

Doctor inbox reads only actual authorized newest100 requests; exact CAS decisions
and lost-response retry retain original decision/revision. Decision is not clinical
execution. Original patient login, original VIEW grant, one-hour TTL/withdrawal are
server fences, never restored by a new grant/login. No patient identity absent from
the DTO is guessed. Idle request expiry clears the view. Both roles clear private
content on route cover/background/account change/permission loss and reject late
results. No PHI/log/credential/disk history cache.

DELETE session/request withdrawal and memory-erased receipt remain available after
policy loss. A selected known session can be revoked even if it can no longer be
read. API references and pending intents clear at logout/account change. Sessions
are memory-only in Flutter; the backend has no active-session discovery route or
cross-login session-resume contract. No claim of indefinite/restored conversation
memory. Server TTL and explicit erasure still apply.

Verification:35 mocked regressions; pub get; analyzer clean; full1475 (+35).
Cases cover independent scopes, untrusted saved text, proposed vs confirmed vs
executed, exact before/after response loss for session/turn/preview/confirm/submit,
preview attempt lookup, current context reconciliation, routine revision selection,
nonclinical read effect, doctor decision replay,401/403/404/409/410/422/503,
policy withdrawal, late hide/logout/switch, stale server revisions, real-clock idle
expiry and320px/200% consent/active proposal UI in both themes. Test HTTP rejects
all hosts except flutter-tests.invalid. Synthetic state proves neither AI reasoning
nor medical accuracy; no real model, account or device delivery was invoked.

External gaps: no genuine model transport; no list/recovery/revoke-all session
contract across process restart; doctor request DTO lacks patient_id/authorized
patient-context link; request list has no pagination beyond100. These are recorded
for Hussam. Durable privacy-safe operation recovery across process restart and
broader cross-domain navigation/consistency remain F6 work.
