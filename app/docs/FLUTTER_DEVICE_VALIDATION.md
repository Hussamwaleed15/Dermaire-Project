# Latest device result — F6-N2026-10-19
The existing iPhone17/iOS26.0.1 simulator built native-assets SQLCipher with SwiftPM.
2 native key/strict-refusal integration tests passed; actual SIGKILL44531→44562
with live DB/WAL/SHM recovered original identity with0 new writes,1 receipt and1
current read. This run used explicit test-only simulator qualification injection;
file_protection_verified=false. Strict lib/native protection remains fail-closed.
Not proof of complete secure production restart recovery or hardware protection.
Android SDK still absent; no Android runtime test.2021 host tests/analyzer clean.
Exact commands/evidence/limits: FLUTTER_F6_N_DEVICE_EVIDENCE.md. Historical F6-M below.

---

# Flutter device validation — verified2026-10-18

Current bounded result: **iOS simulator synthetic smoke PASSED**. Android execution
BLOCKED; complete mobile/native capability qualification remains PARTIAL.

## Actual environment and discovery

Flutter3.44.8 / Dart3.12.2; Xcode26.0.1. Existing SwiftPM project retained; CocoaPods
absent, no CocoaPods migration. Android SDK not found, no Android AVD/device.

Initial flutter doctor -v, flutter devices --machine and flutter emulators exposed
only macOS and reported no emulator sources. That was not enough to conclude that
no iOS runtime existed. Direct xcrun simctl list devices available --json and list
runtimes --json found installed available com.apple.CoreSimulator.SimRuntime.iOS-26-0:
name iOS26.0, actual version26.0.1/build23A8464, with shutdown simulators.

Booted the existing **iPhone17**:
**DB96C794-96EA-4BB6-BDB3-301F8F385FB9**. Flutter then listed it as an iOS emulator.
No SDK, simulator image, runtime, signing setting or provider resource installed.
After successful execution, restored this device to its prior shutdown state.

## Executed command and result

From app/:

```sh
xcrun simctl boot DB96C794-96EA-4BB6-BDB3-301F8F385FB9
xcrun simctl bootstatus DB96C794-96EA-4BB6-BDB3-301F8F385FB9 -b
flutter devices --machine
flutter test integration_test/withdrawal_smoke_test.dart --no-pub -d DB96C794-96EA-4BB6-BDB3-301F8F385FB9
```

Final exit0. Xcode build completed in17.0s; **1 runtime test passed in7s**.
Initial attempts failed; they are not reported as passes. Their fixes were Flutter/
test-only: explicit synthetic HTTP transport across native-frame callbacks, identical
pure Matcher contract predicates rather than WidgetTester-guarded expect() calls
inside fake-server handlers, and bounded waits for actual authorized controls and
confirmed operations. No permission or outcome assertion was weakened.

The shared test/support/withdrawal_workflow.dart drives the same actual widgets and
controllers for host and device entry: denied patient entry → selective original
clinician-grant withdrawal → plan-participation cancellation → separate original
evaluation cancellation → logout → accountB isolation. It verifies untouched other
grants, original identities, no fabricated safety acceptance/AppShell, no images/
clinical-purpose display, and no prior-account clinician or pending payload carried.
Every request uses a contract-faithful fake with flutter-tests.invalid only. Explicit
transport injection rejects other hosts and release mode. Preferences mocked.
No real patient data, Google OAuth, production/staging API or provider used.

Final host evidence is separate: flutter analyze clean; flutter test **1982 passed**.
Four host withdrawal variants cover light/dark,390/320px,100/200% and reduced motion;
eight additional connected-care host journeys cover both roles and those variants.
The executed simulator entry was **light/100%** only; do not imply both themes or
all journeys ran on the simulator. SDK integration_test entry itself was retained.

A debug Dart/assets-only build of this synthetic target also succeeded under
/tmp/dermaire-m8-smoke-bundle. It is not an APK, native-link qualification or executed
test. The subsequent simulator run is the stronger evidence. No tracked native
Android/iOS/configuration, backend, Tester or actual dependency changes occurred.

## Repeat and remaining setup

Recheck device inventory each time. For this already installed simulator, the exact
commands above apply; otherwise choose the actual ID from current inventory. To
repeat host validation:

```sh
flutter analyze
flutter test test/wave_withdrawal_workflow_test.dart test/wave_connected_care_workflow_test.dart
flutter test
```

Android: Amr must provide/approve SDK and a supported emulator/device setup before
installation/configuration. No Android build/run is claimed. Native configuration
changes still require a specific reviewed approval; the general wave is not approval.

Do not run lib/main.dart/default production target to replace this synthetic test.
Do not change SwiftPM to CocoaPods merely because CocoaPods is absent. Existing
SwiftPM configuration successfully built this synthetic iOS run.

## Limits

This is an **iOS simulator synthetic integration smoke**, not physical-device or
backend E2E. Real native camera/permission/capture, Google OAuth, Push delivery,
validated inference and complete patient/doctor mobile journeys remain unverified.
SQLCipher adapter/key bridge is unapproved/unapplied: no encrypted-file/WAL proof,
real power failure, kill/relaunch persistence, key invalidation, backup/restore or
interrupted durable logout was tested. Journal unit tests and controller recreation
are not process-death evidence. See FLUTTER_SECURE_STORAGE_APPROVAL_PROPOSAL.md.
