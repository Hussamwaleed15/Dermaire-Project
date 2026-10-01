# Rewards authority: deferred, not redeemable

Rewards was the next divergence after Home at bae2f0a. Products, baseline,
daily context and Home already have dedicated server authority paths.
Rewards is non-core; its catalog had no inventory, fulfillment, clinician
scheduling or entitlement delivery. Implementing a ledger alone would still
promise benefits the product cannot deliver. This milestone quarantines the
program rather than inventing commerce or clinical fulfillment.

## Path map and final behavior

| Path | Previous source | Final authority/behavior |
| --- | --- | --- |
| User model; password/Google signup | Seeded balance of 6 | New accounts start at 0 |
| Internal provision_user | Explicit 0 | Unchanged |
| Product create | Server increments balance | Product persists; no award |
| Product update/delete | No award adjustment | Unchanged |
| Check-in create/list; response schema | +1 on write; constant 1 on reads | No award; tokens_earned is 0 |
| Flutter loadPreferences | check-in count times 2 | Removed |
| Flutter earnToken/tokens | Local mutable balance | Removed |
| Flutter redeemReward/history | Local debit/history; swallowed HTTP error | Removed |
| ApiService redeemReward | Remote write from fake local success | Removed |
| RewardsTab | Hardcoded tiers, prices, progress, free-serum success | Unavailable notice; no financial facts/actions |
| Products add screen | Promised one token | Explicit no redeemable tokens |
| GET /rewards/balance | Seeded User balance, hardcoded catalog | Authenticated 503 REWARDS_UNAVAILABLE; no balance/catalog |
| POST /rewards/redeem | Debit and row without delivery | Authenticated 503; no mutation, even for legacy callers |
| UserOut tokens_balance | Persisted legacy field | Retained for wire compatibility; not a redeemable entitlement |
| Reward schemas/model | Legacy compatibility/storage | Retained; not exposed as active catalog/history |
| Account deletion | User and redemption cleanup | Unchanged and covered by existing tests |

Existing balances and redemption records are retained only as legacy data,
not migrated into validated entitlements or exposed in Rewards. There is no
persistent Flutter rewards cache, request, optimistic write or restart
reconstruction. Offline, server failure, reset and restart cannot display
stale balances, demo tiers or fake success. The unavailable notice describes
the shipped product, so it requires no network request. Authentication still
protects both server endpoints; no rewards work is coupled to session loading.

Before reactivation, define actual fulfillment and eligibility, reconcile
legacy records, add an auditable award ledger and atomic/idempotent redemption,
and expose a validated server projection and confirmed delivery status.
This milestone intentionally stops at Rewards; it does not begin Phase 2.

## Verification

Focused backend tests cover auth, seeded balances, repeated reads/writes,
restart via session expiration, no spending/history mutations, and core writes
without awards. Flutter verifies the unavailable UI across reset/restart with
no progress, redemption action or success. Existing account deletion tests
verify legacy redemption cleanup. Full backend and Flutter suites and analyze
are run alongside git diff --check before committing.

Final local results: backend 115 passed; Flutter 87 passed; Flutter analyze
reported no issues; git diff --check passed.
