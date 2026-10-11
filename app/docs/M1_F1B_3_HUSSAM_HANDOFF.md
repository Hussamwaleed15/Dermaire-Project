# M1-F1b-3 — Hussam handoff (Flutter entry UX)

No backend change blocks this increment. Flutter still uses the existing
`GET /users/me` and `POST /auth/accept-safety` contracts; their owner/session,
strict boolean, write/readback and timeout semantics are unchanged.

Carry forward the separately owned contract follow-ups from F1b-1/F1b-2:

- Policy currency: expose the server's current safety policy identifier and the
  persisted identifier associated with acceptance, plus the rule for outdated
  acceptance. Publish a sample response and migration behavior for existing
  accounts before Flutter introduces policy-version UI. Flutter currently
  sends only `{"accepted": true}` and does not fabricate a policy version.
- Profile review: define whether an explicit user-reviewed profile marker is
  required. If required, expose its server state, supported write operation,
  and old-account migration semantics. Optional health fields must not be
  treated as mandatory or silently populated. Flutter currently hydrates
  authoritative profile data and makes no onboarding-completed claim.

Expected isolated contract checks: existing accepted accounts with null
acceptance timestamp; owner-matched receipts; absent/false/invalid acceptance;
401/403/5xx; write acknowledged but readback missing/false; old-account migration.

No backend/Azure/database/provider/production/tester changes or live calls were
made during Stage B. This document is a handoff, not a backend implementation.
