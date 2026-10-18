# F6-N device evidence — executed2026-10-19

Host Flutter3.44.8/Dart3.12.2, Xcode26.0.1, SwiftPM retained. Fresh flutter doctor -v
reports no Android SDK. flutter devices initially macOS only, flutter emulators no
sources; simctl inventory found existing shutdown iPhone17/iOS26.0 runtime(actual
26.0.1). No images, host toolchains, permissions or deployment settings installed.
Device DB96C794-96EA-4BB6-BDB3-301F8F385FB9 booted for isolated debug tests.

## Native key and strict refusal —2 integration tests PASS
From app/:
```sh
flutter test integration_test/native_journal_keys_test.dart --no-pub --dart-define=DERMAIRE_EXPECT_PROTECTION_UNAVAILABLE=true -d DB96C794-96EA-4BB6-BDB3-301F8F385FB9
```
Final Xcode34.5s,2 tests passed. Random32-byte Keychain create/load, duplicate create
refusal, distinct role keys, fence/reuse refusal and idempotent destruction/deletion.
Second test expects strict disk adapter to refuse at file-protection on THIS
simulator, then cleans its namespace. Omitting the define requires actual verified
protection and is the physical-device expectation, NOT a simulator success claim.

Initial protection success attempts FAILED. Actual native diagnostic identified
fileProtectionMismatch: after requesting complete protection, simulator attributes
do not confirm the class. Both FileProtectionType and String representations are
checked. No native bypass added. Production adapter remains fail-closed. Hardware
lock/Keychain accessibility/invalidation/security-class semantics remain unqualified.

## Real SIGKILL/relaunch — bounded storage qualification PASS
Build the explicit synthetic target, not lib/main.dart:
```sh
flutter build ios --simulator --debug --no-pub --dart-define=DERMAIRE_SIMULATOR_QUALIFICATION=true -t integration_test/secure_journal_restart_app.dart
xcrun simctl install DB96C794-96EA-4BB6-BDB3-301F8F385FB9 build/ios/iphonesimulator/Runner.app
xcrun simctl get_app_container DB96C794-96EA-4BB6-BDB3-301F8F385FB9 com.example.dermaireApp data
```
Set `tmp/dermaire-journal-test-phase` in the returned CURRENT app container to
`prepare` (plain synthetic control word). Relaunch via:
```sh
xcrun simctl launch DB96C794-96EA-4BB6-BDB3-301F8F385FB9 com.example.dermaireApp
```
Read `validation-prepare.json` under container Library/Application Support/journal-v1.
Paths may move on reinstall; always rediscover container. Original attempt using
Platform.environment did not receive the phase; replaced with this test-only tmp
control file. No AppDelegate argument/configuration changes were needed.

Actual final run: prepare process44531,1 synthetic keyed write whose reply was
lost. An independent encrypted connection proved unconfirmed on disk before send.
Main connection deliberately remained referenced/open, leaving WAL live. Inspected
actual DB4096B, WAL28872B, SHM32768B before termination: none contained selected
synthetic owner/key/path/SQLite-header markers. Host tests separately inspect live
DB/WAL too. This finite search does not prove absence of plaintext in every OS
artifact, VM memory, backups, key caches or temporary directory.

Sent **SIGKILL to44531 only**, using the PID just returned by our explicit launch;
verified process exited. Changed tmp phase file to `recover`, then launched same
installed binary without data clearing/reinstall. New process44562 restored one
original unconfirmed identity, read actual ProductReceiptReader contract through a
strict fake transport, then current product revision2 separately from receipt1.
Result reviewRequired;0 writes,1 original receipt read,1 current read. Distinct
account namespace was empty; current-session invalidation denied old disk access.

[Machine evidence](validation/F6_N_IOS_PROCESS_EVIDENCE.json) records flags/counts,
versions and selected artifact sizes; no raw keys, tokens, paths or payloads.
Cipher version4.18.0 community, SQLite3.53.4 on host and iOS.

**Qualification-only limitation:** integration_test/SimulatorQualificationPlatform
explicitly injected ONLY for this debug target and define acknowledges the exact
simulator fileProtectionMismatch. It never changes lib/ or native behavior, and
cannot run in release. Evidence explicitly says file_protection_verified=false.
Thus SIGKILL proves this bounded SQLCipher/Keychain storage persistence/reconciliation
under synthetic injection. It does NOT prove strict production secure-journal
end-to-end readiness, hardware Data Protection, power-loss durability or every crash
boundary. Native strict adapter refusal is independently tested above. Production
journaling remains disabled; all real mutation controllers remain unchanged.

After inspection set tmp phase `cleanup` and launch to fence/destroy/remove this
synthetic namespace. A fenced namespace cannot be reused; a repeat should use a
new explicitly isolated synthetic test owner in the entry, never erase a real
uncertain identity or bypass a fence merely to retry. Fixed keys are test-only.
No OAuth, real patient records, staging/production API or provider was contacted.
All synthetic API requests reject any host other than flutter-tests.invalid.

## Android — BLOCKED runtime, static checks only
SDK/AVD/device absent. No build/emulator/Keystore runtime/SIGKILL claim. Source bridge
and backup XML reviewed, effective Flutter minSDK24 retained; official arm64 library
API24 and16KiB PT_LOAD alignment statically checked. Other ABIs/APK16KiB execution,
backup/restore/OEM transfer, key invalidation and directory fsync need real execution.
After separately provided/approved toolchain and supported device, run the same
native key test without the simulator-protection define, then build/install the
synthetic target (no qualification bypass), provide explicit phase control, terminate
and relaunch using actual package ID com.example.dermaire_app. Do not install tools
or change app IDs/minimums/signing to make this report green.
