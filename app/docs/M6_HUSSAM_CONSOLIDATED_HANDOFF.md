# M6 — verified backend requirements for Hussam

Flutter only. Starting audited source65c3c75489ec752ca2b17a40aa16523a50be0ad0.
No backend/provider/DB/Azure/Production/Tester edits or calls. Existing trusted
CLI provisioning, database-backed role enforcement, active owner/doctor grants,
authorized detail/timeline/notes/reviews, immutable notes, sequenced reviews and
private authenticated image reads are real. Do not request them from scratch.

P0 confirmed: backend/app/api/v1/doctor.py:generate_doctor_qr_access creates
DoctorPatientAccess(export_consent=True) without an explicit patient export
choice. GenerateQrResponse returns token/expiry but no distinct consent receipt;
access_out omits export_consent/scoped viewing/export decisions. Flutter will not
invoke this unsafe linking route or claim view-only grant scopes/export permission.
Needed: explicit separate patient view/export intent, scope receipt/readback,
revocation and isolated negative tests. No deployment or paid-resource request.

UserOut exposes account role but no clinical-license verification status. Trusted
operator verification_reference is an audit input, not an app-visible license
receipt. Flutter uses real provisioned role; does not label it license verification.
If verified-clinician badge is needed, provide an explicit authoritative read model.

P1: operation idempotency/attempt receipts and lookup for clinical note/review
writes. Lost responses/readback failure cannot prove rejection; Flutter locks
uncertain operations within the session, no blind replay/exactly-once claim.
Current grant authorization and review sequencing will be audited further in F2–F4.
Additional actual evidence/communication requirements will be recorded per phase.
Existing M1–M5/B1/B2 and M4/M5 remaining requirements stay separate/unresolved.

F2 verified evidence: doctor.py:31–38 explicitly grants export_consent=True;
services/doctor_loop.py:access_out omits export/view scope readback. Flutter blocks
both new QR generation/claim, removes placeholder QR/export/expiry/revoked claims,
and uses existing owner-scoped access GET + per-grant DELETE/GET confirmation.
Provide distinct patient opt-in/consent receipt, export/view scopes and readable
clinician identity before new linking can be enabled. Do not recreate existing
grant read/revoke/detail/authentication APIs. A continuous revocation/change feed
is not present; every new doctor resource request remains server-authorized.

F3: existing doctor-authorized private image read is verified in image_access;
do not recreate it. Owner capture metadata/measurement/PSM APIs are not substituted
for doctor reads. Timeline includes actual source rows and bounded context projections,
not a complete/stable history. P1 if consistent longitudinal export/read is required:
provide a stable snapshot/cursor with explicit completeness/retention limits and
capture-observation linkage; dynamic offset pages and mutable rows cannot prove this.
No image export is enabled while separate explicit consent scopes are unresolved.
