import '../routine/adherence_operation.dart';
import '../routine/routine_controller.dart';
import '../integration/operation_identity.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import 'operation_journal.dart';

/// AdherenceAttemptLookup describes an immutable report and original configuration
/// revision, not the current routine or objective proof the product was used.
class AdherenceReceiptReader implements JournalReceiptReader {
  AdherenceReceiptReader(this.api, this.generation);
  final ApiService api;
  final int generation;
  void guard(OperationIdentity i) {
    if (!api.isCurrentSession(generation) ||
        api.authenticatedOwner != i.owner ||
        i.role != 'patient' ||
        !api.canReadPatientClinicalStatus) {
      throw RecoverySessionLost();
    }
    contract(i);
  }

  void contract(OperationIdentity i) {
    if (i.path != 'routine/adherence' ||
        i.receiptPath != 'routine/adherence/attempts') {
      throw const FormatException('Unsupported adherence receipt identity');
    }
  }

  AdherenceReceipt parse(Object? raw, OperationIdentity i) {
    final r = AdherenceReceipt.parseIdentity(raw, owner: i.owner);
    if (r.original != null &&
        !RoutineController.validRow(r.original!, 'user_reported')) {
      throw const FormatException('Invalid original reported-use snapshot');
    }
    return r;
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    try {
      final raw = await api.patientResource(
        '${i.receiptPath}/${i.key}',
        generation,
      );
      guard(i);
      final r = parse(raw, i);
      return ReceiptEvidence(
        switch (r.status) {
          'committed' => ReceiptOutcome.committed,
          'unknown' => ReceiptOutcome.unknown,
          _ => ReceiptOutcome.expired,
        },
        resource: r.resource,
        revision: r.configurationRevision,
      );
    } on RequestFailure catch (e) {
      if (e.kind == RequestFailureKind.denied) throw RecoveryPermissionLost();
      rethrow;
    }
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    guard(i);
    if (r.outcome != ReceiptOutcome.committed ||
        r.resource == null ||
        r.revision == null) {
      return false;
    }
    try {
      final seen = <String>{};
      // Offset history is not an MVCC snapshot. A bounded miss requires review;
      // it never proves deletion or permits replacement. Stop at5000 rows.
      for (int offset = 0; offset < 5000; offset += 100) {
        final raw = await api.patientResource(
          'routine/adherence?limit=100&offset=$offset',
          generation,
        );
        guard(i);
        if (raw is! List || raw.length > 100) {
          throw const FormatException('Invalid current report page');
        }
        for (final value in raw) {
          if (value is! Map<String, dynamic> ||
              !RoutineController.validRow(value, 'user_reported') ||
              !seen.add(value['id'] as String)) {
            throw const FormatException(
              'Invalid or overlapping report history',
            );
          }
          if (value['id'] == r.resource) {
            final nested = value['receipt'];
            if (nested is! Map<String, dynamic>) return false;
            final current = parse({
              ...nested,
              'result': nested['status'] == 'expired' ? null : value,
            }, i);
            return current.status == 'committed' &&
                current.resource == r.resource &&
                current.configurationRevision == r.revision;
          }
        }
        if (raw.length < 100) return false;
      }
      return false;
    } on RequestFailure catch (e) {
      if (e.kind == RequestFailureKind.denied) throw RecoveryPermissionLost();
      rethrow;
    }
  }
}
