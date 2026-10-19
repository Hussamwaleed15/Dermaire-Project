import '../experiments/experiment_contract.dart';
import '../integration/configuration_receipt.dart';
import '../integration/operation_identity.dart';
import '../routine/routine_controller.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import 'operation_journal.dart';

/// The two actual ConfigurationAttempt domains. Read-only; no journal activation
/// or mutation dispatch. Body fingerprints remain correlation metadata only.
class ConfigurationReceiptReader implements JournalReceiptReader {
  ConfigurationReceiptReader(this.api, this.generation);
  final ApiService api;
  final int generation;

  void guard(OperationIdentity i) {
    if (!api.isCurrentSession(generation) ||
        api.authenticatedOwner != i.owner ||
        i.role != 'patient' ||
        !api.canReadPatientClinicalStatus) {
      throw RecoverySessionLost();
    }
  }

  ({String domain, String operation}) contract(OperationIdentity i) {
    final resource = i.scope['resource_id'];
    for (final domain in ['routine', 'experiment']) {
      final root = domain == 'routine' ? 'routine/entries' : 'experiments';
      final receipts = domain == 'routine'
          ? 'routine/configuration-attempts'
          : 'experiments/operation-attempts';
      final operations = domain == 'routine'
          ? ['create', 'update', 'stop']
          : [
              'create',
              'edit',
              'activate',
              'finish',
              'cancel',
              'evaluate',
              'legacy_pause',
            ];
      for (final operation in operations) {
        final path = operation == 'create'
            ? root
            : domain == 'routine' || ['edit', 'cancel'].contains(operation)
            ? '$root/$resource'
            : '$root/$resource/${operation == 'legacy_pause' ? 'toggle-pause' : operation}';
        if (i.receiptPath != '$receipts/$operation' || i.path != path) continue;
        if (operation == 'create'
            ? resource != null
            : resource == null || i.scope['expected_revision'] is! int) {
          break;
        }
        if (operation == 'activate' &&
            i.scope['expected_routine_revision'] is! int) {
          break;
        }
        return (domain: domain, operation: operation);
      }
    }
    throw const FormatException(
      'No configuration receipt contract for this identity',
    );
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    final c = contract(i);
    try {
      final resource = i.scope['resource_id'];
      final raw = await api.patientResource(
        '${i.receiptPath}/${i.key}${resource == null ? '' : '?resource_id=$resource'}',
        generation,
      );
      guard(i);
      final r = ConfigurationReceipt.parseIdentity(
        raw,
        owner: i.owner,
        domain: c.domain,
        operation: c.operation,
        resource: resource as String?,
        expectedRevision: i.scope['expected_revision'] as int?,
      );
      final original = r.original;
      if (original != null &&
          (c.operation == 'evaluate'
              ? !ExperimentContract.result(original, r.resource!)
              : c.domain == 'routine'
              ? !RoutineController.validRow(original, 'user_configured') ||
                    original['id'] != r.resource ||
                    original['revision'] != r.revision
              : !ExperimentContract.valid(original, i.owner) ||
                    original['id'] != r.resource ||
                    original['revision'] != r.revision)) {
        throw const FormatException('Invalid original configuration snapshot');
      }
      return ReceiptEvidence(
        switch (r.status) {
          'committed' => ReceiptOutcome.committed,
          'unknown' => ReceiptOutcome.unknown,
          _ => ReceiptOutcome.expired,
        },
        resource: r.resource,
        revision: r.revision,
      );
    } on RequestFailure catch (e) {
      if (e.kind == RequestFailureKind.denied) throw RecoveryPermissionLost();
      rethrow;
    }
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    guard(i);
    final c = contract(i);
    if (r.outcome != ReceiptOutcome.committed ||
        r.resource == null ||
        r.revision == null) {
      return false;
    }
    try {
      final root = c.domain == 'routine' ? 'routine/entries' : 'experiments';
      final raw = await api.patientResource('$root/${r.resource}', generation);
      guard(i);
      if (raw is! Map<String, dynamic> ||
          raw['id'] != r.resource ||
          (c.domain == 'routine'
              ? !RoutineController.validRow(raw, 'user_configured')
              : !ExperimentContract.valid(raw, i.owner))) {
        throw const FormatException('Invalid current configuration');
      }
      // Revision is current resource evidence only. An activation may also change
      // a routine and product; no metadata-only adapter declares those current.
      // Evaluation receipts likewise do not prove the current derived result.
      if (['activate', 'evaluate'].contains(c.operation)) return false;
      return raw['revision'] == r.revision;
    } on PatientResourceMissing {
      guard(i);
      return false; // Stops/cancellations preserve history, never imply deletion.
    } on RequestFailure catch (e) {
      if (e.kind == RequestFailureKind.denied) throw RecoveryPermissionLost();
      rethrow;
    }
  }
}
