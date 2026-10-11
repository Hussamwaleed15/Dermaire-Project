# Hussam handoff — profile hydration contract boundaries

Existing GET `/users/me` and PATCH `/users/skin-profile` return UserOut with
account id, name, email, role and optional profile fields. This is sufficient
for F1b-2 hydration; no new endpoint is required.

1. **Profile review/completion, separate future work:** neither response
   distinguishes never reviewed from intentionally empty. Define a persisted,
   account-bound reviewed/completed receipt and explicit write semantics. Flutter
   needs this only for future completion routing, not displaying empty profiles.
   Tests: untouched versus reviewed-with-all-fields-omitted, same account GET
   readback after login, failed write never completes, cross-owner isolation.
2. **Version-aware consent, separate future work:** UserOut lacks persisted
   safety policy version and required-current-version semantics. Expose both
   with renewal rules; tests for exact account/version/timestamp receipt and old
   receipts. Current Flutter uses boolean confirmation and existing POST default.

No unsupported local completion flags or forced sensitive disclosures are added.
Any real identity/schema inconsistency found during checks will be recorded here.

Source review and mocked checks found no required identity/role mismatch in the
existing contract: TokenResponse `user_id`/`role` map to UserOut `id`/`role`.
Flutter rejects mismatched/absent authoritative identity and offers retry or
sign-in; it never guesses a role. Skin-profile PATCH intentionally excludes
identity fields. Existing registration's generic full_name is preserved; new
identity editing is not part of this increment. No new backend requirement is
introduced by that read-only boundary.

Both items above are nonblocking for profile hydration and should be scheduled
before future completion/version routing. No external message was sent.
