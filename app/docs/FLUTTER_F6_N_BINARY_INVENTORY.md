# Native library inventory — actual3.5.2 qualification
Exact sqlite3 package3.5.2 approved by Amr; native hook source:sqlcipher.
Actual resolved lockfile: hooks2.0.2/code_assets1.2.1/native_toolchain_c0.19.2/
record_use0.6.0. No overrides; Flutter3.44.8/Dart3.12.2/meta1.18 retained.

Official package hash-verified release artifacts:
- arm64 Android: b5a4be982aabc22ca89e7ffe7803952c41544d5f19cbc242fdd4a1d362d0fbae.
  ELF noteAPI24; PT_LOAD alignments16384 (static only; not16KB runtime qualification).
  Binary version string OpenSSL3.6.3 (9Jun2026); no Android execution performed.
- arm64 iOS device:17059d038aaa9019dc463b7bc1d09527716c68ff0f83c7da802d04463e633815;
  LC_BUILD_VERSION min12.0. Existing deployment target14 retained.
- arm64 iOS simulator:b8640f76fe8354e015eb96f389cefe2469be4fd95f70eb6daa2a379b5eef4ba3;
  min14.0. x64 simulator asset also packaged by Flutter.
- arm64 macOS:7987232e57c291e2aaf1cadc78ca3c54b133c8492e34704066bffee2bb21d1bb.

Host SQL runtime reports cipher_version4.18.0 community, SQLite3.53.4. iOS packaged
sqlcipher.framework is separate from systemSQLite, links Foundation/Security/
CoreFoundation/libSystem; universal arm64+x64 simulator binary3596KiB (not measured
APK/IPA release-size delta). Initial iOS native-assets build49.4s; incremental14.2s.
Runtime cipher gate still mandatory on every connection; packaging alone is no proof.

Source/license references:
https://pub.dev/packages/sqlite3/versions/3.5.2
https://github.com/simolus3/sqlite3.dart/blob/sqlite3-3.5.2/sqlite3/doc/hook.md
https://github.com/sqlcipher/sqlcipher/blob/v4.18.0/LICENSE.md
https://github.com/openssl/openssl/blob/openssl-3.6.3/LICENSE.txt
Binding MIT notice comes from packageLICENSE in Flutter license collection. Exact
SQLCipher and OpenSSL notices preserved as app assets. No commercial entitlement
or legal clearance implied. Other ABIs, Android build/packaging, physical-device
iOS14, hardware lock/key invalidation and complete vulnerability/SBOM qualification
remain rollout gates; only inspected artifacts are stated here.
