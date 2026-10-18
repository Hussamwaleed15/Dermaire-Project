# F6-N execution — 2026-10-19
Start0acf2aa, clean main, matching official fetch/push URL and fetched main.
Full baseline1982/analyzer baseline from prior checkpoint; fresh full1982 pass.
Read app/AGENTS.md and all mandatory recovery/proposal/status/handoff/device docs.

N1: approved native key bridges and backup exclusions implemented only in reviewed
files, plus Dart namespace/bridge contract. Installation random epoch is protected
by no-backup/file-protected root; missing epoch with prior artifacts fails closed.
Native createKey independently refuses an existing database/artifacts. Fence remains
permanent after idempotent key/file cleanup. Added protectFiles and eraseFiles in
same reviewed channels/files. No identifier/signing/minimum/SwiftPM changes.
The bridge is not invoked by production entry or mutations. No production key use.

Actual iOS Keychain integration test: iPhone17/iOS26.0.1, existing SwiftPM, Xcode build
20.3s,1 test passed: missing-key load, random32-byte create/load, account-role key
isolation, fence, idempotent destroy/erase, reuse denial. No network. Initial run
exposed read-only platform Uint8List; fixed by explicit mutable copy. Initial failed
run is not counted as success. Hardware lock/invalidation/power loss not proven.

Dependency amendment: exact sqlite3 3.7.1 failed resolution (hooks2.2/record_use1/meta1.19
versus Flutter3.44.8 pinmeta1.18). Amr explicitly approved3.5.2 via response in this
conversation. No override/SDK upgrade. Isolated temp qualification resolved3.5.2
and passed31 tests with actual SQLCipher encrypted DB/WAL, wrong/corrupt/missing key,
CAS/concurrent connections, reconstruction, no replay, account/role/expiry and fence.
These31 are candidate host tests, not yet final app regression/device evidence.

N1 gate:1993 full host tests (+11), analyzer clean, diff check clean;1 native iOS key test passed. Android remains static-only.

N2 in progress: approved3.5.2 resolved in real app:8 transitive additions, existing
versions preserved (hooks2.0.2, code_assets1.2.1, record_use0.6.0). Actual focused
suite63 passed. Encrypted disk adapter validates nonempty cipher_version, raw256-bit
random key, encrypted header, memory security, temp memory, WAL/FULL, integrity,
schema1 and encrypted owner/role binding. SQLite transactions and identity/phase CAS;
immutable timestamps/identity, limit1000 records, bounded row decoding. Native
protection acknowledged after writes; acknowledgment failure prevents send even
if DB commit already happened. Original ambiguity remains persisted, never rekeyed.
No production construction. Explicit SecureRecoverySession composes existing
coordinator and domain readers; auth expiry closes access without erasing minimum
identity; explicit cleanup fences before key/files. Fenced namespace reuse remains
forbidden, including after logout. New-epoch provisioning after explicit cleanup
is not automated by this wave.

N2 final gates:2021 full host tests (+39 vs1982;11 bridge+28 encrypted storage),
analyzer clean. Actual SQLCipher DB/WAL tests pass; no plaintext fallback, missing/
wrong/corrupt key or DB, schema0/2/99, changed identity, encrypted malformed row,
CAS/concurrent connections, rollback, delayed session, scoped reconstruction,
original receipts/current revision, unknown/expired/denial and I/O ack failure.
Native2 integration tests passed (key lifecycle and strict protection refusal).
Final bounded SIGKILL open-WAL process44531→44562 passed storage recovery with
qualification-only injection; strict file-protection is NOT validated on simulator.
See FLUTTER_F6_N_DEVICE_EVIDENCE.md and machine JSON. Android runtime BLOCKED.
Production activation NOT APPROVED. This is not full hardware qualification.
