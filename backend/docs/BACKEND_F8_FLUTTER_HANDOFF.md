# Backend F8 → Flutter handoff

Date: 2026-10-24. Backend implementation commit:
`7706c6a76c1947ecf71b5f1a86bcbde3fe224a41`.

F8 changes no HTTP request or response shape. It fixes the Python dependency
declaration behind the existing F7 `Original-Grant-Id` contract and qualifies the
contract against real PostgreSQL concurrency.

## Required Amr integration (unchanged, now PostgreSQL-qualified)

1. Send the page/editor's preserved `Original-Grant-Id` on every first attempt and
   retry of clinical note/review POSTs. A replacement grant must only be used after
   explicitly opening a new context. Treat 403 as loss of the original authority.
2. Require `Original-Grant-Binding: explicit` for the hardened path. The server
   retains `legacy-current` only for backward compatibility during migration.
3. Use `GET /agent/sessions?limit=&before=` for account session discovery and
   `GET /agent/requests?limit=&before=` for doctor paging. Use only returned
   `patient_ref` for navigation.
4. Use notification `target.thread_id`, not message `source_id`, for conversation
   navigation. Re-authorize when opening the target.
5. Send notification `state_revision` as `expected_revision` on read/unread. On
   412, refresh instead of replaying stale device intent.
6. Preserve the evaluation cancellation `Idempotency-Key` and reconcile with
   `/clinical-plans/{plan_id}/attempts/evaluation_cancel/{key}`. The receipt is not
   the current evaluation state.

## Verified server evidence

- 1148 Backend tests passed, including 95 real PostgreSQL cases; zero skips.
- Clinical write/revoke lock ordering, revoked-original/replacement-grant behavior,
  duplicate keys, rollback, Agent isolation, notification CAS, evaluation
  cancellation receipts and migrations were exercised on PostgreSQL 18.
- Migration head remains `20261024_14`; no F8 schema/API migration is required.
- OpenAPI remains 114 paths / 117 schemas.

## External limits Flutter must continue to show honestly

- Agent model: unavailable; do not show generated inference as completed.
- Comparison inference: unavailable without validated artifact/secure image
  transport/clinical validation; no diagnosis or improvement percentage.
- Push: disabled/unconfirmed; provider acceptance, when eventually available,
  still will not by itself prove delivery to a device.
- Historical operation receipt: original committed result only, not current
  authorization/current PHI/current resource state.
