import '../clinical/clinical_models.dart' show timestamp;
import '../integration/contract.dart';
import 'doctor_models.dart';
import 'doctor_evidence_models.dart';

/// Actual clinical_attempts.out envelope. Never a generic receipt or current
/// clinical decision. Unknown carries no original result and retry_safe=false.
class ClinicalOperationReceipt {
  ClinicalOperationReceipt._(this.status, this.resource, this.original);
  final String status;
  final String? resource;
  final Map<String, dynamic>? original;

  factory ClinicalOperationReceipt.parse(
    Object? value, {
    required String doctor,
    required String patient,
    required String grant,
    required String operation,
    int? expectedSequence,
    String? resource,
  }) {
    if (value is! Map<String, dynamic> ||
        value['schema_version'] != 1 ||
        !['note', 'review'].contains(operation) ||
        !['unknown', 'committed', 'expired'].contains(value['status'])) {
      throw const FormatException('Invalid clinical attempt');
    }
    resourceId(value['attempt_id']);
    final status = value['status'] as String;
    if (status == 'unknown') {
      if (value['result'] != null ||
          value['retry_safe'] != false ||
          [
            'resource_id',
            'recorded_at',
            'expires_at',
          ].any((k) => value[k] != null)) {
        throw const FormatException(
          'Unknown clinical outcome is not rejection',
        );
      }
      return ClinicalOperationReceipt._(status, null, null);
    }
    final id = resourceId(value['resource_id']);
    if (value['actor_id'] != doctor ||
        value['patient_id'] != patient ||
        value['access_id'] != grant ||
        value['operation'] != operation ||
        resource != null && resource != id ||
        value['snapshot_basis'] != 'original_committed_not_current') {
      throw const FormatException('Clinical attempt scope changed');
    }
    final recorded = timestamp(value['recorded_at']),
        expires = timestamp(value['expires_at']);
    if (!expires.isAfter(recorded) ||
        expires.difference(recorded) > const Duration(days: 30)) {
      throw const FormatException('Invalid clinical receipt retention');
    }
    if (status == 'expired') {
      if (value['result'] != null) {
        throw const FormatException('Expired clinical content');
      }
      return ClinicalOperationReceipt._(status, id, null);
    }
    final result = value['result'];
    if (result == null) return ClinicalOperationReceipt._(status, id, null);
    if (result is! Map<String, dynamic> ||
        result['id'] != id ||
        result['doctor_id'] != doctor) {
      throw const FormatException('Wrong original clinical result');
    }
    if (result['schema_version'] !=
        (operation == 'note' ? 'clinical-note-1.0' : 'clinical-review-1.0')) {
      throw const FormatException('Unsupported original clinical schema');
    }
    if (operation == 'note') {
      DoctorNote.fromApi(result, patient);
    } else {
      final review = DoctorDecision.fromApi(result, patient);
      if (review.accessId != grant ||
          expectedSequence != null && review.sequence != expectedSequence + 1) {
        throw const FormatException('Wrong original clinical sequence');
      }
    }
    return ClinicalOperationReceipt._(status, id, Map.unmodifiable(result));
  }
}
