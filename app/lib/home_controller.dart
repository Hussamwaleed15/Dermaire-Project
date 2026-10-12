import 'dart:convert';
import 'clinical/clinical_models.dart' show timestamp;
import 'package:flutter/foundation.dart';
import 'services/api_service.dart';

abstract class HomeRepository {
  Future<Map<String, dynamic>> read();
}

class RemoteHomeRepository implements HomeRepository {
  @override
  Future<Map<String, dynamic>> read() => ApiService.instance.getHome();
}

class HomeController extends ChangeNotifier {
  HomeController(this.repository);
  final HomeRepository repository;
  Map<String, dynamic>? _snapshot;
  int _generation = 0;
  bool loading = false;
  bool _disposed = false;
  int? _session;
  DateTime? retrievedAt;
  bool stale = false;
  void markStale() {
    if (_disposed) return;
    _generation++;
    loading = false;
    stale = _snapshot != null;
    notifyListeners();
  }

  String? error;
  String get today => DateTime.now().toUtc().toIso8601String().split('T').first;
  bool get available =>
      !_disposed &&
      _session == ApiService.instance.sessionGeneration &&
      !stale &&
      !loading &&
      error == null &&
      _snapshot?['date'] == today;
  Map<String, dynamic>? get current => available
      ? jsonDecode(jsonEncode(_snapshot)) as Map<String, dynamic>
      : null;

  void validate(Map<String, dynamic> value) {
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

  Future<bool> refresh() async {
    if (_disposed) return false;
    final generation = ++_generation;
    final session = ApiService.instance.sessionGeneration;
    _session = session;
    bool valid() =>
        !_disposed &&
        generation == _generation &&
        session == ApiService.instance.sessionGeneration;
    loading = true;
    stale = _snapshot != null;
    error = null;
    notifyListeners();
    try {
      final value = await repository.read().timeout(
        const Duration(seconds: 15),
      );
      if (!valid()) return false;
      validate(value);
      _snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
      retrievedAt = DateTime.now().toUtc();
      stale = false;
      loading = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (!valid()) return false;
      loading = false;
      error = 'Home unavailable. Connect and refresh to confirm current data.';
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _generation++;
    _snapshot = null;
    _session = null;
    retrievedAt = null;
    stale = false;
    loading = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
