# L9/L10 — isolated patient workflow and device execution

## Evidence on2026-10-18

flutter doctor -v: Flutter3.44.8/Dart3.12.2; Android SDK not found; Xcode26.0.1
installed, CocoaPods absent. Existing iOS SwiftPM setup preserved. flutter devices
--machine lists only macOS. flutter emulators reports no emulator sources.
No Android/iOS smoke test ran; no SDK, runtime image or CocoaPods was installed.
No native project configuration was edited. CocoaPods absence alone does not prove
that the existing SwiftPM project cannot build.

## Executable tests

From app/ on the current checkout:

```sh
flutter pub get
flutter analyze
flutter test test/wave_withdrawal_workflow_test.dart
flutter test
```

A shared scenario in test/support/withdrawal_workflow.dart drives real entry,
selective grant withdrawal, comparison-plan participation withdrawal, separate
job cancellation, logout and accountB isolation. It checks untouched other grants,
original identities, no fabricated safety acceptance/AppShell, no clinical-purpose
or image display, no carried operation identities and no prior-account clinician.
Four host variants cover light/dark,390px/320px,100%/200% and reduced motion.
Every HTTP call is a contract-faithful MockClient request to flutter-tests.invalid;
other hosts are rejected before network I/O. SharedPreferences uses a mock store.
No real OAuth or Production/staging data is used.

The SAME scenario has an SDK integration_test entry:
integration_test/withdrawal_smoke_test.dart. This file is statically analyzed;
its device execution is NOT included in the host flutter test result.
After Amr approves any required host/native setup and a supported Android/iOS
device is already available, select its actual ID from flutter devices, then run:

```sh
flutter doctor -v
flutter devices
flutter emulators
: "${DERMAIRE_TEST_DEVICE_ID:?Set an available approved Android or iOS device ID}"
flutter test integration_test/withdrawal_smoke_test.dart -d "$DERMAIRE_TEST_DEVICE_ID"
```

The harness uses a synthetic endpoint and intercepted HTTP throughout. Do not run
lib/main.dart with default production URL for this validation. Do not use real
accounts, camera uploads or Google OAuth. Do not add SDK/images/signing changes
or change SwiftPM/CocoaPods merely to make the smoke test start without approval.

## Limits and remaining runtime work

Host widgets prove deterministic Flutter behavior only. The device entry does not
prove a native camera permission flow, Google OAuth, secure storage durability,
Push delivery, inference correctness or backend E2E. It does not persist or recover
a process-death journal. Runtime plugin/signing/build compatibility remains untested
until device execution actually completes. Capture, offline/relaunch, protected
storage crash injection and the full patient/doctor roadmap need additional approved
runtime scenarios. Never substitute controller recreation for process restart.
