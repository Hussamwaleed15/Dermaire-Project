import 'dart:convert';
import '../integration/operation_identity.dart';

enum JournalPhase {
  prepared,
  unconfirmed,
  unresolved,
  receiptRecorded,
  reviewRequired,
  permissionDenied,
  expired,
}

/// Metadata only. Expiry is a local review deadline, not a server receipt claim.
class JournalEntry {
  JournalEntry({
    required this.identity,
    required this.createdAt,
    required this.reviewAt,
    required this.phase,
  }) {
    if (!createdAt.isUtc ||
        !reviewAt.isUtc ||
        !reviewAt.isAfter(createdAt) ||
        reviewAt.difference(createdAt) > const Duration(days: 30)) {
      throw const FormatException('Invalid journal retention');
    }
  }
  final OperationIdentity identity;
  final DateTime createdAt, reviewAt;
  final JournalPhase phase;
  JournalEntry transition(JournalPhase next) {
    if (next == JournalPhase.prepared) {
      throw StateError('An existing identity cannot become a new request');
    }
    return JournalEntry(
      identity: identity,
      createdAt: createdAt,
      reviewAt: reviewAt,
      phase: next,
    );
  }

  String encode() => jsonEncode({
    'schema': 1,
    'identity': identity.toJson(),
    'created_at': createdAt.toIso8601String(),
    'review_at': reviewAt.toIso8601String(),
    'phase': phase.name,
  });
  factory JournalEntry.decode(String input) {
    if (utf8.encode(input).length > 8192) {
      throw const FormatException('Oversized journal');
    }
    try {
      final v = jsonDecode(input) as Map<String, dynamic>;
      if (v.length != 5 || v['schema'] != 1) {
        throw const FormatException('Unsupported journal schema');
      }
      return JournalEntry(
        identity: OperationIdentity.fromJson(
          v['identity'] as Map<String, dynamic>,
        ),
        createdAt: DateTime.parse(v['created_at'] as String),
        reviewAt: DateTime.parse(v['review_at'] as String),
        phase: JournalPhase.values.byName(v['phase'] as String),
      );
    } catch (_) {
      // Do not echo corrupt plaintext, identifiers or ciphertext into logs/UI.
      throw const FormatException(
        'Unreadable operation journal; recovery locked',
      );
    }
  }
}

/// An implementation must acknowledge only after encrypted durable transaction
/// commit, use namespace+key uniqueness/CAS, and reject quarantined namespaces.
/// EncryptedOperationJournal supplies a disk adapter for isolated qualification;
/// production mutation composition remains disabled.
abstract interface class OperationJournal {
  Future<JournalEntry?> read(OperationIdentity identity);
  Future<void> insertDurably(JournalEntry entry);
  Future<void> replaceDurably(JournalEntry entry, JournalPhase expected);
}

enum ReceiptOutcome { committed, unknown, expired }

class ReceiptEvidence {
  const ReceiptEvidence(this.outcome, {this.resource, this.revision});
  final ReceiptOutcome outcome;
  final String? resource;
  final int? revision;
}

/// Domain adapters must validate original owner/role/operation/resource/grant and
/// actual backend schema. A receipt is historical; current reads are separate.
abstract interface class JournalReceiptReader {
  Future<ReceiptEvidence> lookup(OperationIdentity original);
  Future<bool> verifyCurrent(
    OperationIdentity original,
    ReceiptEvidence receipt,
  );
}

class RecoveryPermissionLost implements Exception {}

class RecoverySessionLost implements Exception {}

class JournalCoordinator {
  JournalCoordinator(this.journal, {required this.active, required this.now});
  final OperationJournal journal;
  final bool Function(OperationIdentity) active;
  final DateTime Function() now;
  final Set<String> _inFlight = {};
  String namespace(OperationIdentity i) => '${i.owner}:${i.role}:${i.key}';
  void guard(OperationIdentity i) {
    if (!active(i)) throw RecoverySessionLost();
  }

  /// Only for a brand-new reviewed request. Existing identities NEVER replay.
  /// The sender must also enforce its captured API session/generation.
  Future<JournalPhase> prepareAndSend(
    JournalEntry entry,
    Future<void> Function() sendOriginal,
  ) async {
    final i = entry.identity, lock = namespace(entry.identity);
    guard(i);
    if (!_inFlight.add(lock)) {
      throw StateError('Original operation already active');
    }
    try {
      if (entry.phase != JournalPhase.prepared ||
          !now().isBefore(entry.reviewAt)) {
        throw StateError('Original operation requires review');
      }
      if (await journal.read(i) != null) {
        throw StateError('Existing original must be reconciled');
      }
      guard(i);
      await journal.insertDurably(entry);
      guard(i);
      // A crash immediately before send is also ambiguous. Persist that fact
      // first; failure of either transaction means no send.
      await journal.replaceDurably(
        entry.transition(JournalPhase.unconfirmed),
        JournalPhase.prepared,
      );
      guard(i);
      try {
        await sendOriginal();
      } catch (_) {
        // Lost responses cannot cause automatic retry, deletion or a new key.
      }
      guard(i);
      return JournalPhase.unconfirmed;
    } finally {
      _inFlight.remove(lock);
    }
  }

  Future<JournalPhase> reconcile(
    OperationIdentity i,
    JournalReceiptReader reader,
  ) async {
    final lock = namespace(i);
    guard(i);
    if (!_inFlight.add(lock)) {
      throw StateError('Original operation already active');
    }
    try {
      final entry = await journal.read(i);
      guard(i);
      if (entry == null ||
          entry.identity.encodeIdentity() != i.encodeIdentity()) {
        throw const FormatException('Original identity does not match journal');
      }
      var next = JournalPhase.unresolved;
      if (!now().isBefore(entry.reviewAt)) {
        next = JournalPhase.expired;
      } else {
        try {
          final receipt = await reader.lookup(i);
          guard(i);
          next = switch (receipt.outcome) {
            ReceiptOutcome.unknown => JournalPhase.unresolved,
            ReceiptOutcome.expired => JournalPhase.expired,
            ReceiptOutcome.committed =>
              await reader.verifyCurrent(i, receipt)
                  ? JournalPhase.receiptRecorded
                  : JournalPhase.reviewRequired,
          };
          guard(i);
        } on RecoveryPermissionLost {
          guard(i);
          next = JournalPhase.permissionDenied;
        }
      }
      await journal.replaceDurably(entry.transition(next), entry.phase);
      guard(i);
      return next;
    } finally {
      _inFlight.remove(lock);
    }
  }
}

extension on OperationIdentity {
  String encodeIdentity() => jsonEncode(toJson());
}

/// Close all namespace access first. Each platform action is idempotent and must
/// acknowledge actual completion; failure leaves the durable deletion fence.
abstract interface class JournalCleanup {
  Future<void> fenceDurably(String owner, String role);
  Future<void> destroyKey(String owner, String role);
  Future<void> eraseFiles(String owner, String role);
}

Future<void> cleanupJournal(
  JournalCleanup platform,
  String owner,
  String role,
) async {
  await platform.fenceDurably(owner, role);
  await platform.destroyKey(owner, role);
  await platform.eraseFiles(owner, role);
}
