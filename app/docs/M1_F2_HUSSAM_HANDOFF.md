# M1-F2 — Hussam handoff

The existing authenticated /safety and patient-only /doctor/review-status routes
support this Flutter increment. No required integration is blocked. Backend,
Azure, DB, providers and Production were not changed or called.

Nonblocking contract needs (not new Flutter assumptions):

1. **Snapshot consistency/freshness.** Standalone /safety and embedded review
   safety are computed independently. Neither gives an atomic shared revision
   or expires_at; the clinician action has no validity/expiry/deadline semantics.
   Decide whether to expose a shared evaluation/as-of revision and freshness
   fields. Flutter currently shows timestamps, distinct sources, previous-read
   labels on failures/resume, and never computes clinical expiry or merges risk.
   Acceptance: two different projections remain distinguishable; current urgent
   guidance cannot disappear because of a lower later read; null/expired fields
   have documented meanings; no fabricated resolution/approval.

2. **Care messaging.** Visible notes/reviews are available, but no care
   conversation/message/attachment endpoint was found. Define authorized patient/
   clinician messaging only if required in a later scope. Include grant/visibility,
   deletion/retention, ownership and attachment contracts. Flutter provides no fake
   doctor chat/contact button or delivery acknowledgement. Current decision null
   (e.g. newest private action) must not be replaced by an older visible decision.
   Acceptance: role/grant/owner denial, revoke/expiry, hidden latest decision,
   null recommendation and complete source/timestamp provenance.

3. **Existing report-only Home/idempotency gap.** Report-only observations still
   do not count as confirmed metric baseline/Home completion, and do not have a
   general deduplicating write contract. Define observation completion separately
   from measurements; add owner-scoped idempotency/reconciliation if required.
   Acceptance: same key/payload returns same observation ID, changed payload
   conflicts; confirmed report-only observation affects observation completion
   but creates no scores/baseline days; timeout retry cannot duplicate records.
   This increment only refreshes clinical projections after acknowledged writes.

4. **Stable published patient DTOs.** /review-status returns an untyped router
   projection; /safety has no response owner identifier (ownership is by JWT).
   Optional typed response schemas/owner and capability/version documentation
   would strengthen future client validation. Preserve safety-1.0/doctor-loop-2.0,
   current nullable meanings and patient_visible filtering. Unknown values must
   remain explicit, never safe/approved. Test old accepted accounts, wrong owner,
   private action, invalid UTC dates, unsupported version and 401/403/5xx.

No decision policy or backend medical/authorization logic is implemented locally.
These are handoff requirements for separately scoped backend work, not permission
to change production or a claim that those changes already exist.
