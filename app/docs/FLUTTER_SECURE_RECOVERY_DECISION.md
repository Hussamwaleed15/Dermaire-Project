# L4 — Secure recovery engineering decision

2026-10-18. Status: architecture assessed; platform implementation BLOCKED pending
explicit native integration approval and mobile crash-boundary verification.
No dependency, native file, token storage or production setting changed.

## Inventory and minimum sufficient recovery

Current pubspec/lock: shared_preferences2.5.5, crypto3.0.7, http and existing camera,
file-picker/auth plugins. No configured transactional operation journal, encrypted
mobile database or protected payload-key store. Auth and pending intents are memory
only. Installed preferences documentation disclaims critical-write durability.

Opaque keys are sensitive correlation handles, not anonymous data. Minimum encrypted
row: schema version, account/role namespace, operation/domain, original resource and
original grant IDs, key, expected revisions, receipt route, created/expiry time,
phase and payload fingerprint. Never include bearer credentials in this row.

Products/routine/adherence/experiments can look up committed original receipts using
these identities; plan mutations additionally need original plan/operation. Doctor
revocations use key+operation and verify current grants separately. Message receipts
need original thread/consent/grant. Receipt-only recovery does NOT reconstruct an
unknown request's exact body. Unknown must lock replacement; do not replay without
the exact original reviewed payload. Do not persist raw chat/clinical narratives or
invitations merely to allow retry. Existing backend Agent session originals remain
bound to original login/TTL and have no discovery API; new login cannot revive them.

## Alternatives and decision

| Alternative | Assessment |
|---|---|
| Preferences / cached read-after-write | Rejected: no sufficient critical durability; plaintext payload risk |
| Plain JSON file / opaque-key-only plaintext | Rejected: no protected identity, journal migration/crash protocol or sufficient replay body |
| Platform secure key-value store only | Suitable candidate for key material; multi-row transitions and send-before-durable races still need a tested journal |
| Server discovery only | Attractive minimal-client option, but receipt lookup requires a known identity and not all domains expose discovery/in-flight fencing |
| Encrypted SQLite journal with protected device key | Recommended architecture to prototype after approval; no claim an unreviewed Flutter package already supplies all guarantees |

Recommended technology: SQLCipher-compatible SQLite binding with verified encrypted
WAL/journal behavior, transactions, explicit synchronous=FULL and encrypted row data;
platform key lifecycle via Android Keystore and iOS Keychain. Select/pin and inspect
the actual Flutter/native binding before implementation; verify SQLCipher licensing,
SQLite settings, supported ABIs/platform versions and SwiftPM compatibility. Existing
iOS project uses SwiftPM with deployment target14.0; do not switch to CocoaPods.

SQLite's durability depends on sync/VFS/storage behavior; WAL FULL syncs commits,
where NORMAL may lose committed transactions at power failure. Encryption and secure
key APIs do not prove disk persistence. This is an engineering recommendation, not
an already verified end-to-end guarantee. [SQLite WAL](https://www.sqlite.org/wal.html),
[atomic commit](https://www.sqlite.org/atomiccommit.html).

## Proposed platform changes requiring approval

Android: approved database and key bridge registration/dependency integration;
review app/build.gradle.kts minimum SDK and ABI compatibility against the selected
binding; add private non-backed-up journal directory and explicit backup/data-extraction
exclusions under app/src/main (AndroidManifest.xml and XML rules if required).
Keystore must wrap/protect a random per-account database key; fail closed if unavailable
or invalidated. Hardware-backed protection is device-dependent and must be checked,
not assumed. [Android Keystore](https://developer.android.com/privacy-and-security/keystore).

 iOS: approved SwiftPM/native database integration and key bridge; private Keychain
service scoped to the app with no shared access group or iCloud synchronization;
WhenUnlockedThisDeviceOnly accessibility for foreground recovery, protected journal
files and backup exclusion. Confirm actual signing/entitlement needs before editing
Runner.xcodeproj, Runner entitlements or Info.plist. No biometric prompt/passcode
requirement added without separate product decision. Keychain access classes differ;
ThisDeviceOnly does not imply universal durability or identical reinstall semantics.
[Apple Keychain](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web).

No specific package version or native setting is approved by this document. Approval
must cover the concrete selected binding and reviewed diff before native edits.

## Protocol, migration and privacy requirements

1. Encrypt and commit PREPARED before any network send; persistence failure means
   no send. Do not infer durable success from an in-process cached read.
2. Retain the same key across SENT/UNCONFIRMED; crash between commit and send is
   ambiguous after restart, so perform authenticated receipt lookup first.
3. Reauthenticate, verify account/role/current consent and original grant scope;
   query original receipt, then read current state separately. No automatic replay.
4. Unknown locks replacement. Expired/erased stays unresolved until supported
   explicit current-state review; no re-key. Original receipt never restores consent.
5. Logout/account switch/expiry/revocation: durable erasure/tombstone protocol before
   reuse, destroy per-account key and delete journal/WAL/SHM; remove private view data.
   Flash forensic erasure cannot be guaranteed by file deletion. Test kill during logout.
6. Version1 explicit bounded schema; authentication/integrity failure or newer schema
   fails closed, quarantines without logging content and offers safe recovery review.
   Migration must be transactional or leave old version usable; no plaintext migration.
7. Cap retention below server receipt expiry; do not silently delete the only
   unresolved identity and then permit a replacement. Define explicit user review.
8. No photographs, clinical free text, raw messages, clinician notes, invitation
   bearer tokens or auth tokens in the journal. Any future exact sensitive replay
   needs a separate reviewed encrypted-payload design and data-retention decision.

## Required evidence before DONE

Unit protocol tests plus real Android/iOS storage tests: failure before persistence,
after durable commit/before send, after server commit/lost reply, kill/relaunch,
account mismatch, expired credentials, withdrawn consent/original grant, corrupt
schema/ciphertext/key, old backups/reinstall, long inactivity/receipt expiry, unknown,
full disk, sync failure, interrupted migration, key invalidation and interrupted logout.
Use a local synthetic server, never production or real clinical data. Verify encrypted
files/WAL, not controller recreation. No exactly-once promise; server idempotency
and unknown/in-flight limitations remain explicit.

## Environment and implementation status

Fresh flutter doctor/devices/emulators evidence: Flutter3.44.8, no Android SDK;
Xcode26.0.1 present, CocoaPods absent, only macOS connected, no emulator sources.
Existing SwiftPM project is preserved; absent CocoaPods alone is not proof SwiftPM
cannot build. No suitable Android/iOS runtime was available and none was installed.
All current recovery tests remain session-memory tests, not process-death proof.
Continue independent L1/L2/L3/UX work while this platform decision awaits approval.
