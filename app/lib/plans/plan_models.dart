import '../clinical/clinical_models.dart';
import '../integration/contract.dart';

class ClinicalPlan {
  ClinicalPlan.fromApi(Map<String, dynamic> value, String owner, String role)
    : id = resourceId(value['id']),
      patient = resourceId(value['patient_id']),
      doctor = resourceId(value['doctor_id']),
      grant = resourceId(value['access_id']),
      kind = text(value['kind']),
      state = text(value['state']),
      revision = count(value['revision']),
      purpose = text(value['purpose']),
      due = timestamp(value['due_at_utc']),
      created = timestamp(value['created_at']),
      schedule = Map.unmodifiable(object(value['schedule_provenance'])),
      source = Map.unmodifiable(object(value['source_snapshot'])),
      baseline = value['baseline_capture_id'] == null
          ? null
          : resourceId(value['baseline_capture_id']),
      followup = value['followup_capture_id'] == null
          ? null
          : resourceId(value['followup_capture_id']),
      acknowledged = value['acknowledged_at'] == null
          ? null
          : timestamp(value['acknowledged_at']),
      wire = Map.unmodifiable(value) {
    if (value['schema_version'] != 'clinical-plan-1' ||
        (role == 'patient' ? patient : doctor) != owner ||
        patient == doctor ||
        !['follow_up', 'comparison'].contains(kind) ||
        ![
          'proposed',
          'scheduled',
          'captured',
          'reviewed',
          'cancelled',
        ].contains(state) ||
        revision < 1 ||
        purpose.length < 10 ||
        purpose.length > 1000 ||
        value['provenance'] != 'clinician_authored' ||
        value['patient_visible'] != true ||
        value['clinical_clearance'] != false ||
        schedule['policy'] != 'fixed_utc_explicit_reschedule_v1' ||
        schedule['timezone'] is! String ||
        (schedule['timezone'] as String).isEmpty ||
        schedule['local_time'] is! String ||
        ![0, 1].contains(schedule['fold']) ||
        timestamp(schedule['due_at_utc']) != due ||
        (kind == 'comparison' && (baseline == null || source.isEmpty)) ||
        (['scheduled', 'captured'].contains(state) && acknowledged == null)) {
      throw const FormatException('Unverified clinician plan');
    }
    if (source.isNotEmpty) {
      if (![
        'routine',
        'experiment',
        'observation',
      ].contains(source['source_type'])) {
        throw const FormatException('Unsupported source');
      }
      resourceId(source['source_id']);
    }
  }
  final String id, patient, doctor, grant, kind, state, purpose;
  final int revision;
  final DateTime due, created;
  final DateTime? acknowledged;
  final String? baseline, followup;
  final Map<String, dynamic> schedule, source, wire;
  String get localWallTime => schedule['local_time'] as String;
  String get timezone => schedule['timezone'] as String;
  bool get canReschedule => ['proposed', 'scheduled'].contains(state);
  bool get canCancel => !['cancelled', 'reviewed'].contains(state);
}

class PlanEvent {
  PlanEvent.fromApi(
    Map<String, dynamic> data,
    ClinicalPlan plan,
    String owner,
    String role,
  ) : revision = count(data['revision']),
      operation = text(data['operation']),
      actor = resourceId(data['actor_id']),
      recorded = timestamp(data['recorded_at']),
      snapshot = ClinicalPlan.fromApi(
        object(object(data['snapshot'])['plan']),
        owner,
        role,
      ),
      details = Map.unmodifiable(object(object(data['snapshot'])['details'])) {
    if (revision != snapshot.revision ||
        snapshot.id != plan.id ||
        snapshot.patient != plan.patient ||
        snapshot.doctor != plan.doctor ||
        snapshot.grant != plan.grant ||
        ![plan.patient, plan.doctor].contains(actor)) {
      throw const FormatException('Unverified plan history');
    }
  }
  final int revision;
  final String operation, actor;
  final DateTime recorded;
  final ClinicalPlan snapshot;
  final Map<String, dynamic> details;
}

String? validateWallSchedule(String local, String zone, int? fold) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$').hasMatch(local) ||
      DateTime.tryParse(local) == null) {
    return 'Enter a local date and time as YYYY-MM-DD HH:mm.';
  }
  final parsed = DateTime.parse(local);
  if (!parsed.toIso8601String().startsWith(
    local.length == 16 ? local : local.substring(0, 19),
  )) {
    return 'Choose a valid calendar date and time.';
  }
  if (zone.trim().isEmpty || zone.length > 100 || zone.contains(' ')) {
    return 'Choose an IANA timezone, such as Africa/Cairo.';
  }
  if (fold != null && ![0, 1].contains(fold)) {
    return 'Choose the first or second clock occurrence.';
  }
  return null;
}
