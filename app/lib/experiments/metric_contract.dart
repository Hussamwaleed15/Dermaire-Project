/// Actual optional backend MetricContract; this is not a clinical metric.
class ExperimentMetricContract {
  ExperimentMetricContract._(
    this.metric,
    this.source,
    this.direction,
    this.versions,
    this.provenance,
  );
  final String metric, source, direction, provenance;
  final List<String> versions;
  static ExperimentMetricContract? parse(Map result) {
    final m = result['metric_contract'];
    if (m == null) return null;
    final change = result['observed_change'],
        comparison = result['comparison'],
        p = result['provenance'];
    if (m is! Map ||
        m['schema_version'] != 1 ||
        !['hydration', 'texture', 'redness'].contains(m['metric']) ||
        m['unit'] != 'score_0_to_100' ||
        m['delta_unit'] != 'score_points' ||
        !['manual', 'image_proxy'].contains(m['source']) ||
        m['direction'] !=
            (m['metric'] == 'redness'
                ? 'lower_is_better'
                : 'higher_is_better') ||
        m['aggregation'] != 'within_UTC_day_mean_then_equal_day_mean' ||
        m['evaluation_algorithm'] != 'experiment_v2_rules_1' ||
        m['clinical_measurement'] != false ||
        ![
          'recorded',
          'missing',
          'mixed',
        ].contains(m['measurement_algorithm_provenance']) ||
        m['measurement_algorithm_versions'] is! List ||
        (m['measurement_algorithm_versions'] as List).length > 100 ||
        !(m['measurement_algorithm_versions'] as List).every(
          (v) => v is String && v.isNotEmpty && v.length <= 255,
        ) ||
        change is! Map ||
        change['metric'] != m['metric'] ||
        comparison is! Map ||
        comparison['measurement_source'] != m['source'] ||
        p is! Map ||
        p['algorithm'] != m['evaluation_algorithm']) {
      throw const FormatException('Unsupported evaluation metric contract');
    }
    final versions = (m['measurement_algorithm_versions'] as List)
        .cast<String>();
    if (m['measurement_algorithm_provenance'] == 'mixed' && versions.isEmpty ||
        versions.toSet().length != versions.length ||
        m['measurement_algorithm_provenance'] == 'recorded' &&
            versions.length != 1 ||
        m['measurement_algorithm_provenance'] == 'missing' &&
            versions.isNotEmpty ||
        m['source'] == 'image_proxy' &&
            m['measurement_algorithm_provenance'] == 'mixed' &&
            [
              'likely_associated_improvement',
              'likely_associated_worsening',
            ].contains(result['label'])) {
      throw const FormatException('Contradictory method provenance');
    }
    for (final key in ['baseline_mean', 'experiment_mean']) {
      final n = change[key];
      if (n != null && (n is! num || !n.isFinite || n < 0 || n > 100)) {
        throw const FormatException('Invalid score');
      }
    }
    final delta = change['delta_points'];
    if (delta != null &&
        (delta is! num || !delta.isFinite || delta.abs() > 100)) {
      throw const FormatException('Invalid score difference');
    }
    return ExperimentMetricContract._(
      m['metric'] as String,
      m['source'] as String,
      m['direction'] as String,
      List.unmodifiable(versions),
      m['measurement_algorithm_provenance'] as String,
    );
  }

  static bool validAdherence(Map result) {
    final a = result['adherence'];
    if (a is! Map) return false;
    if (a.isEmpty) {
      return true; // Legacy unavailable evidence, never zero coverage.
    }
    final expected = a['expected_slots'],
        reported = a['reported_slots'],
        followed = a['followed_slots'];
    if (expected is! int ||
        expected < 0 ||
        reported is! int ||
        reported < 0 ||
        reported > expected ||
        followed is! int ||
        followed < 0 ||
        followed > reported ||
        a['source'] != 'user_reported' ||
        !['completed', 'skipped'].contains(a['expected_status'])) {
      return false;
    }
    for (final key in ['coverage', 'followed_fraction']) {
      final value = a[key];
      final count = key == 'coverage' ? reported : followed;
      if (value != null &&
          (value is! num ||
              !value.isFinite ||
              (value - (expected == 0 ? 0 : count / expected)).abs() > 1e-9)) {
        return false;
      }
    }
    return true;
  }

  static bool accepts(Map result) {
    try {
      parse(result);
      final c = result['confounders'];
      if (c is! Map) return false;
      for (final key in ['unusual_days', 'cycle_context_days']) {
        if (c[key] != null && (c[key] is! int || c[key] < 0)) return false;
      }
      for (final key in [
        'baseline_unusual_conditions',
        'routine_changed_after_activation',
        'product_changed_after_activation',
        'baseline_inconsistent_routine_reports',
        'inconsistent_routine_reports',
      ]) {
        if (c[key] != null && c[key] is! bool) return false;
      }
      return validAdherence(result);
    } catch (_) {
      return false;
    }
  }
}
