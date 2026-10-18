import '../clinical/clinical_models.dart' show timestamp;
import '../services/api_exception.dart';

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
