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
    if (evidence) {
      final rows =
          (await api.patientResource(
                    'routine/adherence?routine_entry_id=${receipt['routine_entry_id']}&limit=100&offset=0',
                    generation,
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      final verified = rows.where((r) => r['id'] == receipt['id']).firstOrNull;
      if (verified == null ||
          !RoutineController.validRow(verified, 'user_reported') ||
          !RoutineController.sameWire(receipt, verified)) {
        throw const FormatException('Adherence readback not confirmed');
      }
      return verified;
    }
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
  bool loadingMore = false;
  bool historyHasMore = false;
  String writeKey(String resource, Map<String, dynamic> payload) =>
      resource == 'adherence'
      ? 'adherence:${payload['routine_entry_id']}:${payload['date']}:${payload['slot']}'
      : resource;
  static bool sameWire(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.entries.every(
            (e) => b.containsKey(e.key) && sameWire(e.value, b[e.key]),
          );
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => sameWire(a[i], b[i]));
    }
    return a == b;
  }

  static bool validDay(Object? value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return false;
    }
    final date = DateTime.tryParse(value);
    return date != null && date.toIso8601String().substring(0, 10) == value;
  }

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
                validDay(row['date']) &&
                row['configuration_snapshot'] is Map<String, dynamic> &&
                validRow(
                  row['configuration_snapshot'] as Map<String, dynamic>,
                  'user_configured',
                ) &&
                row['configuration_snapshot']['id'] ==
                    row['routine_entry_id'] &&
                (row['configuration_snapshot']['schedule'] == 'BOTH' ||
                    row['configuration_snapshot']['schedule'] == row['slot']));
  Future<void> refresh() async {
    if (_disposed || saving || loadingMore) return;
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final configured = await repository.read('entries');
      final reported = await repository.read(
        remote ? 'adherence?limit=100&offset=0' : 'adherence',
      );
      if (!configured.every((e) => valid(e, 'user_configured')) ||
          !reported.every((e) => valid(e, 'user_reported'))) {
        throw const FormatException('Invalid routine response');
      }
      if (generation != _generation || _disposed) return;
      entries = configured;
      history = reported;
      historyHasMore = reported.length == 100;
      loadingMore = false;
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
            (entries == null ||
                stale ||
                uncertain.contains(writeKey(resource, payload))))) {
      return false;
    }
    if (resource == 'adherence' &&
        history?.any(
              (r) =>
                  r['routine_entry_id'] == payload['routine_entry_id'] &&
                  r['date'] == payload['date'] &&
                  r['slot'] == payload['slot'],
            ) ==
            true) {
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
        uncertain.add(writeKey(resource, payload));
        stale = true;
        notifyListeners();
      }
      return confirmed;
    } catch (_) {
      if (generation != _generation || _disposed) return false;
      if (remote) {
        uncertain.add(writeKey(resource, payload));
        stale = true;
      }
      error = 'Save unconfirmed. Refresh before retrying.';
      saving = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadMoreHistory() async {
    if (_disposed ||
        saving ||
        loading ||
        loadingMore ||
        stale ||
        !historyHasMore ||
        history == null) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await repository.read(
        'adherence?limit=100&offset=${history!.length}',
      );
      if (_disposed || generation != _generation) return;
      final ids = history!.map((r) => r['id']).toSet();
      if (!page.every((r) => valid(r, 'user_reported') && ids.add(r['id']))) {
        throw const FormatException('History changed. Refresh.');
      }
      history = [...history!, ...page];
      historyHasMore = page.length == 100;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      stale = true;
      error =
          'History refresh failed or changed. Previously confirmed reports remain; refresh before recording.';
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    ++_generation;
    uncertain.clear();
    stale = false;
    loadingMore = false;
    historyHasMore = false;
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
