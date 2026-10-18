# F6c-1 — Product configuration concurrency

2026-10-18. Flutter only. Verified current backend products.py,
product_revisions.py and PRODUCT_MUTATION_ATTEMPTS.md before editing.

Plan: preserve server revision on the actual editor and every existing product
mutation; send strong quoted If-Match from the reviewed snapshot, reject conflicting
preflight reads without silently rebasing, retain current-state readback and test
the race between preflight and mutation. Keep legacy absence compatible without
inventing revision from timestamps. This is the product increment; routine,
experiment, durable operation recovery and history integrations remain separate.

Product.fromApi now validates both revision and revision_protected when either
appears. A revision is a positive signed-32-bit integer, never a timestamp, float,
string or engine version. Absent metadata is legacy, with no CAS guarantee. Local
copyWith retains original owner/timestamp/revision/protection; these server fields
are not writable JSON fields or persistent cache. The actual product editor had
been reconstructing Product without its server identity/timestamp; preserving all
four fields repairs real edit saves, rather than only repository-only tests.

Remote update and controller-driven delete compare the original reviewed metadata
with a fresh owned read. PATCH/DELETE send If-Match: "7" for actual revision7.
A current backend row with revision_protected=false opts into server protection
when that header succeeds; all patient product UI writes use this repository.
No arbitrary header injection: the optional typed patientResource precondition is
restricted to product-ID PATCH/DELETE and validated before dispatch. The separate
Tester and its legacy API helpers remain untouched. The backend handles its own
transactional dependent effects; this client cannot override a protected routine
business conflict or manufacture authority over it.

A stale preflight is rejected before mutation. A race after preflight remains a
412, with no automatic retry, new revision, optimistic success or local overwrite.
409/410/412/422/428 have safe actionable copy; response bodies remain undisclosed.
Successful update returns separately read current state, including actual returned
revision (not assumed +1); changed readback is unconfirmed. Deletion still requires
successful DELETE204 then GET404; timeout/503 followed by mere absence is not taken
as proof. Product creation is unchanged. No operation receipt or durable restart
recovery is claimed by this increment; those existing contracts remain to integrate.

Regression tests use host-denying MockClients: malformed/partial metadata, legacy
compatibility, immutable copy/body isolation, initial opt-in and already-protected
writes, revision jumps, 401/403/409/410/412/422/428/503, same timestamp with changed
revision, preflight-to-write race, reviewed delete revision, late logout response,
and actual editor success/stale rejection feedback. Existing product authority,
model/controller/widget tests remain in the full gate. No live service or mobile
runtime claim, backend/native/provider/Tester change or production deployment.

Final gate: flutter pub get succeeded; flutter analyze clean; all1566 Flutter tests pass (+28 new).
