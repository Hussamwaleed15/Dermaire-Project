import '../clinical/clinical_models.dart' show object, text, timestamp;

const observationChanges = ['better', 'same', 'worse'];
const observationSymptoms = [
  'redness',
  'dryness',
  'itching',
  'burning',
  'breakouts',
  'sensitivity',
  'texture',
];
const observationRoutines = [
  'followed',
  'partial',
  'skipped',
  'not_applicable',
];
const observationLevels = ['none', 'mild', 'moderate', 'severe'];
const safetyQuestions = <String, String>{
  'breathing_difficulty': 'Breathing difficulty',
  'facial_or_mouth_swelling': 'Face or mouth swelling',
  'eye_or_mucosal_involvement': 'Eye or mucosal involvement',
  'fever_or_systemic_illness': 'Fever or systemic illness',
  'rapid_spread': 'Rapid spread',
  'extensive_blistering_or_peeling': 'Extensive blistering or peeling',
  'pus_or_hot_swollen_skin': 'Pus or hot, swollen skin',
  'new_medication_or_product_reaction': 'New medication or product reaction',
};

class ObservationDraft {
  ObservationDraft({
    this.change,
    this.moment,
    Iterable<String> symptoms = const [],
    this.routine,
    this.notes = '',
    this.severity,
    this.pain,
    Map<String, bool?> flags = const {},
  }) : symptoms = Set.unmodifiable(symptoms),
       flags = Map.unmodifiable(flags);
  final String? change, moment, routine, severity, pain;
  final String notes;
  final Set<String> symptoms;
  final Map<String, bool?> flags;
  String? get validation {
    if (!observationChanges.contains(change)) {
      return 'Choose your overall skin change.';
    }
    if (!['Morning', 'Evening'].contains(moment)) {
      return 'Choose Morning or Evening for this observation.';
    }
    if (symptoms.any((s) => !observationSymptoms.contains(s)) ||
        (routine != null && !observationRoutines.contains(routine)) ||
        (severity != null && !observationLevels.contains(severity)) ||
        (pain != null && !observationLevels.contains(pain)) ||
        flags.keys.any((k) => !safetyQuestions.containsKey(k))) {
      return 'An observation value is unsupported. Review your answers.';
    }
    if (notes.runes.length > 1500) return 'Keep notes within 1500 characters.';
    return null;
  }

  Map<String, dynamic> get report {
    final safety = <String, dynamic>{
      if (severity != null) 'severity': severity,
      if (pain != null) 'pain': pain,
      for (final key in safetyQuestions.keys)
        if (flags[key] != null) key: flags[key],
    };
    return {
      'overall_change': change,
      'symptoms': observationSymptoms.where(symptoms.contains).toList(),
      if (routine != null) 'routine_status': routine,
      if (safety.isNotEmpty) 'safety': safety,
    };
  }

  String? get submittedNotes => notes.trim().isEmpty ? null : notes.trim();
}

class RecordedReport {
  RecordedReport.fromApi(Map<String, dynamic> data)
    : change = text(data['overall_change']),
      symptoms = List.unmodifiable((data['symptoms'] as List).map(text)),
      routine = data['routine_status'] == null
          ? null
          : text(data['routine_status']),
      safety = data['safety'] == null
          ? const {}
          : Map.unmodifiable(object(data['safety'])) {
    for (final key in safetyQuestions.keys) {
      if (safety[key] != null && safety[key] is! bool) {
        throw const FormatException('Invalid recorded safety answer');
      }
    }
    for (final key in ['severity', 'pain']) {
      if (safety[key] != null && safety[key] is! String) {
        throw const FormatException('Invalid recorded symptom level');
      }
    }
  }
  final String change;
  final List<String> symptoms;
  final String? routine;
  final Map<String, dynamic> safety;
  bool get unsupported =>
      !observationChanges.contains(change) ||
      symptoms.any((s) => !observationSymptoms.contains(s)) ||
      (routine != null && !observationRoutines.contains(routine)) ||
      safety.keys.any(
        (k) => !['severity', 'pain', ...safetyQuestions.keys].contains(k),
      ) ||
      [
        'severity',
        'pain',
      ].any((k) => safety[k] != null && !observationLevels.contains(safety[k]));
  bool matches(ObservationDraft draft) =>
      !unsupported &&
      change == draft.change &&
      symptoms.toSet().length == draft.symptoms.length &&
      symptoms.toSet().containsAll(draft.symptoms) &&
      routine == draft.routine &&
      safety['severity'] == draft.severity &&
      safety['pain'] == draft.pain &&
      safetyQuestions.keys.every((k) => safety[k] == draft.flags[k]);
}

enum ObservationKind { reportOnly, manual, imageEstimate, unsupported }

class ObservationRecord {
  ObservationRecord.fromApi(Map<String, dynamic> data, {required String owner})
    : id = text(data['id']),
      ownerId = text(data['user_id']),
      createdAt = timestamp(data['created_at'], naiveUtc: true),
      moment = text(data['time_of_day']),
      notes = data['notes'] as String?,
      source = data['ai_vision_analysis'] == null
          ? null
          : object(data['ai_vision_analysis'])['measurement_source'] as String?,
      report =
          data['observation'] == null ||
              object(data['observation'])['user_reported'] == null
          ? null
          : RecordedReport.fromApi(
              object(object(data['observation'])['user_reported']),
            ),
      contextDate = data['observation'] == null
          ? null
          : text(object(data['observation'])['daily_context_date']),
      contextLinked =
          data['observation'] != null &&
          object(data['observation'])['daily_context_id'] != null,
      imageEndpoint = data['image_endpoint'] == null
          ? null
          : text(data['image_endpoint']),
      scores = Map.unmodifiable({
        for (final name in ['hydration', 'redness', 'texture'])
          if (data['${name}_score'] != null) name: data['${name}_score'] as num,
      }) {
    final analysis = data['ai_vision_analysis'] == null
        ? <String, dynamic>{}
        : object(data['ai_vision_analysis']);
    if (data['user_id'] != owner ||
        analysis['simulated'] == true ||
        [
          'SIMULATED',
          'SIMULATED_SUCCESS',
          'FALLBACK_SIMULATED',
        ].contains(analysis['azure_vision_status'])) {
      throw const FormatException('Unverified observation owner/source');
    }
    if (data['observation'] != null) {
      final observation = object(data['observation']);
      final provenance = object(observation['provenance']);
      if (observation['schema_version'] != 1 ||
          (report != null && provenance['report'] != 'user_reported')) {
        throw const FormatException('Unverified observation provenance');
      }
      final date = contextDate!;
      final parsed = DateTime.tryParse(date);
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
          parsed == null ||
          parsed.toIso8601String().split('T').first != date) {
        throw const FormatException('Invalid context date');
      }
    }
    if (source == 'none' && (report == null || scores.isNotEmpty)) {
      throw const FormatException(
        'Report-only record cannot confirm measurements',
      );
    }
    if (['manual', 'image_proxy'].contains(source) &&
        (scores.length != 3 ||
            scores.values.any((s) => !s.isFinite || s < 0 || s > 100))) {
      throw const FormatException('Invalid recorded metrics');
    }
    if (scores.values.any((s) => !s.isFinite || s < 0 || s > 100)) {
      throw const FormatException('Invalid recorded metrics');
    }
    if (imageEndpoint != null &&
        imageEndpoint != '/api/v1/checkins/$id/image') {
      throw const FormatException('Invalid linked image reference');
    }
  }
  final String id, moment, ownerId;
  final String? source;
  final DateTime createdAt;
  final RecordedReport? report;
  final String? notes, contextDate, imageEndpoint;
  final bool contextLinked;
  final Map<String, num> scores;
  ObservationKind get kind => switch (source) {
    'none' => ObservationKind.reportOnly,
    'manual' => ObservationKind.manual,
    'image_proxy' => ObservationKind.imageEstimate,
    _ => ObservationKind.unsupported,
  };
  bool matches(ObservationDraft draft) =>
      kind == ObservationKind.reportOnly &&
      moment == draft.moment &&
      notes == draft.submittedNotes &&
      report?.matches(draft) == true;
}

enum ObservationFailure { rejected, uncertain }

class ObservationWriteException implements Exception {
  const ObservationWriteException(this.failure, {this.candidateId});
  final ObservationFailure failure;
  final String? candidateId;
}
