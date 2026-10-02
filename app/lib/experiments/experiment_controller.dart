import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

abstract class ExperimentRepository {
  Future<List<Map<String, dynamic>>> read();
  Future<Map<String, dynamic>> write(String path, Map<String, dynamic> payload);
}

class RemoteExperimentRepository implements ExperimentRepository {
  @override
  Future<List<Map<String, dynamic>>> read() async =>
      (await ApiService.instance.experimentRequest('') as List)
          .cast<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> payload,
  ) async =>
      await ApiService.instance.experimentRequest(
            path,
            method: 'POST',
            payload: payload,
          )
          as Map<String, dynamic>;
}

class ExperimentController extends ChangeNotifier {
  ExperimentController(this.repository);
  final ExperimentRepository repository;
  List<Map<String, dynamic>>? rows;
  bool loading = false;
  bool saving = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;
  static const labels = [
    'likely_associated_improvement',
    'likely_associated_worsening',
    'no_meaningful_change',
    'insufficient_evidence',
    'confounded_or_low_adherence',
  ];
  bool matches(dynamic actual, dynamic expected) => expected is Map
      ? actual is Map &&
            expected.entries.every((e) => matches(actual[e.key], e.value))
      : actual == expected;
  bool validResult(dynamic value) =>
      value is Map &&
      value['id'] is String &&
      value['experiment_id'] is String &&
      value['result'] is Map &&
      labels.contains(value['result']['label']) &&
      value['result']['evidence_summary'] is String &&
      value['result']['provenance'] is Map &&
      value['result']['limitations'] is List &&
      value['result']['coverage'] is Map &&
      value['result']['evaluated_at'] is String;
  bool valid(Map<String, dynamic> row) =>
      row['id'] is String &&
      (row['id'] as String).isNotEmpty &&
      row['created_at'] is String &&
      DateTime.tryParse(row['created_at']) != null &&
      [
        'draft',
        'active',
        'completed',
        'stopped',
        'cancelled',
        'paused',
        'baseline',
      ].contains(row['status']) &&
      row['coverage'] is Map &&
      row['target_days'] is int &&
      row['target_days'] > 0 &&
      (row['engine_version'] != 2 ||
          (row['source'] == 'user_configured' &&
              row['intervention'] is Map &&
              row['routine_entry_id'] is String)) &&
      (row['result'] == null || validResult(row['result']));

  Future<bool> refresh() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    rows = null;
    notifyListeners();
    try {
      final response = await repository.read();
      if (!response.every(valid)) {
        throw const FormatException('Invalid experiment response');
      }
      if (generation != _generation || _disposed) return false;
      rows = response;
    } catch (_) {
      if (generation != _generation || _disposed) return false;
      error = 'Experiments unavailable. Refresh to retry.';
    }
    if (generation != _generation || _disposed) return false;
    loading = false;
    notifyListeners();
    return rows != null;
  }

  Future<bool> write(String path, Map<String, dynamic> payload) async {
    if (saving || loading) return false;
    final generation = _generation;
    var operationGeneration = generation;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final response = await repository.write(path, payload);
      final evaluating = path.endsWith('/evaluate');
      if (evaluating ? !validResult(response) : !valid(response)) {
        throw const FormatException('Unconfirmed write');
      }
      final id = path.split('/').first;
      if (path.isNotEmpty &&
          (evaluating ? response['experiment_id'] : response['id']) != id) {
        throw const FormatException('Wrong experiment confirmation');
      }
      if (path.isEmpty &&
          (!payload.entries.every((e) => matches(response[e.key], e.value)) ||
              response['status'] != 'draft')) {
        throw const FormatException('Draft not confirmed');
      }
      if (path.endsWith('/activate') && response['status'] != 'active' ||
          path.endsWith('/finish') && response['status'] != payload['status']) {
        throw const FormatException('State not confirmed');
      }
      if (generation != _generation || _disposed) return false;
      saving = false;
      operationGeneration = generation + 1;
      final refreshed = await refresh();
      if (!refreshed || operationGeneration != _generation || _disposed) {
        return false;
      }
      final confirmedId = evaluating
          ? response['experiment_id']
          : response['id'];
      final persisted = rows!.where((r) => r['id'] == confirmedId).firstOrNull;
      if (persisted == null ||
          (evaluating
              ? (persisted['result'] is Map
                        ? persisted['result']['id']
                        : null) !=
                    response['id']
              : persisted['status'] != response['status'])) {
        throw const FormatException('Readback did not confirm write');
      }
      return true;
    } catch (_) {
      if (operationGeneration != _generation || _disposed) {
        return false;
      }
      error = 'Save unconfirmed. Refresh before retrying.';
      saving = false;
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _generation++;
    rows = null;
    error = null;
    loading = saving = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
