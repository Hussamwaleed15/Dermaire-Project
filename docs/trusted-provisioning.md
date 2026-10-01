# Trusted privileged account provisioning

The sole supported provisioning mechanism is an interactive operator CLI on
an access-controlled backend host. It uses that host's configured database;
there is no public provisioning, invitation, or role-update API and no admin UI.
Access to the backend host and database is the trust boundary. Do not expose
this command through an HTTP route, CI job accepting public inputs, or mobile app.

Before provisioning, the operator verifies the clinician's identity and license
outside the app, or obtains internal approval for admin/support access. Record
only an internal verification/approval reference, not identity documents or
medical data. Restrict operator host and database credentials to trusted staff.

From the backend directory, using its configured Python environment:

```powershell
python -m app.tools.provision_user --email "verified-user@example.com" --full-name "Verified User" --role doctor --verification-reference "APPROVAL-REFERENCE"
```

The example address is a placeholder. The command prompts twice for a hidden
password; it accepts no password argument or environment variable and issues
no session token. Passwords require at least 12 characters and at most 72 UTF-8
bytes. Deliver credentials through an operator-approved secure channel. The account and
provisioning audit are committed together; failure rolls back both. No schema
migration or privileged seed credentials are introduced.

The same command supports doctor, admin, and support, with an explicit role.
New account emails are stored in lowercase; use that address for sign-in.
Existing emails (including differently cased emails) are rejected without changing
passwords, roles, patient data or safety acceptance. Patient-to-doctor conversion
is deliberately unsupported in this MVP; it requires a separately reviewed
operation. Public password and Google signup continue creating patients only.

Existing doctors retain password/Google authentication through the existing
backend endpoints. Flutter doctor sign-in requires a server-confirmed doctor
role, real user ID, token expiry and an authorized-patient response. It never
creates a doctor session on network/authentication failure or for patient,
admin or support logins. Admin/support accounts have their existing backend
permissions; the doctor UI does not implicitly grant them doctor permissions.

The workspace displays the server's authorized patient list and confirmed
clinical notes. Empty lists remain empty. Notes require a successful server
save; fake patient records, metrics and local-only success are removed from
this doctor flow. Clinical access still requires patient-generated consent;
expired/revoked links do not authorize listing or notes, and an assigned QR
grant cannot be taken over by a different doctor.

This milestone does not change secret configuration or the overall refresh/
logout design. Those remain separate work.
