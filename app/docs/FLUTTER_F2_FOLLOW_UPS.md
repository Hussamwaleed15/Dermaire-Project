# F2b — Server clinical follow-ups

2026-10-18; actual backend clinical_plans API/service, wall_time and schemas inspected.

Patient Profile and doctor Workspace now open real `/clinical-plans` lists. An
explicitly selected and freshly authorized doctor/patient connection can propose
a follow-up. Patient can acknowledge or cancel (the API has no separate decline
enum). Doctor can reschedule, cancel and record a real clinician assessment.
Current detail and immutable event history are separate from operation receipts.
Comparison plans display actual references/state; private images/camera/evaluation
remain F4, not implemented or inferred by this change.

Each mutation freezes expected revision/body/key in session memory. Conflicts
require a fresh current read. Timeout/503 preserve the original intent; attempt
lookup precedes explicit retry. Committed historical results require current
readback and never roll newer revisions backwards. Account change/logout clears
memory; covered/background views discard displayed private data and late results.
Doctor creation binds the original grant and rechecks it before posting. API
permissions remain authoritative. No automatic reminders or delivery claims.

Dates use a naive local wall clock, IANA zone and optional explicit DST fold sent
to the real server resolver. Nonexistent/repeated times are validated by the
server. The saved UTC instant, original zone/wall time and device-local display
are distinguished. Travel never rewrites the appointment. Invalid date shapes
and normalized invalid calendar dates are rejected locally.

Regression tests: both roles, creation/original grant, patient acceptance,
rescheduling, exact-key before/after-commit loss, stale revision, historical
receipt/current readback, 401/403/404/409/410/422/503, revocation, late responses
after background/logout/account change, invalid authority and 320px/200% text
in both themes. All HTTP uses flutter-tests.invalid; no live backend calls.

Remaining: cancellation when current safety policy is no longer accepted needs
an explicit withdrawal-only plan adapter/UI; ordinary current-policy cancellation
works. General policy loss hides all current clinical content. F4 comparison
creation/capture/image/review UX and F6 cross-domain navigation remain pending.
