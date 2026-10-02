import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

abstract class RoutineRepository {
  Future<List<Map<String, dynamic>>> read(String resource);
  Future<Map<String, dynamic>> write(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  });
}

class RemoteRoutineRepository implements RoutineRepository {
  @override
  Future<List<Map<String, dynamic>>> read(String resource) async =>
      (await ApiService.instance.routineRequest(resource) as List)
          .cast<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> write(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async =>
      await ApiService.instance.routineRequest(
            resource,
            method: method,
            payload: payload,
          )
          as Map<String, dynamic>;
}

class RoutineController extends ChangeNotifier {
  RoutineController(this.repository);
  final RoutineRepository repository;
  List<Map<String, dynamic>>? entries;
  List<Map<String, dynamic>>? history;
  bool loading = false;
  bool saving = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;
  bool valid(Map<String, dynamic> row, String source) =>
      row['id'] is String &&
      (row['id'] as String).isNotEmpty &&
      row['source'] == source &&
      row['created_at'] is String &&
      DateTime.tryParse(row['created_at'] as String) != null &&
      (source == 'user_configured'
          ? row['product_id'] is String &&
                row['product_name'] is String &&
                ['AM', 'PM', 'BOTH'].contains(row['schedule']) &&
                row['frequency'] == 'daily' &&
                row['active'] is bool &&
                row['start_date'] is String &&
                DateTime.tryParse(row['start_date'] as String) != null &&
                row['updated_at'] is String &&
                DateTime.tryParse(row['updated_at'] as String) != null &&
                row['am_order'] is int &&
                row['pm_order'] is int
          : row['routine_entry_id'] is String &&
                ['AM', 'PM'].contains(row['slot']) &&
                ['completed', 'skipped'].contains(row['status']) &&
                row['date'] is String &&
                DateTime.tryParse(row['date'] as String) != null &&
                row['configuration_snapshot'] is Map);
  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    entries = null;
    history = null;
    error = null;
    notifyListeners();
    try {
      final configured = await repository.read('entries');
      final reported = await repository.read('adherence');
      if (!configured.every((e) => valid(e, 'user_configured')) ||
          !reported.every((e) => valid(e, 'user_reported'))) {
        throw const FormatException('Invalid routine response');
      }
      if (generation != _generation || _disposed) return;
      entries = configured;
      history = reported;
    } catch (_) {
      if (generation != _generation || _disposed) return;
      error = 'Routine unavailable. Refresh to try again.';
    }
    if (generation != _generation || _disposed) return;
    loading = false;
    notifyListeners();
  }

  Future<bool> write(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    if (saving || loading) return false;
    final generation = _generation;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final row = await repository.write(resource, payload, method: method);
      final evidence = resource == 'adherence';
      if (!valid(row, evidence ? 'user_reported' : 'user_configured') ||
          !payload.entries.every((e) => row[e.key] == e.value) ||
          (method == 'PATCH' && row['id'] != resource.split('/').last) ||
          (evidence && row['configuration_snapshot'] is! Map)) {
        throw const FormatException('Write not confirmed');
      }
      if (generation != _generation || _disposed) return false;
      saving = false;
      await refresh();
      return !_disposed && _generation == generation + 1;
    } catch (_) {
      if (generation != _generation || _disposed) return false;
      error = 'Save unconfirmed. Refresh before retrying.';
      saving = false;
      notifyListeners();
      return false;
    }
  }

  void clear() {
    ++_generation;
    entries = null;
    history = null;
    loading = false;
    saving = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
