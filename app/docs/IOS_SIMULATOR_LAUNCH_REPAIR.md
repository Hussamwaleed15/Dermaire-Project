# iOS simulator launch repair and SwiftPM lockfiles

Verified on 2026-10-13 from main source
`acc03185ced2ff8a72b1cd3775b8c48a4140ebea`. The repair scope is complete after
normal commit/push verification recorded in the delivery report. No M5 work.

## Reproduced failure and root cause

The user's app did not open. The normal development command, from `app/`, was:

```sh
flutter run -d DB96C794-96EA-4BB6-BDB3-301F8F385FB9 --debug --target lib/main.dart
```

It failed during compilation, before installation/startup. Xcode reported:

```text
The package product 'file-picker-darwin' requires minimum platform version 14.0
for the iOS platform, but this target supports 13.0
(in target 'FlutterGeneratedPluginSwiftPackage')
```

Actual resolved `file_picker_darwin` 2.0.0 has `.iOS("14.0")` in its native
`darwin/file_picker_darwin/Package.swift`. Runner's Debug/Release/Profile project
settings were 13.0, and Flutter generated its top-level plugin package as 13.0.
This platform mismatch, not a corrupt SwiftPM lockfile, prevented the build.

## Minimal fix and files

- `ios/Runner.xcodeproj/project.pbxproj`: raise the three project deployment
  settings to 14.0. Bundle ID, signing, entitlements, permissions, ATS, native
  registration, schemes, application entrypoint and UX remain unchanged.
- `test/ios_dependency_configuration_test.dart`: two regressions compare all
  configured iOS deployment floors to the actual resolved file-picker manifest
  and validate immutable public pins in all four source-owned lockfiles.
- Four `Package.resolved` files below: add their existing unchanged contents.
- `README.md`: current iOS minimum and development instructions/link.
- This documentation.

Flutter regenerated `.iOS("14.0")` in its ignored plugin package automatically.
No generated manifest, SDK, dependency cache, DerivedData, absolute local path,
CocoaPods file or signing secret was patched/committed. `AppFrameworkInfo.plist`
has no separate MinimumOSVersion override and was not changed. The built Runner
Info.plist confirms MinimumOSVersion 14.0 and bundle `com.example.dermaireApp`;
Runner is an arm64 simulator executable. Existing iOS 13 support is no longer
possible with this resolved plugin: the application's native minimum is now 14.
No package upgrade/downgrade, Android or Dart product-code change was needed.

## Development environment

| Item | Verified value |
|---|---|
| macOS | 26.6.2 /25G83, Apple Silicon arm64 |
| Xcode | 26.0.1 /17A400 |
| Developer directory | /Applications/Xcode.app/Contents/Developer |
| iOS and simulator SDK | 26.0 |
| Installed simulator runtime | iOS 26.0, runtime build 26.0.1 /23A8464 |
| Device | iPhone 17, DB96C794-96EA-4BB6-BDB3-301F8F385FB9, already booted |
| Flutter | 3.44.8 stable, framework 058e0af2c2, engine 0cd610717b |
| Dart | 3.12.2 |
| Swift | Apple Swift 6.2, swift-driver 1.127.14.1 |
| Ruby | system 2.6.10; not used by this SPM build |
| CocoaPods | not installed; no Podfile/Podfile.lock in this SPM project |

Flutter doctor warns about CocoaPods and unrelated missing Android SDK/Chrome.
The actual simulator build and launch work through SwiftPM for camera,
file_picker_darwin, Google Sign-In, permission_handler and shared_preferences;
no CocoaPods installation was required. A first sandboxed simctl query could not
reach CoreSimulatorService; repeating the inventory with authorized host access
found the installed runtime and booted device. This was an execution sandbox
restriction, not a missing simulator/runtime on the Mac.

## Four-file SwiftPM inventory

All are legitimate application-owned Xcode shared-data lockfiles, not build or
cache directories. None are ignored. Both workspace entry modes are retained.
All four share the same resolved Google Sign-In transitive graph and are included
in Git intentionally; macOS native source/configuration was not changed.

| Repository path | Owner / use | Decision |
|---|---|---|
| app/ios/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | iOS project internal workspace, opening Runner.xcodeproj | Track unchanged |
| app/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved | iOS external workspace, normal Flutter build | Track unchanged |
| app/macos/Runner.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved | macOS project internal workspace | Track unchanged |
| app/macos/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved | macOS external workspace | Track unchanged |

Lockfile format 2, eight pins each. Public HTTPS GitHub URLs only, no credentials,
private records, machine paths, query authentication or mutable branch pins.
Each includes a version and immutable 40-character revision.

| Identity | Version | Revision |
|---|---|---|
| app-check | 11.3.2 | 97f7d74dd0e8f3d0fe5fc75cc8957aa73bdc948a |
| appauth-ios | 1.7.6 | 2781038865a80e2c425a1da12cc1327bcd56501f |
| googlesignin-ios | 8.0.0 | 65fb3f1aa6ffbfdc79c4e22178a55cd91561f5e9 |
| googleutilities | 8.1.4 | cc31f5ed464b111f877ce8554cbef4455d410d91 |
| gtm-session-fetcher | 3.5.0 | a2ab612cb980066ee56d90d60d8462992c07f24b |
| gtmappauth | 4.1.1 | 5d7d66f647400952b1758b230e019b07c0b4b22a |
| interop-ios-for-google-sdks | 101.0.0 | 040d087ac2267d2ddd4cca36c757d1c6a05fdbfe |
| promises | 2.4.1 | f4a19a3c313dc2616c70bb49d29a799fb16be837 |

SHA-256 for every file, unchanged before/after actual iOS build/run, macOS
package resolution and comparison with the fresh source snapshot:
`1025d5815b0a2c62aba3b3cefe0c509e2411c177cb01ad118cbbb818bee2e8f6`.
No one of the four was excluded or discarded. Generated native integration,
SourcePackages, plugin registrants, build output and DerivedData remain ignored.
macOS workspace package resolution succeeded; macOS app build/launch was not part
of this task. No standalone Swift package `.swiftpm` cache was added.

## Verification and actual launch

- `flutter analyze`: No issues found.
- Full `flutter test`: 1104 passed, preserving 1102 prior tests plus 2 new tests.
  Existing fake transport and production-host rejection remain intact.
- `flutter build ios --simulator --debug --target lib/main.dart`: BUILD SUCCEEDED;
  actual `build/ios/iphonesimulator/Runner.app`, arm64, minimum14.0.
- Normal `flutter run` rebuilt, installed and launched the real bundle on the
  booted iPhone 17; Flutter connected to its view and initialized its engine.
- Observed Runner PID 27012 remained alive for more than 6 minutes and after `d`
  detached the Flutter development session. No immediate termination, unhandled
  Flutter exception, fatal startup error or lost connection was observed.
- Actual native Simulator accessibility/screen inspection showed Welcome with
  the Dermaire logo and existing dark theme. Welcome → Sign In → Back → Create
  Account → Back all worked. No credentials were entered, no account created,
  no Google OAuth, consent bypass or production API action was performed.
- Screenshots of Welcome, Sign In, empty Create Account and stable Welcome after
  detach are supplied with the delivery report. The simulator is left running.

Build notes: Run Script/Thin Binary intentionally execute every build; AppIntents
metadata extraction was skipped because there is no AppIntents framework. Flutter
also probes missing NSBonjourServices/NSLocalNetworkUsageDescription metadata;
these probes did not prevent its actual service connection. No broad plist,
ATS/signing relaxation or new entitlement was introduced to silence warnings.
The simulator check verifies startup/local entry navigation, not authenticated
backend functionality, real camera quality, device distribution or production QA.

## Reproducibility and observed workspace limitation

An independent source snapshot used tracked main plus the exact intended three
setting changes, regression file and four locks. It copied no `.dart_tool`, build,
Flutter ephemeral package or DerivedData. `flutter pub get` regenerated dependency
integration and a fresh simulator debug build succeeded from a local `/private/tmp`
checkout. The generated plugin floor was 14.0 and all pin files matched. Installed
Flutter/pub/Xcode toolchain caches were reusable; no native cache was hand-patched.

A separate fresh snapshot under this Mac's Documents folder failed ad-hoc signing
with `resource fork, Finder information, or similar detritus not allowed` on the
copied Flutter.framework. That framework directory contained com.apple.FinderInfo
and com.apple.fileprovider.fpfs#P metadata. The same source built outside that
File Provider-managed path without an SDK/cache/signing change. This is a separate
observed workspace-metadata limitation, not the original iOS 13 dependency error.
Use a normal local developer checkout outside File Provider-synchronized folders,
as the existing `/Users/amrabdallah/Dermaire-Project` checkout does. No personal
files, SDK artifacts or unrelated caches were deleted/cleared.

On another Mac with compatible installed Xcode/runtime and Flutter 3.44.8:

```sh
# From the repository's app directory:
flutter pub get
flutter analyze
flutter test
flutter build ios --simulator --debug --target lib/main.dart
flutter devices
flutter run -d <available-iPhone-simulator-UUID> --debug --target lib/main.dart
```

SwiftPM must be enabled in Flutter; this installation already has it enabled. If
an installation has explicitly disabled it, enable it with Flutter's supported
`flutter config --enable-swift-package-manager` before preparing this SPM project.
Generated native files are regenerated by Flutter, not committed or manually
patched. Open `ios/Runner.xcworkspace` with Runner/Debug and an installed simulator
if using Xcode after Flutter preparation. A fresh dependency download requires
network access to pub.dev/GitHub and normal Xcode SDK availability. Simulator debug
launch needs no distribution certificate or new Apple Developer account setting.

Backend, Azure, DB, AI/provider configuration, Production, Tester Client and
unrelated Android functionality were untouched. No production build/deployment
or product milestone was started. No necessary manual repair step remains on
this Mac; use the running Simulator or the normal Flutter command above.
