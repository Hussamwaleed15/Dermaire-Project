# B3 safety policy and consent handoff

Date: 2026-11-12 (Africa/Cairo).

This change does not supply or approve legal or medical policy wording. The
approved text, its ownership, and its review remain an explicit release
dependency.

## Flutter contract

Before registration or re-acceptance, Flutter reads
`GET /api/v1/auth/safety-policy`. The additive response contains:

- `required_version`: the exact token that must be sent in `policy_version`;
- `document_status`: `approved` only when an HTTPS document URL and SHA-256 are
  configured together;
- `document.url` and `document.sha256`: the immutable document reference and
  digest Flutter must display and verify;
- `acceptance_ready`: false while no approved document is configured; and
- `enforcement_enabled`: rollout state only, never proof of consent.

Flutter must not present an enabled acceptance action when
`acceptance_ready=false`. It must fetch and display the referenced document,
verify the SHA-256 of the exact bytes, and submit the returned
`required_version`. A `409` means the version changed and the client must refetch
and re-display the contract. Existing clients remain compatible while the
required version stays `1.0` and enforcement remains disabled.

## Rollout boundary

`SAFETY_POLICY_ENFORCE` still defaults to false. Configuration now refuses to
start with enforcement enabled unless both `SAFETY_POLICY_DOCUMENT_URL` and
`SAFETY_POLICY_DOCUMENT_SHA256` identify an approved document. No staging or
production setting was changed.

When enforcement is enabled in a separately authorized rollout, stale, missing,
malformed, or future-dated acceptance blocks protected mutations. Readback,
acceptance, logout, account erasure, consent/grant withdrawal, notification
revocation, plan cancellation, and cancellation of pending agent/evaluation work
remain available. Patient and doctor actors are evaluated independently.

## Open dependency

The project owner must provide the reviewed policy document, stable HTTPS
location, SHA-256 digest, effective version, and approval record before any
environment enables enforcement or rolls the required version.
