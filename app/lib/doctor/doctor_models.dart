import '../clinical/clinical_models.dart';

String doctorId(Object? value) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('Invalid clinical identity');
  }
  return value;
}

class DoctorGrant {
  DoctorGrant.fromApi(
    Map<String, dynamic> value, {
    required String patient,
    String? doctor,
  }) : id = doctorId(value['id']),
       patientId = doctorId(value['patient_id']),
       doctorIdValue = value['doctor_id'] == null
           ? null
           : doctorId(value['doctor_id']),
       status = text(value['status']),
       expiresAt = timestamp(value['expires_at'], naiveUtc: true),
       createdAt = timestamp(value['created_at'], naiveUtc: true),
       revokedAt = value['revoked_at'] == null
           ? null
           : timestamp(value['revoked_at'], naiveUtc: true),
       revokedBy = optionalText(value['revoked_by']) {
    if (patientId != patient ||
        value['granted_by'] != patient ||
        !['pending', 'active', 'revoked', 'expired'].contains(status) ||
        (doctor != null && doctorIdValue != doctor) ||
        (status == 'active' &&
            (doctorIdValue == null ||
                value['claimed_at'] == null ||
                value['revoked_at'] != null ||
                value['revoked_by'] != null))) {
      throw const FormatException('Unverified clinical grant');
    }
    if (value['claimed_at'] != null) {
      timestamp(value['claimed_at'], naiveUtc: true);
    }
    if (value['revoked_at'] != null) {
      timestamp(value['revoked_at'], naiveUtc: true);
    }
  }
  final String id, patientId, status;
  final String? doctorIdValue, revokedBy;
  final DateTime? revokedAt;
  bool get confirmedRevoked =>
      status == 'revoked' && revokedAt != null && revokedBy == patientId;

  final DateTime expiresAt, createdAt;
  bool active(DateTime now) => status == 'active' && now.isBefore(expiresAt);
}

enum PatientPriority { routine, review, urgent }

class DoctorPatient {
  const DoctorPatient({
    required this.id,
    required this.name,
    required this.lastCheckIn,
    required this.experiment,
    required this.priority,
    required this.activeProducts,
    this.followUp,
    this.fileClosed = false,
    this.grants = const [],
    this.safety,
  });
  factory DoctorPatient.fromApi(Map<String, dynamic> value, String doctor) {
    final id = doctorId(value['patient_id']);
    final experiment = value['active_experiment'];
    final grants = (value['access'] as List)
        .map(
          (g) => DoctorGrant.fromApi(
            g as Map<String, dynamic>,
            patient: id,
            doctor: doctor,
          ),
        )
        .toList();
    if (grants.isEmpty ||
        value['active_products_count'] is! int ||
        value['active_products_count'] < 0 ||
        (experiment != null && experiment is! String) ||
        !['routine', 'review', 'urgent'].contains(value['priority'])) {
      throw const FormatException('Unverified doctor patient list');
    }
    return DoctorPatient(
      id: id,
      name: text(value['full_name']),
      lastCheckIn: text(value['last_check_in']),
      experiment: experiment == null
          ? 'No active experiment recorded'
          : text(experiment),
      priority: PatientPriority.values.byName(value['priority'] as String),
      activeProducts: value['active_products_count'] as int,
      grants: List.unmodifiable(grants),
      safety: SafetyAssessment.fromApi(object(value['safety'])),
    );
  }
  final String id, name, lastCheckIn, experiment;
  final PatientPriority priority;
  final int activeProducts;
  final String? followUp;
  final bool fileClosed;
  final List<DoctorGrant> grants;
  final SafetyAssessment? safety;
  bool available(DateTime now) => grants.any((g) => g.active(now));
}

class DoctorNote {
  DoctorNote.fromApi(Map<String, dynamic> value, String patient)
    : id = doctorId(value['id']),
      doctor = doctorId(value['doctor_id']),
      content = text(value['content']),
      priority = text(value['priority']),
      visible = flag(value['patient_visible']),
      followUp = optionalText(value['follow_up']),
      createdAt = timestamp(value['created_at'], naiveUtc: true),
      wire = Map.unmodifiable(value) {
    if (value['patient_id'] != patient ||
        value['provenance'] != 'clinician_authored' ||
        !['routine', 'review', 'urgent'].contains(priority) ||
        content.length < 10 ||
        content.length > 1500) {
      throw const FormatException('Unverified clinical note');
    }
    timestamp(value['updated_at'], naiveUtc: true);
  }
  final String id, doctor, content, priority;
  final bool visible;
  final String? followUp;
  final DateTime createdAt;
  final Map<String, dynamic> wire;
}

class ClinicalAuditEvent {
  const ClinicalAuditEvent(this.action, this.timestamp);
  final String action;
  final DateTime timestamp;
}
