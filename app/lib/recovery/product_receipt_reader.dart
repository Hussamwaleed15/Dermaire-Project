import '../integration/operation_identity.dart';
import '../products/product.dart';
import '../products/product_operation.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import 'operation_journal.dart';

/// Actual product receipts only. No generic interpretation of other domains.
class ProductReceiptReader implements JournalReceiptReader {
  ProductReceiptReader(this.api, this.generation);
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

  String kind(OperationIdentity i) {
    if (i.path == 'products' && i.receiptPath == 'products/attempts') {
      return 'create';
    }
    final resource = i.scope['resource_id'];
    if (resource != null && i.path == 'products/$resource') {
      for (final k in ['patch', 'delete']) {
        if (i.receiptPath == 'products/$resource/operation-attempts/$k' &&
            i.scope['expected_revision'] is int) {
          return k;
        }
      }
    }
    throw const FormatException(
      'No product receipt contract for this identity',
    );
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    final operation = kind(i);
    try {
      final raw = await api.patientResource(
        '${i.receiptPath}/${i.key}',
        generation,
      );
      guard(i);
      final r = ProductOperationReceipt.parseIdentity(
        raw,
        owner: i.owner,
        kind: operation,
        resource: i.scope['resource_id'] as String?,
        expectedRevision: i.scope['expected_revision'] as int?,
      );
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
    final operation = kind(i);
    if (r.outcome != ReceiptOutcome.committed ||
        r.resource == null ||
        r.revision == null) {
      return false;
    }
    try {
      final raw = await api.patientResource(
        'products/${r.resource}',
        generation,
      );
      guard(i);
      final product = Product.fromApi(raw as Map<String, dynamic>);
      if (product.id != r.resource || product.owner != i.owner) {
        throw const FormatException('Wrong current product');
      }
      return operation != 'delete' && product.serverRevision == r.revision;
    } on PatientResourceMissing {
      guard(i);
      return operation == 'delete';
    } on RequestFailure catch (e) {
      if (e.kind == RequestFailureKind.denied) throw RecoveryPermissionLost();
      rethrow;
    }
  }
}
