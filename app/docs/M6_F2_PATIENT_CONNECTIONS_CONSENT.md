# M6-F2 — connections and consent (PARTIAL; supported revocation delivered)

Starting main/origin/main dcb1dc36dec6cfa791b061398c618fcf72fd5863.
Inspected doctor.py generate/claim/access/per-grant DELETE/bulk revoke/detail,
doctor_loop.authorize/access_out, grant/QR schemas/models and doctor-loop tests.
Backend role, patient/doctor identity, active expiry checks and patient lock are
real. Grant IDs/timestamps/status and readback exist. Do not request these anew.

Confirmed P0: doctor.py:31–38 creates QR access with export_consent=True without
an explicit export choice. GenerateQrResponse supplies a token/QR payload and
expiry, while access_out has no scope/export receipt. Flutter now refuses both
QR generation and claim before HTTP. Linking is BLOCKED pending explicit separate
view/export choices and readback. No convincing fake QR/token input/deep-link,
fixed seven-day/Apr2025 expiry, no-login claim or export-success button remains.
The backend is unchanged; this does not repair its broader-consent behavior.

Replaced the local doctorLinkActive flag and fire-and-forget revoke with actual
GET /doctor/access and selected DELETE /doctor/access/{id}. Patient role/profile/
owner/generation/confirmed safety acceptance guard every request. Validate rows,
IDs, owner/granted_by, statuses and real UTC expiry. No inference of view-only or
export scopes; omitted permissions are explicitly unavailable. Historic revocation
metadata can be absent, but a new confirmed revoke requires owner/timestamp receipt
and matching revoked GET readback. No optimistic UI success. Failed/uncertain
outcomes clear visible grant metadata and lock that operation within the session;
GET can reconcile a server-confirmed revoked record without DELETE replay.

Doctor selection now opens only after fresh GET /doctor/patients/{id} verifies
exact patient and current associated active unexpired grant. Per-selection
connection controllers bind doctor generation/patient/request/disposal and clear
record/draft on unknown access,403/404, deadline or parent invalidation. Expired
or revoked live grants cannot reuse cached list IDs. No scoped export/messaging
permission is inferred from a detail response. Backend still authorizes each
resource; current client view is a bounded read, not a continuous revocation feed.

Tests:32 new isolated grant/link-blocking, view/export unknown, malformed/foreign
rows, confirmed/rejected/timeout/persisted-but-lost/missing receipt/readback failure,
duplicate DELETE, logout/account switch/current+old401/revoked consent, fresh doctor
selection and 320px/200% Light/Dark/reduced-motion/accessible sharing regressions.
F1 doctor regression suite preserved. Final flutter analyze: **No issues found**. Full flutter test: **1227 passed**
(1195 preserved +32 new).
No production API, real QR/OAuth, platform/device/native build or backend changes.

A201/200 acknowledgement followed by denied readback remains uncertain, not a
rejected mutation. Both clinical notes and revocation distinguish response phase;
denied reads close sensitive views and cannot unlock a POST replay.
