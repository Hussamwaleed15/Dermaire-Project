import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import '../routine/routine_controller.dart';
import 'experiment_contract.dart';

abstract class ExperimentRepository {
  Future<List<Map<String, dynamic>>> read();
  Future<Map<String, dynamic>> write(String path, Map<String, dynamic> payload);
}

class RemoteExperimentRepository implements ExperimentRepository {
  final api = ApiService.instance;
  @override
  Future<List<Map<String, dynamic>>> read() => readPage(0);
  Future<List<Map<String, dynamic>>> readPage(int offset) async {
    final generation = api.sessionGeneration, owner = api.observationOwner;
    final rows =
        (await api.patientResource(
                  'experiments?limit=100&offset=$offset',
                  generation,
                )
                as List)
            .cast<Map<String, dynamic>>();
    if (owner == null ||
        !rows.every((r) => ExperimentContract.valid(r, owner)) ||
        rows.map((r) => r['id']).toSet().length != rows.length) {
      throw const FormatException('Invalid owned experiments');
    }
    return rows;
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> payload,
  ) => writeChecked(path, payload);
  Future<Map<String, dynamic>> writeChecked(
    String path,
    Map<String, dynamic> payload, {
    String method = 'POST',
    Map<String, dynamic>? expected,
    Map<String, dynamic>? expectedRoutine,
  }) async {
    final generation = api.sessionGeneration, owner = api.observationOwner!;
    if (path.isEmpty && !ExperimentContract.draft(payload) ||
        method == 'PATCH' &&
            (!ExperimentContract.draft(
              payload['definition'] as Map<String, dynamic>,
            ))) {
      throw const FormatException('Invalid draft');
    }
    if (path.isNotEmpty) {
      final id = path.split('/').first;
      final current =
          await api.patientResource('experiments/$id', generation)
              as Map<String, dynamic>;
      if (!ExperimentContract.valid(current, owner) ||
          current['id'] != id ||
          current['engine_version'] != 2 ||
          expected == null ||
          !ExperimentContract.valid(expected, owner) ||
          expected['id'] != id) {
        throw const FormatException('Invalid reviewed experiment');
      }
      if (![
        'revision',
        'revision_protected',
        'status',
        'intervention',
        'routine_entry_id',
        'product_id',
        'start_date',
        'target_days',
        'goal',
        'notes',
        'definition_snapshot',
      ].every((k) => RoutineController.sameWire(current[k], expected[k]))) {
        throw RequestFailure.http(412);
      }
    }
    int? routineRevision;
    if (path.endsWith('/activate') &&
        (expectedRoutine != null ||
            expected?.containsKey('revision') == true)) {
      if (expectedRoutine == null ||
          !RoutineController.validRow(expectedRoutine, 'user_configured') ||
          expectedRoutine['id'] != expected?['routine_entry_id'] ||
          expectedRoutine['product_id'] != expected?['product_id']) {
        throw RequestFailure.http(412);
      }
      final currentRoutine =
          await api.patientResource(
                'routine/entries/${expectedRoutine['id']}',
                generation,
              )
              as Map<String, dynamic>;
      if (!RoutineController.validRow(currentRoutine, 'user_configured') ||
          !sameRoutineConfiguration(currentRoutine, expectedRoutine)) {
        throw RequestFailure.http(412);
      }
      routineRevision = expectedRoutine['revision'] as int?;
    }
    final receipt =
        await api.patientResource(
              path.isEmpty ? 'experiments' : 'experiments/$path',
              generation,
              method: method,
              payload: payload,
              expectedRevision: path.isEmpty
                  ? null
                  : expected?['revision'] as int?,
              expectedRoutineRevision: routineRevision,
            )
            as Map<String, dynamic>;
    final evaluating = path.endsWith('/evaluate');
    final id =
        (evaluating ? receipt['experiment_id'] : receipt['id']) as String;
    if (evaluating
        ? !ExperimentContract.result(receipt, id)
        : !ExperimentContract.valid(receipt, owner)) {
      throw const FormatException('Unconfirmed experiment receipt');
    }
    if (path.isNotEmpty && id != path.split('/').first ||
        path.isEmpty &&
            !ExperimentContract.definitionMatches(receipt, payload) ||
        method == 'PATCH' &&
            (!ExperimentContract.definitionMatches(
                  receipt,
                  payload['definition'] as Map<String, dynamic>,
                ) ||
                receipt['notes'] != payload['notes'])) {
      throw const FormatException('Wrong mutation confirmation');
    }
    final verified =
        await api.patientResource('experiments/$id', generation)
            as Map<String, dynamic>;
    if (!ExperimentContract.valid(verified, owner) ||
        verified['id'] != id ||
        (evaluating
            ? !RoutineController.sameWire(verified['result'], receipt)
            : ![
                'status',
                'intervention',
                'routine_entry_id',
                'product_id',
                'start_date',
                'target_days',
                'goal',
                'notes',
                'definition_snapshot',
              ].every(
                (k) => RoutineController.sameWire(verified[k], receipt[k]),
              ))) {
      throw const FormatException('Experiment readback failed');
    }
    return evaluating ? verified['result'] as Map<String, dynamic> : verified;
  }
}

bool sameRoutineConfiguration(
  Map<String, dynamic> current,
  Map<String, dynamic> original,
) => [
  'id',
  'product_id',
  'product_name',
  'schedule',
  'frequency',
  'active',
  'instructions',
  'am_order',
  'pm_order',
  'start_date',
  'end_date',
  'updated_at',
  'revision',
  'revision_protected',
].every((key) => RoutineController.sameWire(current[key], original[key]));

class ExperimentController extends ChangeNotifier {
  ExperimentController(this.repository, {this.onConfirmed}) {
    if (remote) {
      session = ApiService.instance.sessionGeneration;
      ApiService.instance.addListener(sessionChanged);
    }
  }
  bool get remote => repository is RemoteExperimentRepository;
  int session = 0;
  bool stale = false, loadingMore = false, hasMore = false;
  final Set<String> uncertain = {};
  void sessionChanged() {
    if (!_disposed &&
        (session != ApiService.instance.sessionGeneration ||
            !ApiService.instance.canReadPatientClinicalStatus)) {
      session = ApiService.instance.sessionGeneration;
      clear();
    }
  }

  final ExperimentRepository repository;
  final Future<void> Function(int generation)? onConfirmed;
  List<Map<String, dynamic>>? rows;
  bool loading = false;
  bool saving = false;
  String? error;
  RequestFailure? readFailure;
  DateTime? lastConfirmedAt;
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
    if (_disposed || saving || loadingMore || loading) return false;
    final generation = ++_generation;
    loading = true;
    stale = rows != null;
    readFailure = null;
    error = null;
    notifyListeners();
    try {
      final response = await repository.read();
      if (!response.every(valid)) {
        throw const FormatException('Invalid experiment response');
      }
      if (generation != _generation || _disposed) return false;
      lastConfirmedAt = DateTime.now().toUtc();
      rows = response;
      stale = false;
      hasMore = response.length == 100;
    } catch (failure) {
      if (generation != _generation || _disposed) return false;
      stale = true;
      readFailure = RequestFailure.from(failure);
      error = 'Experiments unavailable. ${readFailure!.message}';
    }
    if (generation != _generation || _disposed) return false;
    loading = false;
    notifyListeners();
    return rows != null && error == null;
  }

  Future<bool> write(
    String path,
    Map<String, dynamic> payload, {
    String method = 'POST',
    Map<String, dynamic>? expected,
    Map<String, dynamic>? expectedRoutine,
  }) async {
    if (_disposed ||
        saving ||
        loading ||
        (remote && (stale || rows == null || uncertain.contains(path)))) {
      return false;
    }
    final generation = _generation;
    final sessionGeneration = ApiService.instance.sessionGeneration;
    var operationGeneration = generation;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final response = remote
          ? await (repository as RemoteExperimentRepository).writeChecked(
              path,
              payload,
              method: method,
              expected: expected,
              expectedRoutine: expectedRoutine,
            )
          : await repository.write(path, payload);
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
          (!payload.entries.every(
                (e) => e.key == 'start_date'
                    ? response[e.key] is String &&
                          (response[e.key] as String).startsWith(
                            e.value as String,
                          )
                    : matches(response[e.key], e.value),
              ) ||
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
        if (remote && !_disposed && operationGeneration == _generation) {
          uncertain.add(path);
          stale = true;
          notifyListeners();
        }
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
      await onConfirmed?.call(sessionGeneration);
      return !_disposed && operationGeneration == _generation;
    } catch (failure) {
      if (operationGeneration != _generation || _disposed) {
        return false;
      }
      final problem = RequestFailure.from(failure);
      if (remote) {
        if (path.isEmpty || problem.kind != RequestFailureKind.rejected) {
          uncertain.add(path);
        }
        stale = true;
      }
      error = 'Save unconfirmed. ${problem.message}';
      saving = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> loadMore() async {
    if (!remote ||
        _disposed ||
        loading ||
        saving ||
        loadingMore ||
        stale ||
        !hasMore ||
        rows == null) {
      return;
    }
    final generation = _generation;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await (repository as RemoteExperimentRepository).readPage(
        rows!.length,
      );
      if (_disposed || generation != _generation) return;
      final ids = rows!.map((r) => r['id']).toSet();
      if (!page.every((r) => ids.add(r['id']))) {
        throw const FormatException('Experiment history changed');
      }
      rows = [...rows!, ...page];
      hasMore = page.length == 100;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      stale = true;
      error = 'History unavailable or changed. Refresh before making changes.';
    } finally {
      if (!_disposed && generation == _generation) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  void clear() {
    _generation++;
    stale = false;
    loadingMore = false;
    hasMore = false;
    uncertain.clear();
    readFailure = null;
    lastConfirmedAt = null;
    rows = null;
    error = null;
    loading = saving = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (remote) ApiService.instance.removeListener(sessionChanged);
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
