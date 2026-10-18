# F6-N update — APPROVED IMPLEMENTATION / NOT APPROVED FOR PRODUCTION
2026-10-19. Amr explicitly approved the native architecture and then the specific
sqlite3 3.5.2 amendment after3.7.1 failed Flutter meta resolution. Applied reviewed
native scope with safety hardening in the same files/channels; no SDK minimum,
identifier, signing, entitlement or SwiftPM changes. Exact executed code23ee7e3.
2021 host tests, analyzer clean,2 iOS native integration tests; bounded SIGKILL
storage qualification passed. Strict iOS file protection unavailable on simulator
and correctly refused. Android SDK absent. This supersedes the proposal-only status
below; the old draft patch is HISTORICAL and must not be reapplied.
See FLUTTER_F6_N_SECURE_RECOVERY_REPORT_AR.md and FLUTTER_F6_N_DEPENDENCY_AMENDMENT.md.
Production mutations remain on prior memory behavior. Rollout NOT APPROVED.

---

# Secure operation journal — concrete native approval proposal

Status: PROPOSED / NOT APPROVED / NOT APPLIED.2026-10-18.
The F6-M instruction authorizes independently testable Flutter protocol work, and
explicitly requires approval before native configuration changes. Only that native
subtask is paused; other Flutter work continues.

Reviewable patch: [secure_journal_native_review.patch](proposals/secure_journal_native_review.patch).
It contains actual proposed file contents, not applied project changes. Native
bridge code is a review draft, not compiled/qualified production code. Approval of
this proposal authorizes implementation/compilation of this exact candidate; it
must not enable recovery until all qualification gates below pass. Changes found
necessary outside the reviewed native scope require an amended reviewed proposal.

## Selected candidate and compatibility evidence

Select **sqlite3 exactly3.7.1**, native-assets hook **source: sqlcipher**. No sqflite
plugin, no sqlcipher_flutter_libs, no CocoaPods migration. Keep SwiftPM and iOS14.0.
Installed Flutter3.44.8/Dart3.12.2 satisfies package Dart>=3.10<4. Package archive
SHA256144132790ec1947fad9f3ddceffd0af2ab80a1f0d1e81a4d094ee6707ec3df0b.
The package hook checks release-library SHA256s; dependency lock resolution and
transitive review must be generated after approval, not fabricated in this document.
[Version/source](https://pub.dev/packages/sqlite3/versions/3.7.1),
[hook documentation](https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.7.1/sqlite3/doc/hook.md).

Downloaded libraries were inspected as data in /tmp, never loaded/executed:

| Official release asset | Verified SHA256 | Static evidence |
|---|---|---|
| libsqlcipher.arm64.ios.dylib | c19c3a9133f1e5a3e30206b573e36d07b1648e36c5f7c0f85500c5e0c80121b4 | Mach-O LC_BUILD_VERSION minos12.0; Foundation/Security dependencies; compatible minimum with iOS14 |
| libsqlcipher.arm64.android.so | 8308570993f1e7dd0742c1cbc82b587951ca724830bf18d5e4948ed34574db40 | ELF .note.android.ident API24, NDKr29 |

SDK FlutterExtension.minSdkVersion is24; app currently uses flutter.minSdkVersion.
No raise is proposed. Package advertises Android arm/arm64/ia32/x64, iOS arm64 and
arm64/x64 simulators. Only the two assets above were independently inspected;
other ABIs, simulator binaries, symbol conflicts, signing, loader names and16KB
Android page alignment remain build/runtime qualification gates. iOS binary install
name is @rpath/libsqlite3.dylib; verify Flutter native-assets packaging does not
resolve the system plaintext library. Fail closed on absent cipher_version.

Candidate comparison from downloaded pub archives:

- flutter_secure_storage11.2.0: compatible Flutter/Dart and Androidmin23; Darwin
  plugin0.4.3 has Package.swift/iOS13. But ordinary Android writeUnsafe encrypts
  then invokes SharedPreferences.Editor.apply(). Encryption does not establish
  synchronous critical-key durability. It is **not selected** for the DB key path.
  [Pinned source](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0),
  [Android apply/commit contract](https://developer.android.com/reference/android/content/SharedPreferences.Editor).
- sqflite_sqlcipher3.4.1: compatible advertised Dart>=3.9/Flutter>=3.35; inspected
  archive has iOS podspec but no Package.swift. Not selected for this SwiftPM app.
  [Pinned package](https://pub.dev/packages/sqflite_sqlcipher/versions/3.4.1).
- SQLite binding is MIT; bundled SQLCipher community and OpenSSL have their own
  notices/terms. Hook explicitly links OpenSSL on Android/Linux/Windows. Preserve
  exact binary notices/SBOM; verify actual embedded SQLCipher/SQLite/OpenSSL versions
  and vulnerability policy before distribution. No commercial edition entitlement
  or legal clearance is implied. [SQLCipher](https://www.zetetic.net/sqlcipher/),
  [cipher settings](https://www.zetetic.net/sqlcipher/sqlcipher-api/).

## Exact proposed native scope

Patch includes app/pubspec.yaml exact pin/hook, and these native files only:

1. android/app/src/main/kotlin/com/example/dermaire_app/MainActivity.kt: register
   a small serial background MethodChannel key bridge. Per-namespace Android
   Keystore AES/GCM wrapping key; random32-byte DB key wrapped with namespace AAD.
   Wrapped key file uses sync/rename/directory sync, no preferences. Fail closed
   on invalidation, missing key, short/corrupt bytes, sync failure or fence.
2. android/app/src/main/AndroidManifest.xml: point to the two journal exclusion
   resources. No permission, SDK, application ID, signing or provider change.
3. android/app/src/main/res/xml/journal_backup_rules.xml and
   journal_data_extraction_rules.xml: explicit journal root exclusion for cloud
   and device-transfer; journal lives under Context.noBackupFilesDir/journal-v1.
   No whole-app backup disable. Verify OEM restore/transfer experimentally.
4. ios/Runner/AppDelegate.swift: private bridge appended in the existing source
   file and registered with the implicit Flutter engine. Keychain generic-password
   service dermaire.journal.keys.v1, per-namespace account, synchronizable=false,
   WhenUnlockedThisDeviceOnly, no shared access group, no new entitlement. Private
   Application Support/journal-v1 directory uses complete file protection and
   isExcludedFromBackup; verify attributes on DB/WAL/SHM/temp files too.

No Gradle minimum/ABI setting change, Podfile, Xcode project, Info.plist, provisioning
or entitlement change is proposed. If actual signing/registration needs one, stop
that native expansion and amend this proposal. No server/provider change.

## Journal adapter requirements before production wiring

The current operation_journal.dart is a typed independent protocol, not a disk
implementation. The approved candidate still needs a reviewed Dart SQLCipher
OperationJournal adapter and account/role/namespace-epoch registry:

- Never use owner identifier as a filename; namespace=SHA256(owner/role/random
  epoch), stored only in protected app metadata. Opaque hashes remain sensitive.
- Request loadKey for an existing DB. Missing/invalidated key or unreadable DB must
  not trigger createKey or plaintext fallback. Explicit new epoch allowed only
  after durable prior cleanup and a fresh reviewed operation, never uncertain replay.
- Raw key exists transiently in same-process bridge/Dart memory; do not print key,
  SQL key PRAGMAs, payload fingerprint, paths or handles. Best-effort buffer clearing
  does not guarantee erasure of all VM/native copies. No biometric policy added.
- Fail unless actual SQLCipher cipher_version is nonempty. Apply key before schema
  read, cipher_plaintext_header_size=0, cipher_memory_security=ON, temp_store=MEMORY,
  journal_mode=WAL and synchronous=FULL; verify reported values. Verify encrypted
  pages/WAL and temp behavior, authenticated corruption failure and no fallback.
- UNIQUE namespace+key and transactional CAS; prepared and unconfirmed commits
  complete before any mutation. Disk/sync failure means no send. A successful HTTP
  response still needs original receipt and current authorization readback.
- Encrypt metadata rows, not just connection state. Journal schema1 is bounded,
  explicit and contains no images, messages, notes, narratives, invitation secrets
  or auth tokens. Fingerprint is client correlation, not claimed backend digest.
- Keep unknown/permission-denied/expired identities locked; local review_at is not
  server receipt expiry. No automatic replay, re-key or automatic deletion of the
  only uncertainty evidence. Retention review deadline<=30days; do not silently
  unlock on expiry. Agent/invitation originals remain login/TTL bound.
- Explicit logout/account deletion: synchronously hide views, durably fence old
  namespace, close connections, destroy protected key, erase DB/WAL/SHM/temp/wrapped
  key files and sync directories. On interruption, startup honors the fence and
  repeats idempotent cleanup; no namespace reuse until completion. Expiry/read401
  hides payloads while preserving encrypted minimum identity for scoped review.
- Fresh install has no migration from preferences or memory. Future schema changes
  must be transactional or preserve old readable journal; newer/corrupt schemas
  lock recovery. No plaintext export/migration. Physical flash erasure not promised.

SQLite FULL/WAL and platform key APIs have storage/OS limits. Read-after-write or
cached key access is not a power-loss proof. [SQLite WAL](https://sqlite.org/wal.html),
[atomic commit](https://sqlite.org/atomiccommit.html),
[Android Keystore](https://developer.android.com/privacy-and-security/keystore),
[backup behavior](https://developer.android.com/identity/data/autobackup),
[Keychain protection](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web).

## Qualification and rollback

Before enabling any production mutation through the adapter: compile debug
synthetic integration entry on actual supported Android/iOS; verify all packaged
ABIs/iOS14/SwiftPM loader and signing; inspect cipher/sqlite/OpenSSL versions and
licenses; test Android16KB device; inspect DB/WAL/tmp for known synthetic strings.
Kill/relaunch at every journal/HTTP/cleanup boundary, full disk and failed sync,
wrong account/role, old backups/transfer/reinstall, key invalidation/locked device,
corruption, migration, original grant loss, unknown/expired receipts, newer current
resource and concurrent CAS. No real accounts, clinical data or production URL.
Process-death DONE requires those executed results, not the current unit tests.

Native bridge draft must also pass race/thread/engine-detach tests and account
registry review. Directory fsync and Keychain/Keystore persistence must fail closed
when unsupported; neither has been proven by this proposal. Hardware-backed keys
are device-dependent. No exactly-once guarantee or clinical inference claim.

Rollback: keep journal adapter disabled unless qualified. Disable new journaled
mutations on regression; preserve fenced/encrypted uncertain identities for explicit
review/cleanup rather than falling back to a fresh key. Revert native dependency/
bridge changes only after eligible namespaces are safely fenced and keys handled;
do not downgrade a populated schema or replay pending requests. Current memory-only
application behavior remains truthful until this implementation is approved and
qualified. Approval of the proposal alone is not permission to claim durability.
