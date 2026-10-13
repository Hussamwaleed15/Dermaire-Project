import 'dart:async';
import 'dart:convert';
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
  final api = ApiService.instance;
  @override
  Future<List<Map<String, dynamic>>> read(String resource) async {
    final generation = api.sessionGeneration;
    final rows =
        (await api.patientResource('routine/$resource', generation) as List)
            .cast<Map<String, dynamic>>();
    if (!rows.every(
          (r) => RoutineController.validRow(
            r,
            resource.startsWith('entries')
                ? 'user_configured'
                : 'user_reported',
          ),
        ) ||
        rows.map((r) => r['id']).toSet().length != rows.length) {
      throw const FormatException('Invalid routine contract');
    }
    return rows;
  }

  @override
  Future<Map<String, dynamic>> write(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) => writeChecked(resource, payload, method: method);

  Future<Map<String, dynamic>> writeChecked(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
    String? expectedUpdatedAt,
  }) async {
    final generation = api.sessionGeneration;
    var patch = Map<String, dynamic>.of(payload);
    if (method == 'PATCH') {
      final current =
          await api.patientResource('routine/$resource', generation)
              as Map<String, dynamic>;
      if (!RoutineController.validRow(current, 'user_configured') ||
          current['id'] != resource.split('/').last ||
          expectedUpdatedAt == null ||
          current['updated_at'] != expectedUpdatedAt) {
        throw const FormatException('Routine changed. Reopen this step.');
      }
      patch.removeWhere((k, v) => current[k] == v);
      if (patch.isEmpty) return current;
    }
    final receipt =
        await api.patientResource(
              'routine/$resource',
              generation,
              method: method,
              payload: patch,
            )
            as Map<String, dynamic>;
    final evidence = resource == 'adherence';
    if (!RoutineController.validRow(
          receipt,
          evidence ? 'user_reported' : 'user_configured',
        ) ||
        !patch.entries.every((e) => receipt[e.key] == e.value)) {
      throw const FormatException('Unconfirmed routine mutation');
    }
    if (evidence) return receipt;
    final id = receipt['id'] as String;
    final verified =
        await api.patientResource('routine/entries/$id', generation)
            as Map<String, dynamic>;
    if (!RoutineController.validRow(verified, 'user_configured') ||
        jsonEncode(receipt) != jsonEncode(verified)) {
      throw const FormatException('Routine readback changed');
    }
    return verified;
  }
}

class RoutineController extends ChangeNotifier {
  RoutineController(this.repository) {
    if (remote) {
      session = ApiService.instance.sessionGeneration;
      ApiService.instance.addListener(sessionChanged);
    }
  }
  bool get remote => repository is RemoteRoutineRepository;
  int session = 0;
  void sessionChanged() {
    if (!_disposed &&
        (session != ApiService.instance.sessionGeneration ||
            !ApiService.instance.canReadPatientClinicalStatus)) {
      session = ApiService.instance.sessionGeneration;
      clear();
    }
  }

  final Set<String> uncertain = {};
  bool stale = false;
  final RoutineRepository repository;
  List<Map<String, dynamic>>? entries;
  List<Map<String, dynamic>>? history;
  bool loading = false;
  bool saving = false;
  String? error;
  int _generation = 0;
  bool _disposed = false;
  bool valid(Map<String, dynamic> row, String source) => validRow(row, source);
  static bool validRow(Map<String, dynamic> row, String source) =>
      row['id'] is String &&
      (row['id'] as String).isNotEmpty &&
      row['source'] == source &&
      row['created_at'] is String &&
      DateTime.tryParse(row['created_at'] as String) != null &&
      (source == 'user_configured'
          ? row['product_id'] is String &&
                (row['product_id'] as String).isNotEmpty &&
                row['product_name'] is String &&
                ['AM', 'PM', 'BOTH'].contains(row['schedule']) &&
                row['frequency'] == 'daily' &&
                row['active'] is bool &&
                row['start_date'] is String &&
                DateTime.tryParse(row['start_date'] as String) != null &&
                row['updated_at'] is String &&
                DateTime.tryParse(row['updated_at'] as String) != null &&
                row['am_order'] is int &&
                row['pm_order'] is int &&
                row['am_order'] >= 0 &&
                row['am_order'] <= 100 &&
                row['pm_order'] >= 0 &&
                row['pm_order'] <= 100
          : row['routine_entry_id'] is String &&
                ['AM', 'PM'].contains(row['slot']) &&
                ['completed', 'skipped'].contains(row['status']) &&
                row['date'] is String &&
                DateTime.tryParse(row['date'] as String) != null &&
                row['configuration_snapshot'] is Map);
  Future<void> refresh() async {
    if (_disposed || saving) return;
    final generation = ++_generation;
    loading = true;
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
      stale = false;
    } catch (_) {
      if (generation != _generation || _disposed) return;
      stale = true;
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
    String? expectedUpdatedAt,
  }) async {
    if (saving ||
        loading ||
        (remote &&
            (entries == null || stale || uncertain.contains(resource)))) {
      return false;
    }
    final generation = _generation;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final row = remote
          ? await (repository as RemoteRoutineRepository).writeChecked(
              resource,
              payload,
              method: method,
              expectedUpdatedAt: expectedUpdatedAt,
            )
          : await repository.write(resource, payload, method: method);
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
      final confirmed =
          !_disposed &&
          _generation == generation + 1 &&
          error == null &&
          entries != null &&
          history != null;
      if (!confirmed && remote && !_disposed && _generation == generation + 1) {
        uncertain.add(resource);
        stale = true;
        notifyListeners();
      }
      return confirmed;
    } catch (_) {
      if (generation != _generation || _disposed) return false;
      if (remote) {
        uncertain.add(resource);
        stale = true;
      }
      error = 'Save unconfirmed. Refresh before retrying.';
      saving = false;
      notifyListeners();
      return false;
    }
  }

  void clear() {
    ++_generation;
    uncertain.clear();
    stale = false;
    entries = null;
    history = null;
    loading = false;
    saving = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    if (remote) ApiService.instance.removeListener(sessionChanged);
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
