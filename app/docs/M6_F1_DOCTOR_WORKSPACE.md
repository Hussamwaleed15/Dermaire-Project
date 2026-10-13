# M6-F1 — server-confirmed doctor workspace

Starting clean main/origin/main: 65c3c75489ec752ca2b17a40aa16523a50be0ad0.
Baseline1164 tests. Read architecture/agent/roadmap audit findings and relevant
M1–M5 authority/privacy documentation and M4/M5 handoffs. Inspected actual auth,
GET users/me, trusted provision_user CLI, role deps, doctor routes/schemas/models,
doctor_loop authorize/access_out/review_status and current Flutter portal.

Implemented supported role entry: token identity/role must agree with an
owner-matched GET /users/me safety receipt and hydrated profile. A local
AccessSession/patientData/authorized ID cannot unlock or hydrate the workspace.
Provisioned accounts start safety_accepted=False; existing mandatory safety UI
uses POST accept-safety and GET readback before doctor workspace. Password and
existing server-authenticated Google doctor roles share the profile gate. Patient
roles keep their existing shell; unknown/unsupported roles do not inherit it.
No doctor registration or client elevation. No license/verification status is
exposed by UserOut, so UI describes provisioned accounts without certifying a
medical license. Main/session route invalidation and patient regressions retained.

Actual DoctorPatientOut uses nullable active_experiment. New typed mapping
handles null honestly, validates IDs/current associated grants/expiry/status,
actual priority/count/safety and notes. The existing workspace now refreshes real
connections, search/filters, loading/empty/error with large-text-friendly wrapping;
no invented patients, counts, appointments, activity or decorative destinations.
401/logout/role/consent invalidation and grant expiry clear sensitive lists/notes.
List refresh clears old data; failure never becomes empty or clinical clearance.
An unknown/failed profile recheck hides all patient data but permits a fresh
GET verification under the same authenticated doctor identity; it cannot write.
No cached authorization IDs substitute for backend authorize on each request.

Necessary security repair to the existing note operation: fresh doctor-authorized
patient detail/grant, exact private-note fields, authenticated/session guards,
strict clinician note receipt and notes GET readback before success. Failed
readback/timeout keeps an ephemeral per-session uncertainty lock; no blind POST
replay. Existing positive note regressions retain actual save assertions with
stronger authenticated/full-contract fixtures (their old unauthenticated mock201
was not an authorization guarantee). F4 will add the wider review/visibility/
follow-up UX; no speculative clinical operations were enabled here.

Privacy: current-session in-memory records only; no sensitive diagnostics, disk
health cache or public URLs/export. Messaging placeholder button removed from
replaced legacy detail; truthful unavailable copy, no inbox/send success.
Pending QR/export finding belongs to F2: current generate-qr sets
export_consent=True; no new linking invocation is added. Backend unchanged.

31 new role/profile/local-forgery, nullable/invalid mapping, grants, current/old401,
reused-token switch, logout/revocation/disposal/concurrent read,403/429/503,
320px/200%/themes/reduced-motion and mandatory doctor-consent tests. Existing
provisioning/clinical-note/access-control assertions retained with isolated
fixtures and invalid-host HTTP guards. Final flutter analyze: **No issues found**. Full flutter test: **1195 passed**
(1164 preserved +31 new). New rejected-vs-uncertain note assertions and profile
failure→verified GET recovery passed. No native/device/production/OAuth test.
