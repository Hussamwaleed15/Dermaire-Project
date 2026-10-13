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
