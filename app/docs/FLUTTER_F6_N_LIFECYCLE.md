# Secure journal lifecycle and rollout boundary — F6-N

This adapter has NO production composition. Existing controllers remain memory-only.
Tests explicitly construct JournalPlatform/EncryptedOperationJournal/
SecureRecoverySession. No build define can enable journaled production mutations.
The simulator qualification exception exists ONLY under integration_test/, requires
an explicit debug define, and catches only native fileProtectionMismatch. It is
not a successful strict-production protection acknowledgment.

| Event | Implemented policy |
|---|---|
| Reauthentication/restart | Require current account/role/safety authorization callback; encrypted binding must agree. Enumerate minimum identity; explicit domain reader then separately current resource. Actual product reader supported; other domains need their own verified receipt readers before rollout. |
| Session expiry/401/lock/background | Caller synchronously invalidates authorization/hides views and calls suspend; close DB, preserve encrypted minimum identity. Native WhenUnlocked key access and complete file protection fail closed. No lifecycle observer/startup wiring is activated in production. New authorized composition required, no automatic resume/replay. |
| Explicit logout/account deletion | Hide first; suspend current access; fence namespace durably, destroy key, remove namespace DB/WAL/SHM/temp/wrapped files and sync parent. Fence persists permanently. Retry cleanup via eraseNamespace without opening DB. Failure does not unlock/rekey. Existing account deletion workflow remains unchanged until separate rollout. |
| Account change | New namespace from installation random epoch+owner+role. Old active callback/generation must become false; late replies rejected. No raw result is restored from receipts to another account. |
| Grant/consent withdrawal | Reader revalidates original authority; preserve permissionDenied minimum identity, never show prior private result. Caller can explicitly erase namespace. No generic receipt claims for legacy unkeyed operations/Agent login-bound sessions. |
| Missing/invalid key; lost DB with existing key | Load never creates. Native create refuses existing protected/wrapped key or files. No fresh empty journal over old uncertainty. Recovery remains unavailable, requires explicit review. |
| Corrupt ciphertext/row/schema | No wipe, fallback, new key or silent skipped row. Current schema1 only; future/legacy0 rejected. Fresh install has no journal schema to migrate. A future supported migration must be transactional and tested; no upgrade migration is claimed by this wave. |
| Review deadline | UTC<=30days; elapsed deadline marks expired and retains replacement lock. Not backend receipt expiry and not permission to resend. Minimum unresolved metadata remains until explicit review/cleanup; no silent timed erasure or unlimited private payload retention (payloads never stored). |
| Reinstall/data clearing/OS restore | Epoch/file/Keystore/Keychain may be removed or survive differently. Missing epoch with old artifacts refuses initialization. ThisDeviceOnly/no-backup requested. Local total data loss cannot prove an old server operation failed; no automatic replay, receipt discovery/current server review needed. No claim old identities can survive deliberate total erasure. |
| Rotation | No automatic key rotation or namespace renewal. Fenced namespace cannot reopen even after cleanup. Provisioning a fresh epoch/key needs an explicit reviewed lifecycle and current server-state review; not implemented as a bypass. |
| Cryptographic erasure | Key deletion and file cleanup implemented/acknowledged; physical flash, cached VM/native key copies, backup copies, reinstall Keychain orphans not proven erased. Best-effort Dart key-buffer zeroing only. |

SQLCipher WAL/FULL commits acknowledge the configured VFS/fsync contract, not universal
power-loss immunity. Actual mobile hardware full disk, failed fsync, power loss,
locked/unlocked Keychain, Keystore invalidation, backups/OEM transfers, app deletion,
interrupted platform cleanup and all supported ABIs remain rollout gates.

No additional Backend route is requested by local storage. Existing source receipts
are historical. Unknown is not rejection or proof no operation is in flight.
See existing FLUTTER_BACKEND_GAPS_FOR_HUSSAM.md; never invent a new key to work
around unknown/expired/permission-denied states. No production activation approved.
