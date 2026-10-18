import '../routine/routine_controller.dart';

/// Actual owned ExperimentOut/EvaluationOut wire data; legacy records are read-only.
abstract final class ExperimentContract {
  static bool text(Object? v) => v is String && v.isNotEmpty;
  static bool instant(Object? v) => v is String && DateTime.tryParse(v) != null;
  static bool number(Object? v) => v is num && v.isFinite;
  static const states = [
    'draft',
    'active',
    'completed',
    'stopped',
    'cancelled',
  ];
  static const labels = [
    'likely_associated_improvement',
    'likely_associated_worsening',
    'no_meaningful_change',
    'insufficient_evidence',
    'confounded_or_low_adherence',
  ];
  static bool result(Object? data, String id) {
    if (data is! Map ||
        !text(data['id']) ||
        data['experiment_id'] != id ||
        !instant(data['created_at']) ||
        data['result'] is! Map) {
      return false;
    }
    final r = data['result'] as Map;
    return r['engine_version'] == 2 &&
        labels.contains(r['label']) &&
        [
          'insufficient',
          'limited',
          'moderate',
        ].contains(r['evidence_strength']) &&
        r['evidence_summary'] is String &&
        instant(r['evaluated_at']) &&
        r['limitations'] is List &&
        (r['limitations'] as List).every((v) => v is String) &&
        [
          'comparison',
          'adherence',
          'confounders',
          'observed_change',
          'coverage',
          'provenance',
        ].every((k) => r[k] is Map) &&
        r['provenance']['source'] == 'server_derived' &&
        [
          'baseline_mean',
          'experiment_mean',
          'delta_points',
          'descriptive_threshold_points',
        ].every(
          (k) =>
              r['observed_change'][k] == null ||
              number(r['observed_change'][k]),
        );
  }

  static bool valid(Map<String, dynamic> r, String owner) {
    if (!RoutineController.validRevision(r) ||
        !text(r['id']) ||
        r['user_id'] != owner ||
        !instant(r['created_at']) ||
        !instant(r['start_date']) ||
        r['coverage'] is! Map ||
        r['target_days'] is! int ||
        r['target_days'] < 1 ||
        r['current_day'] is! int) {
      return false;
    }
    final coverage = r['coverage'] as Map;
    if (![
          'elapsed_days',
          'observed_days',
          'checkins',
        ].every((k) => coverage[k] is int && coverage[k] >= 0) ||
        !['adherence_coverage', 'context_coverage'].every(
          (k) => number(coverage[k]) && coverage[k] >= 0 && coverage[k] <= 1,
        )) {
      return false;
    }
    if (r['engine_version'] != 2) {
      return r['engine_version'] == null &&
          [...states, 'paused', 'baseline'].contains(r['status']) &&
          r['result'] == null;
    }
    if (!states.contains(r['status']) ||
        r['source'] != 'user_configured' ||
        !text(r['routine_entry_id']) ||
        !text(r['product_id']) ||
        !['hydration', 'texture', 'redness'].contains(r['primary_concern']) ||
        r['target_days'] < 7 ||
        r['target_days'] > 90 ||
        r['intervention'] is! Map) {
      return false;
    }
    final change = r['intervention'] as Map;
    if (![
          'start_entry',
          'stop_entry',
          'change_schedule',
        ].contains(change['type']) ||
        (change['type'] == 'stop_entry'
            ? change['schedule'] != null
            : !['AM', 'PM', 'BOTH'].contains(change['schedule']))) {
      return false;
    }
    if (r['status'] != 'draft' &&
        r['status'] != 'cancelled' &&
        (r['definition_snapshot'] is! Map || !instant(r['activated_at']))) {
      return false;
    }
    return r['result'] == null || result(r['result'], r['id'] as String);
  }

  static bool definitionMatches(
    Map<String, dynamic> row,
    Map<String, dynamic> definition,
  ) => definition.entries.every(
    (e) => e.key == 'start_date'
        ? row[e.key] is String &&
              (row[e.key] as String).startsWith(e.value as String)
        : e.value is Map
        ? row[e.key] is Map &&
              (e.value as Map).entries.every(
                (v) => row[e.key][v.key] == v.value,
              )
        : row[e.key] == e.value,
  );
  static bool draft(Map<String, dynamic> p) =>
      text(p['routine_entry_id']) &&
      RoutineController.validDay(p['start_date']) &&
      p['target_days'] is int &&
      p['target_days'] >= 7 &&
      p['target_days'] <= 90 &&
      ['texture', 'hydration', 'redness'].contains(p['primary_concern']) &&
      (p['goal'] == null ||
          p['goal'] is String &&
              p['goal'].trim().isNotEmpty &&
              p['goal'].length <= 500) &&
      (p['notes'] == null ||
          p['notes'] is String && p['notes'].length <= 2000) &&
      p['intervention'] is Map &&
      [
        'start_entry',
        'stop_entry',
        'change_schedule',
      ].contains(p['intervention']['type']) &&
      (p['intervention']['type'] == 'stop_entry'
          ? p['intervention']['schedule'] == null
          : ['AM', 'PM', 'BOTH'].contains(p['intervention']['schedule']));
}
