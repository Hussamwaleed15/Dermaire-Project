# M1-F4 — actionable Backend handoff for Hussam

Read-only contract inspection against main source
`41511eb4a0b48c6139822ab0150527eea99a7194` on 2026-10-12.
No backend/Azure/database/AI/provider/production/tester edits or live calls.
Supported Flutter Home improvements completed; these gaps do not block the
honest read surfaces. This document is not authorization to change production.

## B1 — separate observation completion from tracking reference (existing P0/P1)

Observed: home.py today_checked_in/journal include confirmed manual/image_proxy
measurements. baseline_snapshot counts qualified unlinked tracking days only.
Report-only source=none is saved by /checkins but appears in neither metric
projection. Home can have true while baseline today flag is false for an
experiment-linked measurement; that is a distinct query scope, not proof of a
missing check-in or broken patient report.

Deliver an owned explicit observation/day projection separate from metric-day
and baseline reference. Define UTC day, qualifying report criteria, saved ID,
calculation as_of and correction/deletion semantics; expose measurement scope
separately. Preserve scores/reference/legacy quarantine. Tests: report-only
save→history→explicit observation projection; no metric/baseline increments;
linked vs unlinked records; null/unknown and day rollover; cross-owner denial.
Flutter currently says saved activity separately and never overrides /home.

## B2 — owner-scoped atomic report-only POST idempotency (existing P0/P1)

Observed checkins.py accepts idempotency_key but applies it only in the photo
branch. Repeat report-only POST can create two records. Empty history or matching
content/time cannot identify an unacknowledged request.

Deliver durable atomic owner+attempt-key+canonical-payload handling. Same owner/
key/payload must return same ID/original recorded time; changed payload must have
defined conflict; different owners isolated. Define optional-field null/omission,
key format, in-flight/lostack behavior, replay/retention/expiry, lookup and account
removal semantics. Tests: concurrent requests, restart/lost acknowledgement,
different payload/owner, expired key and erase/replay. Flutter retains F3 uncertain
write state and no automatic POST retry; no client workaround promises exactly-once.

## Additional observed contracts (nonblocking)

- Freshness/source scope: /home has as_of/date; /baseline lacks server calculation
  time/source-day breakdown; /checkins lacks server as_of/cursor; /safety and
  /review-status may compute independently, including different embedded safety.
  Define stable owned resource revisions/calculation times and explicit scopes
  if consistent combined Home readback is needed. No requirement to create a
  new medical status or duplicate clinical engine. Flutter labels retrieval vs
  evaluation/action times and exposes disagreement rather than merging it.
- Tracking provenance: /home reduces experiment to legacy deltas without engine
  version/source/quality/comparison evidence. v2 deltas are null; legacy deltas
  do not establish clinical improvement. If Home comparisons are desired, expose
  authoritative comparison identity, source, reference/window and limitations
  aligned with existing experiment evaluation. Flutter currently omits the tiles.
- History: GET /checkins is unpaginated descending created_at/id. Add stable
  owner-scoped cursor/by-ID/attempt lookup before a broader activity feed or
  robust idempotency reconciliation. Empty read is not proof of failed write.
- Broader activity/capture links: no shared observation/capture/routine/experiment
  event identity is provided by /home. Add owner-validated explicit links only
  when product scope calls for them; do not infer joins by time/content. F4 uses
  at most two actual observation-history records, not a fabricated unified feed.

Routine configuration/adherence APIs and experiment read/lifecycle APIs already
exist. No missing routine endpoint is alleged, no new adherence contract or AI
recommendation endpoint requested for this Home milestone. No policy-version or
onboarding-completed fields invented. Earlier F1/F2/F3 handoffs remain separate.
