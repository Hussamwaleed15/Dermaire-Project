import 'dart:convert';
import '../clinical/clinical_models.dart';

List<dynamic> assistanceList(Object? v, int max) {
  if (v is! List || v.length > max) {
    throw const FormatException('Unsupported assistance list');
  }
  return v;
}

List<String> assistanceTexts(Object? v, int max) =>
    List.unmodifiable(assistanceList(v, max).map(text));
void boundedJson(Object? v, [int depth = 0]) {
  if (depth > 8) throw const FormatException('Unsupported fact depth');
  if (v == null || v is String || v is bool) return;
  if (v is num && v.isFinite) return;
  if (v is List && v.length <= 100) {
    for (final item in v) {
      boundedJson(item, depth + 1);
    }
    return;
  }
  if (v is Map && v.length <= 100 && v.keys.every((k) => k is String)) {
    for (final item in v.values) {
      boundedJson(item, depth + 1);
    }
    return;
  }
  throw const FormatException('Invalid fact JSON');
}

class AssistanceFact {
  AssistanceFact.fromApi(Map<String, dynamic> d)
    : id = text(d['id']),
      source = text(d['source']),
      sourceId = text(d['source_id']),
      field = text(d['field']),
      category = text(d['category']),
      freshness = text(d['freshness']),
      recordedAt = d['recorded_at'] == null
          ? null
          : timestamp(d['recorded_at']),
      confidence = optionalText(d['confidence']) {
    if (![
          'patient_reported',
          'system_observed',
          'deterministic_derived',
        ].contains(category) ||
        ![
          'fresh',
          'stale',
          'unknown',
          'historical_reference',
        ].contains(freshness)) {
      throw const FormatException('Unsupported fact provenance');
    }
    boundedJson(d['value']);
    boundedJson(d['provenance']);
    valueJson = jsonEncode(d['value']);
    provenanceJson = jsonEncode(object(d['provenance']));
    if (valueJson.length + provenanceJson.length > 6000) {
      throw const FormatException('Oversized fact');
    }
  }
  final String id, source, sourceId, field, category, freshness;
  final DateTime? recordedAt;
  final String? confidence;
  late final String valueJson, provenanceJson;
  bool get knownSource => [
    'profile',
    'checkin',
    'baseline',
    'daily_context',
    'routine',
    'adherence',
    'experiment',
    'measurement',
    'product_intelligence',
    'personal_skin_model',
    'safety',
  ].contains(source);
}

class AssistanceInference {
  AssistanceInference.fromApi(Map<String, dynamic> d)
    : statement = text(d['statement']),
      evidenceIds = assistanceTexts(d['evidence_ids'], 12) {
    if (d['category'] != 'ai_inferred') {
      throw const FormatException('Unsupported inference category');
    }
  }
  final String statement;
  final List<String> evidenceIds;
}

class AssistanceProvider {
  AssistanceProvider.fromApi(Map<String, dynamic> d)
    : provider = optionalText(d['provider']),
      model = optionalText(d['model']),
      reason = optionalText(d['reason']),
      configured = flag(d['configured']),
      invoked = flag(d['invoked']),
      availability = text(d['availability']),
      mode = text(d['mode']) {
    if (![
          'disabled',
          'unconfigured',
          'available',
          'failed',
          'not_invoked',
        ].contains(availability) ||
        ![
          'grounded_ai',
          'degraded',
          'safety_guard',
          'narrowed',
        ].contains(mode) ||
        mode == 'grounded_ai' &&
            (!configured ||
                !invoked ||
                availability != 'available' ||
                provider == null ||
                model == null)) {
      throw const FormatException('Unsupported provider claims');
    }
  }
  final String? provider, model, reason;
  final bool configured, invoked;
  final String availability, mode;
}

class AssistanceClinician {
  AssistanceClinician.fromApi(Map<String, dynamic> d)
    : id = text(d['id']),
      sequence = count(d['sequence']),
      recommendation = text(d['recommendation']) {
    if (d['provenance'] != 'clinician_authored' || sequence < 1) {
      throw const FormatException('Unsupported clinician provenance');
    }
  }
  final String id, recommendation;
  final int sequence;
}

class AssistanceResponse {
  AssistanceResponse.fromApi(Map<String, dynamic> d, {required this.owner})
    : schema = text(d['schema_version']),
      contextVersion = text(d['context_version']),
      task = text(d['task']),
      message = text(d['message']),
      escalation = text(d['escalation']),
      safety = SafetyAssessment.fromApi(object(d['authoritative_safety'])),
      clinician = d['authoritative_clinician'] == null
          ? null
          : AssistanceClinician.fromApi(object(d['authoritative_clinician'])),
      provider = AssistanceProvider.fromApi(object(d['metadata'])),
      facts = List.unmodifiable(
        assistanceList(
          d['grounded_facts_used'],
          12,
        ).map((v) => AssistanceFact.fromApi(object(v))),
      ),
      inferences = List.unmodifiable(
        assistanceList(
          d['inferred_points'],
          1,
        ).map((v) => AssistanceInference.fromApi(object(v))),
      ),
      uncertainties = assistanceTexts(d['uncertainties'], 500),
      nextSteps = assistanceTexts(d['next_steps'], 8) {
    if (schema != 'contextual-ai-1.0' ||
        contextVersion != 'context-1.0' ||
        ![
          'changes',
          'worsening',
          'tracking',
          'routine',
          'doctor_questions',
          'unsupported',
        ].contains(task) ||
        message.length > 50000 ||
        facts.map((f) => f.id).toSet().length != facts.length ||
        inferences.any(
          (i) =>
              i.evidenceIds.isEmpty ||
              i.evidenceIds.any((id) => !facts.any((f) => f.id == id)),
        )) {
      throw const FormatException('Unverified assistance evidence');
    }
    final moderation = d['moderation'];
    if (moderation != null) {
      final m = object(moderation);
      if (m['provider'] != 'azure_content_safety' ||
          !['not_invoked', 'available', 'degraded'].contains(m['state']) ||
          m['configured'] is! bool ||
          m['invoked'] is! bool ||
          m['flagged'] is! bool) {
        throw const FormatException('Unsupported moderation format');
      }
    }
  }
  final String owner, schema, contextVersion, task, message, escalation;
  final SafetyAssessment safety;
  final AssistanceClinician? clinician;
  final AssistanceProvider provider;
  final List<AssistanceFact> facts;
  final List<AssistanceInference> inferences;
  final List<String> uncertainties, nextSteps;
}
