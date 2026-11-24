# Flutter F8-1 — original clinical grant binding

2026-11-13. Developer: Amr A. Abdallah. Base main:
`b995873f2b76e0c37a08f23fbf40322174aba6fe`.

## Contract and implementation

Backend `app/api/v1/doctor.py` note/review POSTs accept `Original-Grant-Id`
and emit `Original-Grant-Binding: explicit` when supplied. `authorize` locks
the patient and exact grant; `clinical_attempts.begin` binds the immutable
receipt to doctor, patient, grant, operation, payload hash and key. The F7
matrix is older than the PostgreSQL qualification described in the F8 handoff.
Integration handoff was inspected at PR5
`e1154667d71bc9c909514b911f186afbe6700bb2`; PR4 head at audit was
`edf37a5bdba2b5c7be3fffffca05e4edd6109c1c`. Neither is a deployment claim.

`doctorResource` sends the preserved intent grant and key, never a replacement.
It checks the case-insensitive response header name and exact `explicit` value.
Missing, legacy-current, duplicate/combined or unsupported values fail closed
before returning narrative data to the editor. HTTP201 without proof is an
unconfirmed outcome, not rejection. The original intent survives.

The narrow clinical path in `integrationResource` now requires the retained
key/body/account identity, checks the current original grant before a deliberate
same-operation retry, overrides request grant metadata from that identity and
never sends the response-only binding header. It also requires explicit response
binding. No controller automatically invokes a retry or generates a new key.

## Recovery evidence and limits

Refresh performs GET receipt lookup and fresh authorized history reads only.
An exact committed receipt with matching actor, patient, access_id, operation,
payload and review sequence is sufficient evidence of the original SQL record's
grant identity. It may resolve a lost/missing-header response through this
independent durable evidence and history comparison; it does NOT prove that an
`explicit` response header was originally observed. Unknown, altered grant,
expired/erased receipt or mismatching current history never clears uncertainty.
Receipt lookup itself never establishes current authority: existing connection
checks bracket lookup and PHI reads. No historical result reopens revoked access.

Backend does not persist an explicit-versus-legacy binding-mode field in
`clinical_attempts.out`. Hussam: if product acceptance requires retrospective
attestation of the original HTTP header mode (rather than the exact committed
grant identity), add a durable, operation-bound binding-mode field; a new header
on receipt GET cannot truthfully attest how the original write was authorized.
This change makes no such retrospective header-mode claim.

Existing F7 logout/account/role/patient/generation guards and quarantine remain.
401 ends session via existing transport; 403 denies original authority;
404/409/410/412 do not confirm success; 503/timeout/lost response retain the
original unresolved identity. No production journal activation or new storage.

## Validation

New tests exercise note/review request grant and absence of response-only request
header; explicit, missing, legacy and unsupported responses; exact retry
key/body/grant; 401/403/404/409/410/412/503; no duplicate controller submission;
receipt resolution without another write. Existing F7/Q tests cover late response,
replacement grants, revocation, expiry, session/account changes, privacy and CAS.
The shared synthetic fixture now models the Backend201 binding response; negative
F8 tests explicitly replace/remove it. Changed-body retries fail before HTTP,
so the old duplicate test now expects one permitted duplicate instead of two.

Focused/full/analyzer outcomes and publication SHA are reported in the final
delivery. No real OAuth, live services, native/device or clinical validation.
Next task: F8-2 policy document and password-recovery integration; not implemented.
