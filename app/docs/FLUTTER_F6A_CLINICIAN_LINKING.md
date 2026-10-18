# F6a — Restore real scoped patient/doctor entry

2026-10-18. Inspected actual doctor routes, GenerateQr/Claim schemas, grant_attempts,
clinical_attempts and current VIEW authorization; historical H1 handoff is
superseded only where actual source now implements durable attempts.

Patient access management now links to an explicit intended-doctor invitation.
Doctor account ID is provided by the clinician, validated by the server; no
invented directory/license badge. Fixed one-hour issue payload explicitly grants
VIEW and export_consent:false. Pending is not active authority. Original issue
key/body/query are retained on uncertainty and actual consent-attempt lookup
precedes explicit same-key retry. Current owned access list is read separately.
Claimed/revoked/expired original tokens are never restored as usable invitations.
A covered/background view clears displayed bearer code/editors; resume reads its
known issue key only within the same login. Nothing is logged/persisted on disk.

Verified doctor Workspace links to Claim patient invitation. Doctor pastes actual
private code and explicitly acknowledges patient intent. POST uses fixed original
key/code; supported claim-attempt readback uses JWT patient ID solely as untrusted
routing input, never authority. Before first commit, attempt lookup can deny
access; explicit retry may then replay the exact supported keyed POST. Current
patient list must contain the ORIGINAL claimed active scoped grant, actual detail
must authorize that patient, and a final original-grant check follows detail.
A new grant cannot restore an older original claim. No optimistic connected UI.
Uncertain outcomes remain unresolved until actual receipt/current permission.

No QR library/scanner is configured. UI provides an honest copyable single-use
bearer code with manual paste, not a rendered QR placeholder. Patient consent does
not imply messaging consent or export functionality. Existing patient grant view/
revocation remains; typed grant model now exposes real recorded/effective scopes
where provided and preserves explicit unknown for legacy DTOs. Legacy blocked
raw generateDoctorQr/claim helpers stay blocked; only the new verified flow is
exposed. Token expiry/current-session guards, role/owner checks and idle expiry
remain enforced.

Privacy dashboard copy now describes actual stored reports/private accepted
photos and limited nonclinical estimates; it no longer claims configured Azure
Vision/Content Safety clinical analytics or Erythema scores as actual analysis.

Regression coverage32: explicit consent/doctor binding, pending vs active scope,
key/body before/after loss, current original grant, claimed token unavailability,
401/403/404/409/410/422/503, wrong doctor/scope/readback, replacement grants, late
hide/logout/switch and320px/200% patient/doctor forms in both themes. All mocked
HTTP rejects real hosts. No real QR/token/account was used. Native configuration,
backend, production, Tester and provider settings untouched.

F6 continues with snapshot/CAS/recovery/integration work; this is not a claim that
all F6 or complete mobile application work is finished.
