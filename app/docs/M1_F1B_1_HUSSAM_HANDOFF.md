# Hussam handoff — consent contract follow-up

F1b-1 uses existing routes; no backend change is necessary for boolean receipt
confirmation. These follow-ups are separate backend/product work, not blockers
to that bounded increment:

1. Expose persisted `safety_policy_version` on `UserOut` from both
   `/auth/accept-safety` and `/users/me`; publish required policy version and
   renewal semantics. Verify accepted version/timestamp/account readback and
   outdated receipt behavior. Flutter currently omits the request version,
   relying on the existing backend default; it does not claim version currency.
2. Define persisted onboarding/profile-review completion, distinguishing a new
   untouched profile from a reviewed profile with all optional fields omitted.
   Verify failed writes and account isolation. F1b-2 must not infer completion
   from sensitive optional fields or an empty local flag.

No backend files, resources, providers or production were modified. This file
is a handoff artifact; no external message is implied.
