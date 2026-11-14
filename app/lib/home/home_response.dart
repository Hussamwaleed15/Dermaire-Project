import '../clinical/clinical_models.dart' show timestamp, object, text;
import '../services/api_exception.dart';

/// The server's observation projection is separate from measurement completion.
class HomeObservationSummary {
  HomeObservationSummary(Map<String, dynamic> value)
    : id = text(value['id']),
      createdAt = timestamp(value['created_at']),
      moment = text(value['time_of_day']),
      kind = text(value['kind']) {
    if (id.isEmpty ||
        !['Morning', 'Evening'].contains(moment) ||
        !['report_only', 'report_and_measurement'].contains(kind) ||
        value['measurement_available'] is! bool ||
        value['measurement_available'] != (kind == 'report_and_measurement')) {
      throw const FormatException('Invalid Home observation summary');
    }
  }
  final String id, moment, kind;
  final DateTime createdAt;
}

class HomeObservationStatus {
  HomeObservationStatus.fromHome(Map<String, dynamic> home)
    : completedToday =
          object(home['observation_status'])['today_completed'] == true,
      recent = List.unmodifiable(
        (object(home['observation_status'])['recent'] as List).map(
          (v) => HomeObservationSummary(object(v)),
        ),
      ) {
    final value = object(home['observation_status']);
    final asOf = timestamp(home['as_of']);
    String day(DateTime at) => at.toUtc().toIso8601String().split('T').first;
    if (value['schema_version'] != 1 ||
        value['day_basis'] != 'UTC' ||
        value['today_completed'] is! bool ||
        recent.length > 2 ||
        recent.map((r) => r.id).toSet().length != recent.length ||
        recent.any((r) => r.createdAt.isAfter(asOf)) ||
        completedToday != recent.any((r) => day(r.createdAt) == home['date']) ||
        (home['today_checked_in'] != true &&
            recent.any(
              (r) =>
                  r.kind == 'report_and_measurement' &&
                  day(r.createdAt) == home['date'],
            )) ||
        recent.any(
          (r) =>
              r.kind == 'report_only' &&
              (home['journal'] as List).any((j) => object(j)['id'] == r.id),
        )) {
      throw const FormatException('Unverified Home observation status');
    }
    for (var i = 1; i < recent.length; i++) {
      final previous = recent[i - 1], current = recent[i];
      if (current.createdAt.isAfter(previous.createdAt) ||
          current.createdAt == previous.createdAt &&
              current.id.compareTo(previous.id) >= 0) {
        throw const FormatException('Unordered Home observations');
      }
    }
  }
  final bool completedToday;
  final List<HomeObservationSummary> recent;
}

void validateHomeResponse(Map<String, dynamic> value, String today) {
  final asOf = value['as_of'];
  timestamp(asOf); // UTC-aware server projection time, never a local date.
  if (asOf is! String ||
      DateTime.tryParse(asOf) == null ||
      DateTime.parse(asOf).toUtc().toIso8601String().split('T').first !=
          value['date'] ||
      value['date'] != today ||
      value['today_checked_in'] is! bool ||
      value['journal'] is! List ||
      (value['journal'] as List).length > 2) {
    throw ApiException('Invalid home response');
  }
  // Older deployments may omit this additive field. Absence is unavailable,
  // never false; a supplied malformed projection fails the read closed.
  if (value.containsKey('observation_status')) {
    HomeObservationStatus.fromHome(value);
  }
  final experiment = value['experiment'];
  if (experiment != null) {
    if (experiment is! Map ||
        experiment['id'] is! String ||
        (experiment['id'] as String).isEmpty ||
        !['active', 'paused', 'baseline'].contains(experiment['status']) ||
        experiment['current_day'] is! int ||
        experiment['target_days'] is! int ||
        experiment['target_days'] < 1 ||
        experiment['current_day'] < 1 ||
        experiment['current_day'] > experiment['target_days'] ||
        experiment['primary_concern'] is! String ||
        (experiment['product_name'] != null &&
            experiment['product_name'] is! String)) {
      throw ApiException('Invalid home experiment');
    }
    for (final key in [
      'redness_delta_percent',
      'texture_delta_percent',
      'hydration_delta_percent',
    ]) {
      final delta = experiment[key];
      if (!experiment.containsKey(key) ||
          (delta != null && (delta is! num || !delta.isFinite))) {
        throw ApiException('Invalid home comparison');
      }
    }
  } else if (!value.containsKey('experiment')) {
    throw ApiException('Missing home experiment');
  }
  final ids = <String>{};
  for (final entry in value['journal'] as List) {
    if (entry is! Map ||
        entry['id'] is! String ||
        (entry['id'] as String).isEmpty ||
        entry['created_at'] is! String ||
        DateTime.tryParse(entry['created_at']) == null ||
        !ids.add(entry['id'] as String) ||
        !['Morning', 'Evening'].contains(entry['time_of_day']) ||
        !['manual', 'image_proxy'].contains(entry['measurement_source'])) {
      throw ApiException('Unconfirmed home journal');
    }
    timestamp(entry['created_at'], naiveUtc: true);
    for (final key in ['hydration_score', 'texture_score', 'redness_score']) {
      final score = entry[key];
      if (score is! num || !score.isFinite || score < 0 || score > 100) {
        throw ApiException('Invalid home measurement');
      }
    }
  }
}
