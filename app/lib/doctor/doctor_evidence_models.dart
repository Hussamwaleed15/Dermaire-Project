import '../clinical/clinical_models.dart';
import 'doctor_models.dart';

class DoctorDecision {
  DoctorDecision.fromApi(Map<String, dynamic> value, String patient)
    : id = doctorId(value['id']),
      doctor = doctorId(value['doctor_id']),
      accessId = doctorId(value['access_id']),
      sequence = count(value['sequence']),
      state = text(value['state']),
      recommendation = optionalText(value['recommendation']),
      rationale = optionalText(value['rationale']),
      visible = flag(value['patient_visible']),
      createdAt = timestamp(value['created_at'], naiveUtc: true),
      safety = SafetyAssessment.fromApi(object(value['safety_at_review'])),
      diverges = flag(value['diverges_from_current_safety']),
      lower = flag(value['lower_than_current_safety']),
      urgentPreserved = flag(value['urgent_safety_preserved']),
      wire = Map.unmodifiable(value) {
    if (value['patient_id'] != patient ||
        value['provenance'] != 'clinician_authored' ||
        sequence < 1 ||
        ![
          'pending',
          'in_review',
          'reviewed',
          'follow_up_needed',
        ].contains(state) ||
        (recommendation != null &&
            (![
                  'track',
                  'low_risk_self_care',
                  'doctor_review',
                  'urgent',
                ].contains(recommendation) ||
                rationale == null ||
                rationale!.length < 10))) {
      throw const FormatException('Unverified clinical review');
    }
  }
  final String id, doctor, accessId, state;
  final int sequence;
  final String? recommendation, rationale;
  final bool visible, diverges, lower, urgentPreserved;
  final DateTime createdAt;
  final SafetyAssessment safety;
  final Map<String, dynamic> wire;
}

class DoctorReviewRead {
  DoctorReviewRead.fromApi(Map<String, dynamic> value, String patient)
    : state = text(value['state']),
      sequence = count(value['latest_sequence']),
      safety = SafetyAssessment.fromApi(object(value['safety'])),
      decision = value['current_decision'] == null
          ? null
          : DoctorDecision.fromApi(object(value['current_decision']), patient),
      history = (value['history'] as List)
          .map((v) => DoctorDecision.fromApi(object(v), patient))
          .toList() {
    if (value['schema_version'] != 'doctor-loop-2.0' ||
        value['patient_id'] != patient ||
        ![
          'not_requested',
          'pending',
          'in_review',
          'reviewed',
          'follow_up_needed',
        ].contains(state) ||
        (sequence == 0
            ? decision != null
            : decision == null ||
                  decision!.sequence != sequence ||
                  decision!.state != state) ||
        history.map((v) => v.sequence).toSet().length != history.length ||
        history.any((v) => v.sequence > sequence) ||
        (decision != null &&
            !history.any(
              (v) => v.id == decision!.id && v.sequence == sequence,
            ))) {
      throw const FormatException('Unverified current review');
    }
    history.sort((a, b) => b.sequence.compareTo(a.sequence));
  }
  final String state;
  final int sequence;
  final SafetyAssessment safety;
  final DoctorDecision? decision;
  final List<DoctorDecision> history;
}

class DoctorTimelineItem {
  DoctorTimelineItem.fromApi(Map<String, dynamic> value, String patient)
    : id = text(value['id']),
      source = text(value['source']),
      sourceId = text(value['source_id']),
      field = text(value['field']),
      category = text(value['category']),
      recordedAt = value['recorded_at'] == null
          ? null
          : timestamp(value['recorded_at']),
      provenance = Map.unmodifiable(object(value['provenance'])),
      data = Map.unmodifiable(object(value['data'])) {
    if (!(id == '$source:$sourceId:$field' ||
            (source == 'product_intelligence' &&
                id.startsWith('$source:$sourceId:$field:') &&
                (field == 'ingredient' ||
                    provenance['ingredient_ref'] != null))) ||
        !categories.contains(category) ||
        (source == 'profile' && sourceId != patient) ||
        (['clinical_note', 'doctor_review'].contains(source) &&
            category != 'clinician_authored')) {
      throw const FormatException('Unverified timeline provenance');
    }
    if (source == 'capture') doctorId(sourceId);
    if (source == 'clinical_note') DoctorNote.fromApi(data, patient);
    if (source == 'doctor_review') DoctorDecision.fromApi(data, patient);
  }
  static const categories = {
    'patient_reported',
    'system_observed',
    'deterministic_derived',
    'clinician_authored',
    'ai_inferred',
  };
  final String id, source, sourceId, field, category;
  final DateTime? recordedAt;
  final Map<String, dynamic> provenance, data;
  bool get storedCapture =>
      source == 'capture' &&
      field == 'record' &&
      category == 'system_observed' &&
      data['state'] == 'accepted' &&
      data['storage'] == 'azure_blob';
  String get sourceLabel => switch (category) {
    'patient_reported' => 'Patient-reported',
    'system_observed' => 'System-observed (not a clinical measurement)',
    'deterministic_derived' => 'Deterministic derivation (not diagnosis)',
    'clinician_authored' => 'Clinician-authored',
    _ => 'Historical AI output; not authoritative',
  };
  static const fields = {
    'profile': ['skin_type', 'selected_goal', 'skin_concerns'],
    'daily_context': ['date', 'unusual_conditions', 'cycle_day'],
    'routine': [
      'product_id',
      'schedule',
      'frequency',
      'start_date',
      'end_date',
      'active',
      'instructions',
      'source',
    ],
    'adherence': ['routine_entry_id', 'date', 'slot', 'status', 'note'],
    'experiment': [
      'product_id',
      'engine_version',
      'status',
      'intervention',
      'goal',
      'notes',
      'activated_at',
      'stopped_at',
    ],
    'experiment_evaluation': ['experiment_id'],
    'capture': ['state', 'source', 'view', 'storage', 'server_version'],
    'checkin': ['date', 'notes'],
  };
  static const supportedSources = {
    'profile',
    'daily_context',
    'routine',
    'adherence',
    'experiment',
    'experiment_evaluation',
    'capture',
    'measurement',
    'product_intelligence',
    'checkin',
    'baseline',
    'personal_skin_model',
    'safety',
    'clinical_note',
    'doctor_review',
  };
  List<String> get lines {
    if (!supportedSources.contains(source)) {
      return ['Unsupported evidence source; no conclusion is shown.'];
    }
    if (category == 'ai_inferred') {
      return [
        'Historical AI analysis is quarantined. It is not a clinical assessment.',
      ];
    }
    if (source == 'clinical_note') {
      final note = DoctorNote.fromApi(data, data['patient_id'] as String);
      return [
        note.content,
        'Author account: ${note.doctor}',
        note.visible
            ? 'Patient-visible server record'
            : 'Private clinician record',
        if (note.followUp != null)
          'Follow-up guidance: ${note.followUp} (text only; no appointment or reminder)',
      ];
    }
    if (source == 'doctor_review') {
      return [
        'Review state: ${data['state']}',
        'Recommendation: ${data['recommendation'] ?? 'Not recorded'}',
        'Rationale: ${data['rationale'] ?? 'Not recorded'}',
        'Sequence: ${data['sequence']}',
      ];
    }
    if (source == 'measurement') {
      if (provenance['clinical_measurement'] != false ||
          category != 'system_observed') {
        return ['Unsupported measurement provenance; no estimate is shown.'];
      }
      final values = data['status'] == 'measured' ? data['values'] : null;
      final result = <String>[
        'Nonclinical image appearance estimates. These are not disease severity or diagnostic measurements.',
      ];
      if (values is! Map || values.isEmpty) {
        return [...result, 'No verified estimate values available.'];
      }
      for (final key in ['red_chromaticity_proxy', 'texture_contrast_proxy']) {
        final v = values[key];
        if (v is Map &&
            v['status'] == 'measured' &&
            v['unit'] == 'fraction_0_to_1' &&
            v['source_capture_id'] == data['capture_id'] &&
            v['method_version'] == provenance['algorithm'] &&
            v['value'] is num &&
            (v['value'] as num).isFinite &&
            v['value'] >= 0 &&
            v['value'] <= 1) {
          result.add(
            '$key: ${v['value']} fraction (0–1); method ${v['method_version']}; capture ${v['source_capture_id']}',
          );
        } else {
          result.add('$key: unavailable or unverified');
        }
      }
      return result;
    }
    if (source == 'checkin' &&
        field == 'tracking_scores' &&
        (provenance['clinical_measurement'] != false ||
            ![
              'manual',
              'image_proxy',
            ].contains(provenance['measurement_source']))) {
      return ['Unsupported tracking provenance; no score is shown.'];
    }
    if (source == 'checkin' && field == 'tracking_scores') {
      return [
        'Source: ${provenance['measurement_source'] ?? 'Unknown'}; tracking values are not clinical measurements.',
        for (final key in ['hydration', 'texture', 'redness'])
          '$key tracking score: ${format(data[key])} (0–100 tracking domain)',
      ];
    }
    final result = <String>[
      for (final key in fields[source] ?? <String>[])
        if (data.containsKey(key))
          '${key.replaceAll('_', ' ')}: ${format(data[key])}',
    ];
    if (source == 'checkin' && data['observation'] is Map) {
      final reported = data['observation'] as Map;
      for (final key in [
        'overall_change',
        'symptoms',
        'routine_status',
        'discomfort',
      ]) {
        if (reported.containsKey(key)) {
          result.add(
            'Reported ${key.replaceAll('_', ' ')}: ${format(reported[key])}',
          );
        }
      }
    }
    if (source == 'experiment_evaluation' && data['result'] is Map) {
      final r = data['result'] as Map;
      result.add(
        'Association: ${format(r['label'])}; not causality or treatment effectiveness.',
      );
      for (final key in [
        'evidence_summary',
        'limitations',
        'coverage',
        'observed_change',
      ]) {
        if (r.containsKey(key)) {
          result.add('${key.replaceAll('_', ' ')}: ${format(r[key])}');
        }
      }
      result.add(
        'Numeric changes have unspecified units unless explicitly provided; no percentages are inferred.',
      );
    }
    if (data.containsKey('value')) {
      result.add('Recorded projection: ${format(data['value'])}');
    }
    if (source == 'product_intelligence') {
      for (final key in [
        'state',
        'data_completeness',
        'unknowns',
        'items',
        'name',
        'concentration',
        'value',
      ]) {
        if (data.containsKey(key)) {
          result.add('${key.replaceAll('_', ' ')}: ${format(data[key])}');
        }
      }
    }
    if (provenance['mutable_current_snapshot'] == true) {
      result.add('Mutable current snapshot; not an edit history.');
    }
    return result.isEmpty
        ? ['No supported evidence fields can be displayed for this record.']
        : result;
  }

  static String format(Object? value, {int depth = 0}) {
    if (value == null) return 'Not reported';
    if (value is num) return value.isFinite ? value.toString() : 'Unverified';
    if (value is String) {
      return value.length > 1000
          ? '${value.substring(0, 1000)}… (display truncated)'
          : value;
    }
    if (value is bool) return value ? 'Reported true' : 'Reported false';
    if (depth >= 3) return 'Additional structured detail is not displayed';
    if (value is List) {
      return value.take(10).map((v) => format(v, depth: depth + 1)).join('; ') +
          (value.length > 10 ? ' (display truncated)' : '');
    }
    if (value is Map) {
      return value.entries
          .where(
            (e) => ![
              'image_blob_name',
              'image_reference',
              'access_token',
              'image_url',
              'email',
              'patient_id',
              'doctor_id',
            ].contains(e.key),
          )
          .take(10)
          .map(
            (e) =>
                '${e.key.toString().replaceAll('_', ' ')}: ${format(e.value, depth: depth + 1)}',
          )
          .join('; ');
    }
    return 'Unsupported value';
  }
}

class DoctorTimelinePage {
  DoctorTimelinePage.fromApi(
    Map<String, dynamic> value,
    String patient,
    int offset,
  ) : builtAt = timestamp(value['built_at']),
      total = count(value['total']),
      nextOffset = value['next_offset'] as int?,
      items = (value['items'] as List)
          .map((v) => DoctorTimelineItem.fromApi(object(v), patient))
          .toList(),
      unknowns = (value['unknowns'] as List).map(text).toList(),
      limitations = (value['limitations'] as List).map(text).toList(),
      availability = Map.unmodifiable(
        object(value['derived_source_availability']),
      ),
      safety = SafetyAssessment.fromApi(object(value['safety'])) {
    if (value['schema_version'] != 'doctor-timeline-2.0' ||
        value['offset'] != offset ||
        value['limit'] != 100 ||
        items.length > 100 ||
        total < offset + items.length ||
        items.map((v) => v.id).toSet().length != items.length ||
        nextOffset != (offset + 100 < total ? offset + 100 : null)) {
      throw const FormatException('Unsupported timeline page');
    }
    for (final item in items) {
      if (item.recordedAt != null && item.recordedAt!.isAfter(builtAt)) {
        throw const FormatException('Future timeline record');
      }
    }
    for (final v in availability.values) {
      if (v is! Map ||
          !['available', 'partial', 'missing'].contains(v['state']) ||
          v['included'] is! int ||
          v['included'] < 0 ||
          v['truncated'] is! bool) {
        throw const FormatException('Unknown evidence availability');
      }
    }
  }
  final DateTime builtAt;
  final int total;
  final int? nextOffset;
  final List<DoctorTimelineItem> items;
  final List<String> unknowns, limitations;
  final Map<String, dynamic> availability;
  final SafetyAssessment safety;
}
