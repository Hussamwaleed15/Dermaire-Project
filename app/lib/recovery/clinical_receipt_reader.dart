import '../doctor/clinical_operation_receipt.dart';
import '../doctor/doctor_models.dart';
import '../doctor/doctor_evidence_models.dart';
import '../integration/operation_identity.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import 'operation_journal.dart';

/// Clinical original receipts only. No narrative is returned or persisted.
class ClinicalReceiptReader implements JournalReceiptReader {
  ClinicalReceiptReader(this.api, this.generation);
  final ApiService api;
  final int generation;
  void guard(OperationIdentity i) {
    if (!api.isCurrentSession(generation) ||
        i.owner != api.authenticatedOwner ||
        i.role != 'doctor' ||
        !api.canReadDoctorWorkspace) {
      throw RecoverySessionLost();
    }
  }

  String contract(OperationIdentity i) {
    final patient = i.scope['patient_id'], grant = i.scope['access_id'];
    if (patient == null || grant == null || i.scope['doctor_id'] != i.owner) {
      throw const FormatException('Missing original clinical scope');
    }
    for (final kind in ['note', 'review']) {
      if (i.path ==
              'doctor/patients/$patient/${kind == 'note' ? 'notes' : 'reviews'}' &&
          i.receiptPath == 'doctor/patients/$patient/attempts/$kind' &&
          (kind == 'note' || i.scope['expected_sequence'] is int)) {
        return kind;
      }
    }
    throw const FormatException('Unsupported clinical receipt identity');
  }

  Future<void> authorize(OperationIdentity i) async {
    guard(i);
    final raw = await api.doctorResource(
      'patients/${i.scope['patient_id']}',
      generation,
    );
    guard(i);
    if (raw is! Map<String, dynamic> ||
        raw['patient_id'] != i.scope['patient_id']) {
      throw const FormatException('Wrong current patient');
    }
    final grant = DoctorGrant.fromApi(
      raw['access'] as Map<String, dynamic>,
      patient: i.scope['patient_id'] as String,
      doctor: i.owner,
    );
    if (grant.id != i.scope['access_id'] ||
        !grant.active(DateTime.now().toUtc()) ||
        grant.effectiveScopes != null &&
            !grant.effectiveScopes!.contains('VIEW')) {
      throw RecoveryPermissionLost();
    }
  }

  Never denied(RequestFailure e) {
    if ([
      RequestFailureKind.denied,
      RequestFailureKind.rejected,
    ].contains(e.kind)) {
      throw RecoveryPermissionLost();
    }
    throw e;
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    final kind = contract(i);
    try {
      await authorize(i);
      final raw = await api.doctorResource(
        '${i.receiptPath.substring('doctor/'.length)}/${i.key}',
        generation,
      );
      guard(i);
      await authorize(i);
      final receipt = ClinicalOperationReceipt.parse(
        raw,
        doctor: i.owner,
        patient: i.scope['patient_id'] as String,
        grant: i.scope['access_id'] as String,
        operation: kind,
        expectedSequence: i.scope['expected_sequence'] as int?,
        resource: i.scope['resource_id'] as String?,
      );
      return ReceiptEvidence(
        switch (receipt.status) {
          'committed' => ReceiptOutcome.committed,
          'unknown' => ReceiptOutcome.unknown,
          _ => ReceiptOutcome.expired,
        },
        resource: receipt.resource,
        revision: kind == 'review'
            ? (receipt.original?['sequence'] as int?)
            : null,
      );
    } on RequestFailure catch (e) {
      denied(e);
    }
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    guard(i);
    final kind = contract(i);
    if (r.outcome != ReceiptOutcome.committed || r.resource == null) {
      return false;
    }
    try {
      await authorize(i);
      final raw = await api.doctorResource(
        'patients/${i.scope['patient_id']}/${kind == 'note' ? 'notes' : 'reviews'}',
        generation,
      );
      guard(i);
      bool found;
      if (kind == 'note') {
        if (raw is! List) throw const FormatException('Invalid current notes');
        final notes = raw
            .map(
              (v) => DoctorNote.fromApi(
                v as Map<String, dynamic>,
                i.scope['patient_id'] as String,
              ),
            )
            .toList();
        if (notes.map((v) => v.id).toSet().length != notes.length) {
          throw const FormatException('Duplicate note identity');
        }
        found = notes.any((v) => v.id == r.resource && v.doctor == i.owner);
      } else {
        final review = DoctorReviewRead.fromApi(
          raw as Map<String, dynamic>,
          i.scope['patient_id'] as String,
        );
        found =
            review.decision?.id == r.resource &&
            review.decision?.doctor == i.owner &&
            review.decision?.accessId == i.scope['access_id'] &&
            review.sequence == r.revision;
      }
      await authorize(i);
      return found;
    } on RequestFailure catch (e) {
      denied(e);
    }
  }
}
