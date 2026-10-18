# F4 — Actual plan-linked comparison

2026-10-18. Verified clinical_plans API/service/schemas, comparison_jobs,
model_providers, doctor timeline, private image authorization, guided capture and
WAVE_AGENT_COMPARISON_HANDOFF. No backend/provider/native changes or live calls.

Doctor Patient detail can propose a comparison only after selecting a real
routine/experiment/check-in and accepted Azure-stored baseline from authorized
patient evidence. Backend validates ownership/source and original VIEW grant;
creation receipt and current plan readback verify source/baseline identity. No
arbitrary pair picker or automatic routine-end scheduling. Follow-up is explicitly
chosen per case with real IANA/fold scheduling, then patient acknowledgment.

Patient can launch existing guided camera from a scheduled comparison. An optional
return action appears only after accepted stored server-confirmed capture; no
unconfirmed/rejected image is returned. Patient separately associates the capture
with the original plan revision. A changed revision requires review/retake. Server
checks original grant, accepted private storage, distinct pair and capture after
acknowledgment. Lost association reconciles exact original key/body/revision.

Both roles see baseline/follow-up via existing bounded decoded-image leases,
without global ImageProvider cache, public URL or disk file. Original plan is
reauthorized before AND after bytes: the image endpoint's acceptance of any fresh
VIEW grant cannot restore an old plan's original authority. Cover/background,
session change, mutation, denied recheck or changed revision disposes leases and
clears displayed content. Image decoding retains existing byte/pixel bounds.

History parses actual regular plan snapshots AND separate evaluation job events.
Jobs/worker transitions increment revisions, so current plan is read separately
before CAS edits. Evaluation POST requires separate explicit processing consent;
202 queued is a request, never completed analysis. Original evaluate attempt
lookup/current job readback handles before/after response loss. DELETE evaluation
uses real revision precondition; current readback follows cancellation.

Actual model boundary is unavailable. Real nonclinical image-quality envelopes,
if returned, require matching pair, artifact SHA/model version and human review.
Doctor inference review is bound to exact job/revision/assessment and is separate
from ordinary clinician plan review. Neither workflow certifies clinical accuracy,
changes treatment, or grants clinical clearance. No score/diagnosis/improvement
percentage is fabricated or inferred from displayed photographs.

Verification: pub get, analyzer clean, full1440 (+22), focused comparison22.
Includes both-role original-plan image checks, foreign pair denial, revocation
while image bytes arrive, late hide/account/revision, exact-key capture and
evaluation loss recovery, cancellation, artifact-bound inference review, mixed
history, server-effective cancellation, accepted/rejected camera return, real
clinician source choices and320px/200% text in both themes. Fixtures reject real
HTTP hosts and synthetic model envelopes establish no model/medical accuracy.

Remaining: in-flight operation identities are session-memory only,
so durable privacy-safe recovery remains F6. Policy-loss plan/evaluation withdrawal
UI still needs an explicit minimal adapter; current-policy cancellation works.
Device runtime not validated (no configured mobile emulator).
