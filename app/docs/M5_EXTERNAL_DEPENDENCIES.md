# Product M5 — external dependencies and ownership

14 November 2026. Flutter source checkpoint: `94ca238ec5497caa4f5f6a9ce27d5047aa56ec83`, stacked on PR7 `5d855b499f73866ba6894fe67f950e81ec1b6e51`. This document is a handoff, not evidence that anyone has been messaged or that activation was authorized.

## Hussam: attempt-specific notification reconciliation (requirements 1, 2, 6)

Verified contracts: `GET /notifications`, `GET /notifications/history`, `PUT /notifications/{id}/read|unread?expected_revision=N`, `GET|PUT /notifications/preferences`, `DELETE /notifications/preferences?expected_revision=N`, `GET|PUT /notifications/routine-reminders/{entry_id}`. Paths are relative to the existing API prefix.

Current revisions/CAS protect resource updates. They do not provide durable proof of the original request after response loss. Preferences/reminders have no attempt-specific receipt; notification transport history is not a read-state mutation receipt. Flutter now retains the exact normalized original request and precondition in session memory, archives unknown attempts when a newer CAS revision fences replay, and never infers original execution from matching current settings. Read-state local identity is not a server idempotency key and is not sent as a fabricated header. DELETE disable-all has a retained original CAS request too.

Required decision/contract before claiming complete original reconciliation: identify only operations that can support transactionally durable, owner/role/resource/payload/precondition-bound original-attempt proof; specify accepted operation identity, request binding, authorized lookup, retention/expiry and definitive versus unknown outcomes. Preserve current independent resource authority. Missing/expired proof must not imply rejection or safe replay. Do not add a fake universal receipt or retrofit exactly-once guarantees without transaction evidence. Include concurrent CAS/response loss/account-deletion tests in Hussam's scope. Flutter can safely continue explicit current GETs and bounded same-original CAS retry; no automatic retry.

Privacy: pending bodies are session memory only. Existing logout removes them; expiry quarantines only minimal operation identity using existing infrastructure. No other account receives payloads/identities. A future proof endpoint must preserve owner and current authorization, redact private destinations and define account deletion. Do not weaken existing domain receipt readers.

## Hussam + Amr: scheduling and provider/device boundary (requirements 2–4)

Current reminder contract uses explicit timezone, AM/PM minute values, fold, gap_policy=skip, calendar_policy=prospective_fixed_occurrences_v1 and effective_at. Live delivery remains unavailable. Flutter preserves those values and does not invent a cadence, DST rule or adherence inference. No hosted worker was enabled or qualified.

Before any registration/push activation, Hussam must supply approved provider/installation lifecycle and actual supported permission/token/registration response semantics, ownership binding, token refresh/expiry/revocation, logout/account-switch cleanup, worker scheduling/retry and privacy-safe generic payloads. Device delivery may be claimed only with real authoritative proof; enqueued/provider_accepted/read-in-app are insufficient. Worker rollout and provider credentials belong to Hussam; no Azure or production change is requested by this Flutter commit.

Amr must approve an explicit permission-request journey and any new native SDK/token capability. Routine consent, OS permission, registration, medical consent and push preference stay independent. Denied/restricted/unsupported/unavailable permission must not register a device. No fake token or silent registration fallback. Registration route/model existence alone is not qualification.

Safe Flutter work completed without activation: explicit unavailable permission/token/registration/provider status, truthful accepted-versus-delivered labels, typed transport evidence and existing reminder/current-consent UI. Existing abstractions remain inert.

## Amr + security/operations + Hussam coordination: persistence (requirements 5, 6)

Current notification drafts and mutation identity are memory-only. Private views wipe on background/route hide/logout/authorization loss, resume with current GETs, and discard superseded callbacks. This is intentionally not a process-death recovery promise. No private cache or draft is persisted by M5.

The isolated SQLCipher implementation and SecureRecoverySession are qualification components, not approved production composition. Turning them on requires a reviewed design and explicit approval for encryption/key management, secure-store availability, per-account key isolation, device lock/authentication, retention/expiry, revocation/deletion, rotation, corruption recovery, backup/migration, failure behavior and operational qualification. No plaintext fallback. Amr owns product retention and draft/cache expectations; security/operations own qualification; Hussam coordinates any server revocation/receipt-retention guarantees. Medical actions must continue requiring current online authority.

Safe independent work: honest memory-only draft/freshness presentation and preserving uncertain original identity within the existing session boundary. No durable journal, private disk cache or new offline queue has been activated.

## Salma and release owners (all requirements)

Independent source/contract/privacy/accessibility QA and authorized integration of the open PR stack remain pending. Physical-device iOS/Android permission revocation, token lifecycle, notification privacy and actual push delivery need approved native/provider implementation first. Real Backend/version rollout, device storage/key-loss/process-death tests, worker/provider qualification and release authorization are separate gates. Host Flutter tests do not qualify these systems or provide clinical validation.

No GitHub issue, external handoff message, merge, QA approval, provider activation, database migration or deployment was performed. M5 product closure remains pending. M6 is not started.
