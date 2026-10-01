import 'package:flutter/foundation.dart';
import 'services/api_service.dart';

abstract class ContextRepository {
  Future<Map<String, dynamic>> read(String day);
  Future<Map<String, dynamic>> write(String day, bool? unusual, int? cycleDay);
}

class RemoteContextRepository implements ContextRepository {
  @override
  Future<Map<String, dynamic>> read(String day) => ApiService.instance.getDailyContext(day);
  @override
  Future<Map<String, dynamic>> write(String day, bool? unusual, int? cycleDay) =>
      ApiService.instance.saveDailyContext(day, unusual, cycleDay);
}

class ContextController extends ChangeNotifier {
  ContextController(this.repository);
  final ContextRepository repository;
  Map<String, dynamic>? _snapshot;
  bool loading = false;
  String? error;
  int _generation = 0;
  String get today => DateTime.now().toUtc().toIso8601String().split('T').first;
  bool get available => !loading && error == null && _snapshot?['date'] == today;
  Map<String, dynamic>? get current => available ? Map.of(_snapshot!) : null;

  void validate(Map<String, dynamic> value, String day) {
    final cycle = value['cycle_day'];
    if (value['date'] != day || value['recorded'] is! bool ||
        value['source'] != 'user_reported' ||
        (value['unusual_conditions'] != null && value['unusual_conditions'] is! bool) ||
        (cycle != null && (cycle is! int || cycle < 1 || cycle > 60)) ||
        (value['recorded'] == false && (cycle != null || value['unusual_conditions'] != null || value['updated_at'] != null)) ||
        (value['recorded'] == true && (value['updated_at'] is! String ||
          DateTime.tryParse(value['updated_at'] as String) == null))) {
      throw ApiException('Invalid context confirmation');
    }
  }

  Future<bool> refresh() => _request();
  Future<bool> save(bool? unusual, int? cycleDay) =>
      _request(write: true, unusual: unusual, cycleDay: cycleDay);

  Future<bool> _request({bool write = false, bool? unusual, int? cycleDay}) async {
    if (loading) return false;
    final generation = ++_generation;
    final day = today;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final value = write ? await repository.write(day, unusual, cycleDay) : await repository.read(day);
      if (generation != _generation) return false;
      validate(value, day);
      if (write && (value['recorded'] != true || value['unusual_conditions'] != unusual ||
          value['cycle_day'] != cycleDay)) {
        throw ApiException('Context not confirmed');
      }
      _snapshot = Map.of(value);
      loading = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (generation != _generation) return false;
      loading = false;
      error = write ? 'Save unconfirmed. Your draft is still here. Refresh before retrying.' :
          'Context unavailable. Connect and retry.';
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _generation++;
    _snapshot = null;
    loading = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
