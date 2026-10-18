# Specific dependency amendment — APPROVED 2026-10-19
The exact approved sqlite3 3.7.1 cannot resolve on installed Flutter3.44.8:
Flutter pins meta1.18.0; sqlite3>=3.6 requires hooks^2.2 / record_use^1.0 /
meta^1.19.0. Actual flutter pub get failed before lockfile changes.

Proposed one-line amendment to app/pubspec.yaml:
```diff
-  sqlite3: 3.7.1
+  sqlite3: 3.5.2
```
Retain native-assets source:sqlcipher, all reviewed native scope, SwiftPM, SDK
minimums, signing and identifiers. No dependency_override and no Flutter upgrade.
3.5.2 archive inspected: Dart>=3.10; hooks>=1<3; pinned release binary SHA256s,
SQLCipher hook supported. Its exact transitive lock/engine/ABI/minimums/licenses
still require actual resolve/build/runtime verification after approval. Never use
plaintext fallback if SQLCipher absent. Production activation remains forbidden.
Native bridges and independent protocol work can continue without this amendment.

Amr explicitly approved sqlite3 3.5.2 in the current conversation, with verification/testing. This does not approve production activation.
