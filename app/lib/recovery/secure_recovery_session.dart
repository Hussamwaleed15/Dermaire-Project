import '../integration/operation_identity.dart';
import 'encrypted_operation_journal.dart';
import 'journal_platform.dart';
import 'operation_journal.dart';

/// Explicit composition for isolated qualification only. Production entry and
/// mutation controllers do not construct this class. No environment flag enables
/// production journaling. Reauthentication and current consent remain mandatory.
class SecureRecoverySession {
  SecureRecoverySession._(this.journal, this._authorized, this.now);
  final EncryptedOperationJournal journal;
  final bool Function() _authorized;
  final DateTime Function() now;
  bool _closed = false;
  static Future<SecureRecoverySession> open({
    required JournalPlatform platform,
    required String owner,
    required String role,
    required bool Function() authorized,
    required DateTime Function() now,
  }) async {
    if (!authorized()) throw RecoverySessionLost();
    final ns = await JournalNamespace.resolve(
      platform,
      owner: owner,
      role: role,
    );
    if (!authorized()) throw RecoverySessionLost();
    final journal = await EncryptedOperationJournal.open(
      platform: platform,
      namespace: ns,
      active: authorized,
    );
    return SecureRecoverySession._(journal, authorized, now);
  }

  bool _active(OperationIdentity i) =>
      !_closed && _authorized() && journal.namespace.owns(i);
  late final JournalCoordinator _coordinator = JournalCoordinator(
    journal,
    active: _active,
    now: now,
  );
  Future<List<JournalEntry>> restore() async {
    if (_closed || !_authorized()) throw RecoverySessionLost();
    return journal.pending();
  }

  Future<JournalPhase> prepareAndSend(
    JournalEntry entry,
    Future<void> Function() sendOriginal,
  ) => _coordinator.prepareAndSend(entry, sendOriginal);
  Future<JournalPhase> reconcile(
    OperationIdentity identity,
    JournalReceiptReader reader,
  ) => _coordinator.reconcile(identity, reader);

  /// Session expiry/temporary authorization loss: hide access, retain encrypted
  /// identities. New authorized composition still must revalidate actual receipts.
  void suspend() {
    _closed = true;
    journal.close();
  }

  /// Explicit logout/account deletion/withdrawal: hide first, then durable fence,
  /// key destruction and files. Failures remain fenced, never permit a new key.
  Future<void> erase() async {
    _closed = true;
    await journal.erase();
  }
}
