# Clinical and consent operation receipts (20261015_10)

Optional `Idempotency-Key` preserves existing clients. Send a distinct 16–128 character key for each intended operation and retain the identical request on network uncertainty. The new tables store committed SQL outcomes only, in the same transaction as the domain row and audit. There is no separate durable reservation, rejected registry or fake in-flight state. An unknown lookup cannot prove rejection or that retry under a new key is safe.

* `POST /api/v1/doctor/patients/{patient_id}/notes`
* `POST /api/v1/doctor/patients/{patient_id}/reviews`
* `GET /api/v1/doctor/patients/{patient_id}/attempts/{note|review}/{key}`
* `POST /api/v1/doctor/generate-qr`
* `DELETE /api/v1/doctor/access/{access_id}`
* `GET /api/v1/doctor/consent-attempts/{issue|revoke}/{key}`

Writes return `Operation-Attempt-Id`, `Operation-Replay`, `Result-Snapshot: original_committed`, and `Cache-Control: no-store`. Lookup returns `committed`, `expired` or `unknown`; snapshots are original historical outcomes, never current resource projections. Replaying a review happens before its original CAS check, so a lost response is recoverable without creating another sequence. Reusing the key with different content/preconditions returns 409. Receipts expire for replay after 30 days (410). A failed/ambiguous commit returns 503 and requires lookup with the original key. Invalid/unauthorized requests retain existing 401/403/422 semantics and have no durable rejection receipt.

Clinical identity binds doctor, patient, operation and key; the fingerprint binds the typed full payload including expected review sequence. The receipt binds the actual consent grant. Every replay/readback reauthorizes current VIEW access. Different current grant returns 409, revoked/expired access returns 403. Private note/review snapshots never become patient-visible through this route. Existing private-current review precedence and urgent safety remain unchanged.

Issue receipts bind explicit VIEW/EXPORT payload, selected doctor, validity and issuing login session. QR receipt replay/readback with token is available only while that original invitation is pending, unclaimed, unrevoked, unexpired and its issuing credential/session intent remains valid. A claimed/revoked/expired invitation is never recreated by retry (410; readback `committed` with `result_availability: unavailable`, no bearer token). Revoke receipts bind the exact access ID. Single-use claim and bulk revoke also support optional receipts as detailed below.

PostgreSQL uses the patient row lock shared by grant issue/revoke, clinical writes and patient deletion, with grant locks after patient lock. Concurrent duplicate SQL requests converge on one receipt. SQLite compatibility is verified but does not constitute PostgreSQL locking evidence. Bilateral account deletion removes clinical receipts and all grant receipts for related grants; linked notes authored by surviving doctors also have receipt copies erased when the linked review author is deleted. Signed account recovery invokes this same deletion path.

Remaining: durable rejected/in-flight registries, explicit required-key migration and any future onboarding-version transition are not implemented by this increment. Existing safety/onboarding version checks remain as verified in their own contracts. No live provider, deployment or clinical validation is implied.

Additional scope completed: single-use claim has optional same-grant clinician receipt through the existing clinical attempt lookup (`claim`); successful replay requires the same still-valid token/grant, current doctor assignment and issuing credential/session intent. An unkeyed claim remains single-use 409 after claim. Bulk revoke has optional `revoke_all` patient receipt and now takes the patient lock before grant locks. Replaying its original receipt returns its historical outcome and does not revoke newly issued grants; send a new key for a genuinely new revoke-all intent.

`GET /api/v1/users/completion-receipts/{safety|profile-review}/{version}` exposes existing atomic completion audit evidence scoped to the authenticated account. Safety uses the exact policy version; profile-review supports version `1` only. `committed` requires the actual original audit; legacy accepted/profile rows without that audit return `unknown`, with current state separately exposed. Safety acceptance already uses conditional SQL and exact required-version validation; profile review already uses one-time timestamp CAS with transactional audit. These routes do not introduce a durable rejected/in-flight registry or pretend that future onboarding versions exist.
