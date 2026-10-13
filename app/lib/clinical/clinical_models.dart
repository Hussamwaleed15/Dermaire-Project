/// Read-only patient projections from safety-1.0 / doctor-loop-2.0.
/// Unknown enum values are preserved, never mapped to a reassuring state.
enum SafetyLevel {
  track('track', 'Monitoring guidance'),
  lowRisk('low_risk_self_care', 'Low-risk self-care guidance'),
  doctorReview('doctor_review', 'Clinician review recommended'),
  urgent('urgent', 'Urgent medical assessment recommended'),
  unknown('', 'Unsupported safety status');

  const SafetyLevel(this.code, this.label);
  final String code, label;
  static SafetyLevel parse(String value) =>
      values.firstWhere((s) => s.code == value, orElse: () => unknown);
}

enum ReviewState {
  notRequested('not_requested', 'Review not requested'),
  pending('pending', 'Review pending'),
  inReview('in_review', 'Review in progress'),
  reviewed('reviewed', 'Review recorded'),
  followUp('follow_up_needed', 'Follow-up needed'),
  unknown('', 'Unsupported review status');

  const ReviewState(this.code, this.label);
  final String code, label;
  static ReviewState parse(String value) =>
      values.firstWhere((s) => s.code == value, orElse: () => unknown);
}

Map<String, dynamic> object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid clinical object');
  }
  return Map<String, dynamic>.from(value);
}

String text(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Invalid clinical text');
  }
  return value;
}

String? optionalText(Object? value) => value == null ? null : text(value);
int? optionalCount(Object? value) {
  if (value == null) return null;
  if (value is! int || value < 0) {
    throw const FormatException('Invalid clinical count');
  }
  return value;
}

bool? optionalFlag(Object? value) {
  if (value == null) return null;
  if (value is! bool) throw const FormatException('Invalid clinical flag');
  return value;
}

int count(Object? value) =>
    optionalCount(value) ??
    (throw const FormatException('Missing clinical count'));
bool flag(Object? value) =>
    optionalFlag(value) ??
    (throw const FormatException('Missing clinical flag'));

DateTime timestamp(Object? value, {bool naiveUtc = false}) {
  final raw = text(value);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})?$',
  ).firstMatch(raw);
  if (match == null || (match[7] == null && !naiveUtc)) {
    throw const FormatException('Invalid clinical timestamp');
  }
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final check = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  final actual = [
    check.year,
    check.month,
    check.day,
    check.hour,
    check.minute,
    check.second,
  ];
  if (parts[0] < 1 ||
      !List.generate(6, (i) => parts[i] == actual[i]).every((same) => same)) {
    throw const FormatException('Invalid clinical timestamp');
  }
  final zone = match[7];
  if (zone != null &&
      zone != 'Z' &&
      (int.parse(zone.substring(1, 3)) > 23 ||
          int.parse(zone.substring(4, 6)) > 59)) {
    throw const FormatException('Invalid clinical timezone');
  }
  final parsed = DateTime.tryParse(zone == null ? '${raw}Z' : raw);
  if (parsed == null) throw const FormatException('Invalid clinical timestamp');
  return parsed.toUtc();
}

class SafetyReason {
  SafetyReason.fromApi(Map<String, dynamic> value)
    : code = text(value['code']),
      rawState = text(value['state']),
      summary = text(value['summary']) {
    if (value['evidence'] is! List ||
        (value['evidence'] as List).any(
          (item) => item is! Map<String, dynamic>,
        )) {
      throw const FormatException('Invalid evidence references');
    }
  }
  final String code, rawState, summary;
  SafetyLevel get level => SafetyLevel.parse(rawState);
}

class SafetyAssessment {
  SafetyAssessment.fromApi(Map<String, dynamic> value)
    : rawStatus = text(value['status']),
      engineVersion = text(value['engine_version']),
      evaluatedAt = timestamp(value['evaluated_at']),
      guidance = text(value['guidance']),
      reasons = List.unmodifiable(
        (value['reasons'] as List).map((r) => SafetyReason.fromApi(object(r))),
      ),
      limitations = List.unmodifiable((value['limitations'] as List).map(text)),
      currentReportCount = optionalCount(
        object(value['evidence_status'])['current_report_count'],
      ),
      riskScreenComplete = optionalFlag(
        object(value['evidence_status'])['risk_screen_complete'],
      ),
      staleOrAbsent = optionalFlag(
        object(value['evidence_status'])['stale_or_absent'],
      );
  final String rawStatus, engineVersion, guidance;
  final DateTime evaluatedAt;
  final List<SafetyReason> reasons;
  final List<String> limitations;
  final int? currentReportCount;
  final bool? riskScreenComplete, staleOrAbsent;
  SafetyLevel get level => SafetyLevel.parse(rawStatus);
  bool get supported =>
      engineVersion == 'safety-1.0' && level != SafetyLevel.unknown;
  bool get hasUnknownReasons =>
      reasons.any((r) => r.level == SafetyLevel.unknown);
}

class ClinicianDecision {
  ClinicianDecision.fromApi(Map<String, dynamic> value, {required String owner})
    : id = text(value['id']),
      sequence = count(value['sequence']),
      rawState = text(value['state']),
      recommendation = optionalText(value['recommendation']),
      rationale = optionalText(value['rationale']),
      createdAt = timestamp(value['created_at'], naiveUtc: true),
      diverges = flag(value['diverges_from_current_safety']),
      lowerThanCurrentSafety = optionalFlag(
        value['lower_than_current_safety'],
      )!,
      urgentSafetyPreserved = flag(value['urgent_safety_preserved']) {
    if (value['patient_id'] != owner ||
        value['patient_visible'] != true ||
        value['provenance'] != 'clinician_authored' ||
        sequence < 1 ||
        value['doctor_id'] is! String ||
        (value['doctor_id'] as String).isEmpty ||
        (recommendation != null && rationale == null)) {
      throw const FormatException(
        'Unverified patient-visible clinician decision',
      );
    }
  }
  final String id, rawState;
  final int sequence;
  final String? recommendation, rationale;
  final DateTime createdAt;
  final bool diverges, lowerThanCurrentSafety, urgentSafetyPreserved;
  SafetyLevel? get level =>
      recommendation == null ? null : SafetyLevel.parse(recommendation!);
}

class ClinicianReview {
  ClinicianReview.fromApi(Map<String, dynamic> value, {required String owner})
    : schemaVersion = text(value['schema_version']),
      patientId = text(value['patient_id']),
      rawState = text(value['state']),
      latestSequence = count(value['latest_sequence']),
      changedAt = value['changed_at'] == null
          ? null
          : timestamp(value['changed_at'], naiveUtc: true),
      safety = SafetyAssessment.fromApi(object(value['safety'])),
      decision = value['current_decision'] == null
          ? null
          : ClinicianDecision.fromApi(
              object(value['current_decision']),
              owner: owner,
            ) {
    if (patientId != owner ||
        !value.containsKey('current_decision') ||
        (decision != null &&
            (decision!.sequence != latestSequence ||
                decision!.rawState != rawState))) {
      throw const FormatException('Unverified current clinician projection');
    }
    // Note failures cannot suppress independent canonical Safety/current decision.
    try {
      if (schemaVersion != 'doctor-loop-2.0') {
        throw const FormatException('Unsupported notes');
      }
      notes = List.unmodifiable(
        (value['notes'] as List).map(
          (v) => PatientClinicianNote.fromApi(object(v), owner),
        ),
      );
    } catch (_) {
      notes = null;
    }
    // History/notes are not substituted for the current_decision, even when the
    // latest action is private or has no recommendation.
  }
  List<PatientClinicianNote>? notes;
  final String schemaVersion, patientId, rawState;
  final int latestSequence;
  final DateTime? changedAt;
  final SafetyAssessment safety;
  final ClinicianDecision? decision;
  ReviewState get state => ReviewState.parse(rawState);
  bool get supported =>
      schemaVersion == 'doctor-loop-2.0' && state != ReviewState.unknown;
}

/// Patient-visible immutable clinician note, independent of current decision.
class PatientClinicianNote {
  PatientClinicianNote.fromApi(Map<String, dynamic> value, String owner)
    : content = text(value['content']),
      author = text(value['doctor_id']),
      priority = text(value['priority']),
      followUp = optionalText(value['follow_up']),
      createdAt = timestamp(value['created_at'], naiveUtc: true) {
    text(value['id']);
    timestamp(value['updated_at'], naiveUtc: true);
    if (value['patient_id'] != owner ||
        value['patient_visible'] != true ||
        value['provenance'] != 'clinician_authored' ||
        !['routine', 'review', 'urgent'].contains(priority) ||
        content.length < 10 ||
        content.length > 1500 ||
        (followUp != null && followUp!.length > 100)) {
      throw const FormatException('Unverified visible clinical note');
    }
  }
  final String content, author, priority;
  final String? followUp;
  final DateTime createdAt;
}
