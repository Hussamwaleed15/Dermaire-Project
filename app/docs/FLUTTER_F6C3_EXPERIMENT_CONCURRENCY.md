# F6c-3 — Experiment revisions and reviewed linked routine

2026-10-18. Verified actual ExperimentOut/lifecycle routes, resource_revisions.py,
experiments.activate and current H2/configuration-attempt contracts. Flutter only.

Plan: consume actual revision metadata, preserve original parent revision for edit,
activate, finish, evaluate and cancel, then add a server-read linked-routine review
before activation. Send both original preconditions; never pick a fresh revision
and silently apply an older intent. Keep legacy records read-only and support
legacy response absence without inventing a version. Test errors, late responses,
actual review UI and private view lifetime before the full verification gate.

ExperimentContract validates revision/revision_protected as a pair when present.
Repository preflight verifies owned/current v2 identity and original definition,
state, revision and protection. Derived coverage can change independently; it is
not used as a substitute for configuration revision. Direct mutations send strong
quoted If-Match from the original server snapshot. Evaluation consumes the actual
parent returned by GET experiment after EvaluationOut; no guessed+1 or promotion
of engine_version/updated_at to a revision. A successful original response is still
separately read back; newer/contradictory content remains unconfirmed.

Real patient activation now GETs the exact linked routine and shows product,
current schedule/status/instructions, intended intervention and planned UTC date.
Only explicit Confirm activation continues. The repository separately checks the
same reviewed configuration, ID/product and actual original revision before POST,
which carries Routine-If-Match alongside experiment If-Match. Missing review on a
versioned experiment, changed routine, wrong linked product or stale parent cannot
activate. Server business/date/permission checks remain authoritative. No clinical
approval, retrospective start, implicit adherence or image-comparison plan appears.

The single-use review clears displayed content and cannot confirm after session
loss, app background or route cover. Returning requires another explicit read and
review; no hidden activation resumes. The enclosing flow ignores late session
responses and checks foreground before opening a review or dispatching activation.
Loading/repeated-tap guards prevent duplicate review requests. Human-readable change
labels and existing theme/accessibility primitives preserve Dermaire identity.

With the linked experiment writer now compatible, routine edit/stop can safely
send original revisions for previously unprotected current-contract rows too.
Successful direct headers permanently opt rows into server protection as designed;
older clients receive428 rather than bypass it. Legacy metadata absence has no CAS
guarantee. Existing UI uses PATCH active:false to stop and POST finish with actual
status to end/cancel; DELETE cancellation is also preserved by repository contract.
Legacy toggle-pause remains unavailable for v2; no new legacy-edit UI was added.

Definite lifecycle rejection requires fresh review, without permanently creating
an uncertain-operation lock. Create failures and timeouts/503/malformed or missing
readback remain uncertain; no automatic retry/new key is issued. Durable committed
receipts and process-restart recovery are still separate pending work. CAS alone
is not an operation receipt and this increment does not claim it is.

35 new mock regressions: malformed/partial metadata, edit/activate/finish/evaluate/
cancel headers, returned revision jumps, changed parent, missing/mismatched/changed
routine,401/403/409/410/412/422/428/503, timeout no double submit, late logout, real
confirmation/decline/changed-after-review, logout/background revocation,320px200%
light/dark rendering and route-cover expiry. All transports reject production hosts.

Final gate: pub get succeeded; analyzer clean; all1625 Flutter tests passed (+35).
