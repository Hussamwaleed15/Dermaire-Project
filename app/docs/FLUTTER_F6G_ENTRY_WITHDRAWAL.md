# F6g-2 — clinician withdrawal at the patient entry gate

Bounded Flutter-only implementation; no production, backend, native or Tester edits.

## Verified contracts and behavior

- `backend/api/deps.py`: safety-policy enforcement explicitly excludes doctor
  revoke/access writes. Withdrawal must not require accepting a new policy.
- `DELETE /doctor/revoke/{patient_id}`: patient/self only, `Idempotency-Key`,
  operation `revoke_all`; revokes active access and pending invitations. Replay
  returns the original result before current grants are examined.
- `GET /doctor/consent-attempts/revoke_all/{key}`: actual schema1 original receipt;
  owner/actor/access all bind to the authenticated patient, operation and original
  snapshot basis are validated. Unknown is not failure; expired is not success.
- No timestamp, revision, current permission list or accepted-policy state invented.

The actual PatientEntryGate Safety screen now links to a withdrawal-only screen.
Explicit scope confirmation is required. This route reads no clinical records or
permission list and never accepts the policy or opens AppShell. The transport
exception permits the narrow revoke/receipt routes only; private GETs and grant
creation remain gated. Existing authenticated-session/role guards still apply.

Lost responses retain the exact key in session memory. Check original precedes
explicit retry, and retry is available only after an unknown lookup. Committed
receipts clear the original pending request but describe only the original
withdrawal; later grants are not automatically withdrawn. Expired receipts keep
replacement locked pending current-permission review in the accepted workspace.
Hide/logout/account switch discard view confirmation/results; late responses
cannot restore them. Logout clears session intents. No restart recovery claimed.

## Files

- `lib/consent/clinician_withdrawal.dart`
- `lib/onboarding_screens.dart`
- `lib/services/api_service.dart`
- `test/wave_entry_withdrawal_test.dart`

## Validation and boundaries

28 new mocked unit/widget tests, synthetic host enforced: scope confirmation,
response loss before/after commit, exact original retry, later grants, invalid
receipt ownership/operation/basis/result, expired, HTTP401/403/404/409/410/422/503,
late responses after hide/logout/switch, doctor-role denial, private-GET denial,
and actual entry navigation at320px/200% in both themes. No backend E2E claim.

Selected individual revocation and plan/evaluation withdrawal after policy loss
remain PARTIAL. This increment is bulk patient withdrawal only. Durable protected
storage and actual Android/iOS runtime verification remain BLOCKED as recorded
in FLUTTER_F6_RECOVERY_CONTRACTS.md. No new backend route is required here.
