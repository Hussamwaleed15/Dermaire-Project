import '../clinical/clinical_models.dart';
import '../capture/guided_capture_models.dart';

String psmId(Object? value) {
  final id = text(value);
  if (!RegExp(r'^[A-Za-z0-9_-]{1,255}$').hasMatch(id)) {
    throw const FormatException('Invalid evidence identity');
  }
  return id;
}

List<dynamic> psmList(Object? value, {int limit = 500}) {
  if (value is! List || value.length > limit) {
    throw const FormatException('Unsupported evidence list');
  }
  return value;
}

List<String> psmTexts(Object? value) =>
    List.unmodifiable(psmList(value).map(text));
String psmChoice(Object? value, List<String> choices) {
  final v = text(value);
  if (!choices.contains(v)) {
    throw const FormatException('Unsupported model value');
  }
  return v;
}

String psmStrength(Object? value) =>
    psmChoice(value, ['none', 'limited', 'moderate']);
DateTime? psmTime(Object? value) => value == null ? null : timestamp(value);
num? psmNumber(Object? value) {
  if (value == null) return null;
  if (value is! num || !value.isFinite) {
    throw const FormatException('Invalid source value');
  }
  return value;
}

class PsmFreshness {
  PsmFreshness.fromApi(Map<String, dynamic> data)
    : state = psmChoice(data['state'], ['missing', 'fresh', 'stale']),
      latestAt = psmTime(data['latest_at']),
      ageDays = optionalCount(data['age_days']);
  final String state;
  final DateTime? latestAt;
  final int? ageDays;
}

class PsmEvidence {
  PsmEvidence.fromApi(Map<String, dynamic> data)
    : id = psmId(data['id']),
      source = psmChoice(data['source'], [
        'checkin',
        'daily_context',
        'profile',
        'product',
        'adherence',
      ]),
      kind = psmChoice(data['kind'], [
        'user_reported',
        'image_proxy',
        'server_recorded',
      ]),
      category = text(data['category']),
      recordedAt = timestamp(data['recorded_at']),
      fields = psmTexts(data['fields']) {
    if (category !=
        (kind == 'user_reported' ? 'patient_reported' : 'system_observed')) {
      throw const FormatException('Unverified evidence category');
    }
  }
  final String id, source, kind, category;
  final DateTime recordedAt;
  final List<String> fields;
}

class PsmFinding {
  PsmFinding.fromApi(Map<String, dynamic> data)
    : code = text(data['code']),
      subject = text(data['subject']),
      direction = psmChoice(data['direction'], [
        'increased',
        'decreased',
        'stable',
        'better',
        'worse',
        'same',
        'associated',
      ]),
      statement = text(data['statement']),
      strength = psmStrength(data['strength']),
      rule = text(data['rule']),
      evidence = List.unmodifiable(
        psmList(data['evidence']).map((v) => PsmEvidence.fromApi(object(v))),
      ),
      evidenceCount = optionalCount(data['evidence_count']),
      latestEvidenceAt = psmTime(data['latest_evidence_at']),
      confidence = data['confidence'] == null
          ? null
          : psmStrength(data['confidence']),
      caveats = psmTexts(data['caveats'] ?? []),
      referenceValue = psmNumber(data['reference_value']),
      recentValue = psmNumber(data['recent_value']),
      threshold = psmNumber(data['threshold']) {
    if (data['category'] != 'deterministic_derived' ||
        evidence.isEmpty ||
        (evidenceCount != null &&
            evidenceCount !=
                evidence.map((v) => '${v.source}:${v.id}').toSet().length) ||
        latestEvidenceAt != null &&
            latestEvidenceAt !=
                evidence
                    .map((v) => v.recordedAt)
                    .reduce((a, b) => a.isAfter(b) ? a : b)) {
      throw const FormatException('Unverified finding provenance');
    }
  }
  final String code, subject, direction, statement, strength, rule;
  final List<PsmEvidence> evidence;
  final int? evidenceCount;
  final DateTime? latestEvidenceAt;
  final String? confidence;
  final List<String> caveats;
  // Returned legacy/reference numbers have no unit in Finding. Preserve typed
  // values but do not display them as calibrated or fractional image metrics.
  final num? referenceValue, recentValue, threshold;
}

class PsmCoverage {
  PsmCoverage.fromApi(Map<String, dynamic> d)
    : recordDays = count(d['confirmed_days']),
      reportDays = count(d['report_days']),
      trackingDays = count(d['measurement_days']),
      excluded = count(d['excluded_checkins']),
      proxyDays = optionalCount(d['proxy_measurement_days']),
      latestProxy = psmTime(d['latest_proxy_measurement_at']),
      latestEvidence = psmTime(d['latest_evidence_at']),
      ageDays = optionalCount(d['age_days']),
      recency = psmChoice(d['recency'], ['missing', 'fresh', 'stale']),
      baselineReady = flag(d['baseline_ready']),
      reasons = psmTexts(d['reasons']);
  final int recordDays, reportDays, trackingDays, excluded;
  final int? proxyDays, ageDays;
  final DateTime? latestProxy, latestEvidence;
  final String recency;
  final bool baselineReady;
  final List<String> reasons;
}

class PsmProfile {
  PsmProfile(
    Map<String, dynamic> root,
    Map<String, dynamic>? source,
    String owner,
  ) : available = flag(root['available']),
      goals = psmTexts(root['primary_goals'] ?? []),
      evidence = List.unmodifiable(
        psmList(
          root['evidence'] ?? [],
        ).map((v) => PsmEvidence.fromApi(object(v))),
      ),
      skinType = optionalText(source?['skin_type']),
      concerns = psmTexts(source?['skin_concerns'] ?? []),
      freshness = source?['freshness'] == null
          ? null
          : PsmFreshness.fromApi(object(source!['freshness'])) {
    if (source != null && source['category'] != 'patient_reported' ||
        evidence.any((e) => e.source != 'profile' || e.id != owner)) {
      throw const FormatException('Unverified profile source');
    }
    if (goals.isNotEmpty && evidence.isEmpty) {
      throw const FormatException('Missing goal evidence');
    }
  }
  final bool available;
  final List<String> goals, concerns;
  final List<PsmEvidence> evidence;
  final String? skinType;
  final PsmFreshness? freshness;
}

class PsmReport {
  PsmReport.fromApi(Map<String, dynamic> d)
    : id = psmId(d['id']),
      recordedAt = timestamp(d['recorded_at']),
      freshness = PsmFreshness.fromApi(object(d['freshness'])),
      change = psmChoice(object(d['report'])['overall_change'], [
        'better',
        'same',
        'worse',
      ]),
      symptoms = List.unmodifiable(
        psmList(object(d['report'])['symptoms']).map(
          (v) => psmChoice(v, [
            'redness',
            'dryness',
            'itching',
            'burning',
            'breakouts',
            'sensitivity',
            'texture',
          ]),
        ),
      ),
      routine = object(d['report'])['routine_status'] == null
          ? null
          : psmChoice(object(d['report'])['routine_status'], [
              'followed',
              'partial',
              'skipped',
              'not_applicable',
            ]);
  final String id, change;
  final String? routine;
  final DateTime recordedAt;
  final PsmFreshness freshness;
  final List<String> symptoms;
}

class PsmImageEstimates {
  PsmImageEstimates.fromApi(Map<String, dynamic> d, {required this.historical})
    : id = psmId(d['id']),
      captureId = psmId(d['capture_id']),
      algorithm = text(d['algorithm_version']),
      computedAt = timestamp(d['measured_at']),
      receivedAt = historical ? timestamp(d['received_at']) : null,
      status = historical
          ? psmChoice(
              object(object(d['metrics'])['red_chromaticity_proxy'])['status'],
              ['measured'],
            )
          : psmChoice(d['status'], [
              'measured',
              'unavailable',
              'failed',
              'insufficient_quality',
            ]),
      source = historical ? null : text(d['provenance']),
      freshness = historical
          ? PsmFreshness.fromApi(object(d['freshness']))
          : null {
    final quality = CaptureQuality.fromApi(
      object(d[historical ? 'quality_reference' : 'capture_quality']),
    );
    if (algorithm != 'measurement-1.0' ||
        quality.version != 'capture-quality-1.0' ||
        quality.decision != 'accepted' ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(quality.requestFingerprint) ||
        !historical &&
            source !=
                (status == 'unavailable'
                    ? 'server_recorded_unavailability'
                    : 'server_computed_from_upload_bytes')) {
      throw const FormatException('Unsupported image estimate source');
    }
    final raw = object(d['metrics']);
    if (raw.length != 2 ||
        !raw.containsKey('red_chromaticity_proxy') ||
        !raw.containsKey('texture_contrast_proxy')) {
      throw const FormatException('Unsupported image metrics');
    }
    metrics = Map.unmodifiable(
      raw.map(
        (key, v) => MapEntry(
          key,
          CaptureProxy.fromApi(
            object(v),
            captureId: captureId,
            algorithm: algorithm,
            parentStatus: status,
          ),
        ),
      ),
    );
    if (metrics.entries.any(
      (e) => e.key != e.value.key || e.value.measuredAt != computedAt,
    )) {
      throw const FormatException('Inconsistent image measurement');
    }
  }
  final String id, captureId, algorithm, status;
  final String? source;
  final bool historical;
  final DateTime computedAt;
  final DateTime? receivedAt;
  final PsmFreshness? freshness;
  late final Map<String, CaptureProxy> metrics;
}

class PsmMeasurements {
  PsmMeasurements(Map<String, dynamic> data)
    : trend = psmChoice(data['trend_status'], [
        'unknown',
        'not_comparable',
        'comparable',
        'stale',
      ]),
      freshness = PsmFreshness.fromApi(object(data['freshness'])) {
    if (data['category'] != 'deterministic_derived') {
      throw const FormatException('Unknown measurement category');
    }
    try {
      latest = data['latest'] == null
          ? null
          : PsmImageEstimates.fromApi(
              object(data['latest']),
              historical: false,
            );
      latestUnsupported = false;
    } catch (_) {
      latest = null;
      latestUnsupported = true;
    }
    try {
      historical = data['latest_measured'] == null
          ? null
          : PsmImageEstimates.fromApi(
              object(data['latest_measured']),
              historical: true,
            );
      historicalUnsupported = false;
    } catch (_) {
      historical = null;
      historicalUnsupported = true;
    }
  }
  final String trend;
  final PsmFreshness freshness;
  late final PsmImageEstimates? latest, historical;
  late final bool latestUnsupported, historicalUnsupported;
}

class PsmExperiment {
  PsmExperiment.fromApi(Map<String, dynamic> d)
    : id = psmId(d['id']),
      status = psmChoice(d['status'], [
        'draft',
        'active',
        'paused',
        'baseline',
        'completed',
        'stopped',
        'cancelled',
      ]),
      start = timestamp(d['start_date']),
      targetDays = count(d['target_days']),
      changeType = optionalText(d['change_type']),
      evaluation = d['evaluation'] == null
          ? null
          : PsmExperimentEvaluation(object(d['evaluation'])) {
    if (d['category'] != 'patient_reported' || targetDays < 1) {
      throw const FormatException('Unsupported experiment source');
    }
  }
  final String id, status;
  final DateTime start;
  final int targetDays;
  final String? changeType;
  final PsmExperimentEvaluation? evaluation;
}

class PsmExperimentEvaluation {
  PsmExperimentEvaluation(Map<String, dynamic> d)
    : id = psmId(d['id']),
      label = psmChoice(d['label'], [
        'likely_associated_improvement',
        'likely_associated_worsening',
        'no_meaningful_change',
        'insufficient_evidence',
        'confounded_or_low_adherence',
      ]),
      strength = psmChoice(d['strength'], [
        'insufficient',
        'limited',
        'moderate',
      ]),
      evidenceCount = optionalCount(d['evidence_count']),
      statement = text(d['statement']),
      freshness = PsmFreshness.fromApi(object(d['freshness'])),
      caveats = psmTexts(d['caveats'] ?? []) {
    if (d['category'] != 'deterministic_derived') {
      throw const FormatException('Unsupported evaluation provenance');
    }
  }
  final String id, label, strength, statement;
  final int? evidenceCount;
  final PsmFreshness freshness;
  final List<String> caveats;
}

class PsmClinicianSnapshot {
  PsmClinicianSnapshot(Map<String, dynamic> d)
    : id = psmId(d['id']),
      state = text(d['state']),
      recommendation = optionalText(d['recommendation']),
      rationale = optionalText(d['rationale']),
      recordedAt = timestamp(d['recorded_at']),
      freshness = PsmFreshness.fromApi(object(d['freshness'])) {
    if (d['category'] != 'clinician_authored') {
      throw const FormatException('Unsupported clinician source');
    }
  }
  final String id, state;
  final String? recommendation, rationale;
  final DateTime recordedAt;
  final PsmFreshness freshness;
}

class PersonalSkinModel {
  PersonalSkinModel.fromApi(Map<String, dynamic> data, {required this.owner})
    : schema = data['schema_version'] as int,
      contract = text(data['contract_version']),
      derivation = text(data['derivation_version']),
      generatedAt = timestamp(data['generated_at']),
      status = psmChoice(data['status'], [
        'no_data',
        'insufficient_data',
        'no_meaningful_change',
        'meaningful_change',
        'stale',
      ]),
      statement = text(data['statement']),
      strength = psmStrength(data['strength']),
      coverage = PsmCoverage.fromApi(object(data['sufficiency'])),
      limitations = psmTexts(data['limitations']),
      unknowns = psmTexts(data['unknowns'] ?? []) {
    if (schema != 2 ||
        contract != 'personal-skin-model-2.0' ||
        derivation != 'psm-v2.0') {
      throw const FormatException('Unsupported PSM version');
    }
    if (data['assistant_layer'] != null) {
      final layer = object(data['assistant_layer']);
      if (layer['category'] != 'ai_inferred' ||
          layer['included'] != false ||
          layer['authoritative'] != false) {
        throw const FormatException(
          'Unsupported assistant layer in deterministic PSM',
        );
      }
    }
    final issues = <String>[];
    T? optional<T>(
      String label,
      Object? raw,
      T Function(Map<String, dynamic>) parse,
    ) {
      if (raw == null || raw is Map && raw.isEmpty) return null;
      try {
        return parse(object(raw));
      } catch (_) {
        issues.add('$label is unsupported or incomplete.');
        return null;
      }
    }

    List<T> items<T>(
      String label,
      Object? raw,
      T Function(Map<String, dynamic>) parse, {
      bool required = false,
    }) {
      if (raw == null && !required) return const [];
      try {
        return List.unmodifiable(psmList(raw).map((v) => parse(object(v))));
      } catch (_) {
        issues.add('$label is unsupported or incomplete.');
        return const [];
      }
    }

    final sources = data['sources'] == null
        ? <String, dynamic>{}
        : object(data['sources']);
    changing = items(
      'Changing findings',
      data['changing'],
      PsmFinding.fromApi,
      required: true,
    );
    stable = items(
      'Stable findings',
      data['stable'],
      PsmFinding.fromApi,
      required: true,
    );
    associations = items(
      'Associations',
      data['associations'],
      PsmFinding.fromApi,
      required: true,
    );
    profile = optional(
      'Profile evidence',
      data['profile'],
      (d) => PsmProfile(
        d,
        sources['profile'] == null ? null : object(sources['profile']),
        owner,
      ),
    );
    final history = optional(
      'Reported observation source',
      sources['history'],
      (d) {
        if (d['category'] != 'patient_reported') {
          throw const FormatException('Unknown observation category');
        }
        return d;
      },
    );
    reports = items(
      'Reported observations',
      history?['recent_reports'],
      PsmReport.fromApi,
    );
    measurements = optional(
      'Image estimates',
      sources['measurements'],
      PsmMeasurements.new,
    );
    experiments = items(
      'Experiment evidence',
      sources['experiments'],
      PsmExperiment.fromApi,
    );
    safety = optional(
      'PSM safety snapshot',
      data['safety'],
      SafetyAssessment.fromApi,
    );
    final doctor = optional('PSM clinician source', sources['doctor'], (d) {
      if (d['category'] != 'clinician_authored') {
        throw const FormatException('Invalid doctor source');
      }
      return d;
    });
    clinician = optional(
      'PSM clinician decision',
      doctor?['current_decision'],
      PsmClinicianSnapshot.new,
    );
    // Never fall back to older visible history when current decision is null.
    partialIssues = List.unmodifiable(issues);
  }
  final String owner, contract, derivation, status, statement, strength;
  final int schema;
  final DateTime generatedAt;
  final PsmCoverage coverage;
  final List<String> limitations, unknowns;
  late final List<PsmFinding> changing, stable, associations;
  late final PsmProfile? profile;
  late final List<PsmReport> reports;
  late final PsmMeasurements? measurements;
  late final List<PsmExperiment> experiments;
  late final SafetyAssessment? safety;
  late final PsmClinicianSnapshot? clinician;
  late final List<String> partialIssues;
}
