# Phase 3 account audit isolation correction — 9 October 2026

Final source review after the initial 6a9c13f deployment found a reproducible
unrelated-audit erasure gap. delete_account matched the user's full name and other
identifiers against serialized JSON, including keys and partial values. A user
named `id` could therefore clear another actor's `product_id` audit details.
Similarly, a stable identifier in a JSON key or only as a prefix caused false matches.

Normal traffic was promptly reclosed. No real deletion was invoked to prove this;
two synthetic SQLite regressions fail on the earlier source and pass after correction.
Matching now examines string values recursively, ignores JSON keys, uses bounded
stable subject/owned-record identifiers and the unique email, and does not infer
ownership from a nonunique full name. Current audit writers either use the subject
as actor or include stable patient/product/action references; related legacy free-text
identifier values are still scrubbed. Other actors' unrelated audit payloads remain.
Account intent persistence ordering, replay source immutability, v2/v3 wire formats,
provider states, DB schema and infrastructure requirements are unchanged.

Fresh full backend suite on the correction: **697 passed**, 91 existing warnings,
89.12s. The corrected package must replace the initial artifact before the final
Phase 3 exit gate and normal traffic are restored. Do not use 6a9c13f as the final
unrestricted-write rollback artifact. Phase 4 has not started.
