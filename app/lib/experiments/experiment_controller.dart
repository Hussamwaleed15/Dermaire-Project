import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import '../routine/routine_controller.dart';
import 'experiment_contract.dart';
import '../integration/configuration_receipt.dart';
import '../integration/contract.dart';

abstract class ExperimentRepository {
  Future<List<Map<String, dynamic>>> read();
  Future<Map<String, dynamic>> write(String path, Map<String, dynamic> payload);
}

class RemoteExperimentRepository implements ExperimentRepository {
  final api = ApiService.instance;
  static const intentId = 'configuration:experiment';
  ConfigurationPending? get pending =>
      api.integrationIntents[intentId] is ConfigurationPending
      ? api.integrationIntents[intentId] as ConfigurationPending
      : null;
  void guard(ConfigurationPending op) {
    if (!api.isCurrentSession(op.generation) ||
        api.observationOwner != op.owner ||
        !api.canReadPatientClinicalStatus ||
        !identical(pending, op)) {
      throw const FormatException('Experiment request session changed');
    }
  }

  Future<bool> reconcileConfiguration({
    bool retryOriginal = false,
    bool finishUnavailableReview = false,
  }) async {
    final op = pending;
    if (op == null) return true;
    guard(op);
    final raw = await api.patientResource(op.lookupPath, op.generation);
    guard(op);
    final receipt = ConfigurationReceipt.parse(raw, op);
    op.lookupStatus = receipt.status;
    op.availability = receipt.availability;
    if (receipt.status == 'unknown') {
      op.uncertain = true;
      if (!retryOriginal) return false;
      await dispatchConfiguration(op);
      return true;
    }
    final original = receipt.original;
    if (original != null &&
        (op.operation == 'evaluate'
            ? !ExperimentContract.result(original, receipt.resource!)
            : !ExperimentContract.valid(original, op.owner) ||
                  original['id'] != receipt.resource ||
                  original['revision'] != receipt.revision)) {
      throw const FormatException('Invalid original experiment result');
    }
    try {
      final current =
          await api.patientResource(
                'experiments/${receipt.resource}',
                op.generation,
              )
              as Map<String, dynamic>;
      if (!ExperimentContract.valid(current, op.owner) ||
          current['id'] != receipt.resource) {
        throw const FormatException('Invalid current experiment');
      }
    } on PatientResourceMissing {
      /* Do not recreate a historical erased experiment. */
    }
    guard(op);
    if ((receipt.status == 'expired' || receipt.availability == 'erased') &&
        !finishUnavailableReview) {
      return false;
    }
    api.integrationIntents.remove(intentId);
    return true;
  }

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
    if (!api.canReadPatientClinicalStatus || api.observationOwner == null) {
      throw RequestFailure.session();
    }
    if (!(path.isEmpty && method == 'POST' ||
        RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(path) &&
            ['PATCH', 'DELETE'].contains(method) ||
        RegExp(r'^[A-Za-z0-9_-]+/(activate|finish|evaluate)$').hasMatch(path) &&
            method == 'POST')) {
      throw ArgumentError('Unsupported experiment write');
    }
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
    if (pending != null) {
      throw const FormatException(
        'Resolve the original experiment request first',
      );
    }
    final operation = path.isEmpty
        ? 'create'
        : method == 'PATCH'
        ? 'edit'
        : method == 'DELETE'
        ? 'cancel'
        : path.split('/').last;
    final op = ConfigurationPending(
      domain: 'experiment',
      operation: operation,
      owner: owner,
      generation: generation,
      path: path.isEmpty ? 'experiments' : 'experiments/$path',
      body: payload,
      method: method,
      resource: path.isEmpty ? null : path.split('/').first,
      expectedRevision: path.isEmpty ? null : expected?['revision'] as int?,
      expectedRoutineRevision: routineRevision,
    );
    api.integrationIntents[intentId] = op;
    return dispatchConfiguration(op);
  }

  Future<Map<String, dynamic>> dispatchConfiguration(
    ConfigurationPending op,
  ) async {
    guard(op);
    final wasUncertain = op.uncertain;
    try {
      final receipt =
          await api.patientResource(
                op.path,
                op.generation,
                method: op.method,
                payload: op.method == 'DELETE' ? null : op.body,
                expectedRevision: op.expectedRevision,
                expectedRoutineRevision: op.expectedRoutineRevision,
                idempotencyKey: op.key,
              )
              as Map<String, dynamic>;
      final path = op.resource == null
          ? ''
          : op.path.substring('experiments/'.length);
      final payload = op.body,
          owner = op.owner,
          method = op.method,
          generation = op.generation;
      final evaluating = op.operation == 'evaluate';
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
      guard(op);
      api.integrationIntents.remove(intentId);
      return evaluating ? verified['result'] as Map<String, dynamic> : verified;
    } catch (failure) {
      if (identical(pending, op)) {
        if (!wasUncertain &&
            failure is IntegrationFailure &&
            [400, 403, 404, 409, 410, 412, 422, 428].contains(failure.status)) {
          api.integrationIntents.remove(intentId);
        } else {
          op.uncertain = true;
        }
      }
      rethrow;
    }
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
  ConfigurationPending? get configurationPending =>
      remote && ApiService.instance.canReadPatientClinicalStatus
      ? (repository as RemoteExperimentRepository).pending
      : null;
  Future<bool> recoverConfiguration({
    bool retryOriginal = false,
    bool finishUnavailableReview = false,
  }) async {
    if (_disposed ||
        saving ||
        loading ||
        !remote ||
        configurationPending == null) {
      return false;
    }
    final ticket = _generation,
        original = configurationPending!,
        sessionGeneration = ApiService.instance.sessionGeneration;
    var expectedTicket = ticket;
    var receiptResolved = false;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final resolved = await (repository as RemoteExperimentRepository)
          .reconcileConfiguration(
            retryOriginal: retryOriginal,
            finishUnavailableReview: finishUnavailableReview,
          );
      receiptResolved = resolved;
      if (_disposed || ticket != _generation) return false;
      if (resolved) {
        uncertain.remove(
          original.resource == null
              ? ''
              : original.path.substring('experiments/'.length),
        );
      }
      saving = false;
      expectedTicket = ticket + 1;
      await refresh();
      if (_disposed || _generation != expectedTicket) return false;
      if (resolved && !stale) {
        saving = true;
        notifyListeners();
        await onConfirmed?.call(sessionGeneration);
      }
      if (_disposed || _generation != expectedTicket) return false;
      if (!stale) {
        error = resolved
            ? finishUnavailableReview
                  ? 'Receipt review complete. No original request was repeated.'
                  : 'Original experiment request confirmed. Current experiment records refreshed.'
            : configurationPending?.lookupStatus == 'unknown'
            ? 'The original experiment request remains uncertain. No committed receipt is available yet.'
            : 'The original receipt content is expired or erased. Review current records before finishing receipt review.';
      }
      notifyListeners();
      return resolved && !stale;
    } catch (failure) {
      if (_disposed || expectedTicket != _generation) return false;
      stale = true;
      error =
          '${receiptResolved ? 'Original experiment request confirmed, but related information could not refresh.' : 'Experiment request remains unconfirmed.'} ${failure is IntegrationFailure ? RequestFailure.http(failure.status).message : RequestFailure.from(failure).message}';
      return false;
    } finally {
      if (!_disposed && expectedTicket == _generation) {
        saving = false;
        notifyListeners();
      }
    }
  }

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
      if (remote && configurationPending == null) uncertain.clear();
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
        (remote &&
            (stale ||
                rows == null ||
                uncertain.contains(path) ||
                configurationPending != null))) {
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
          if (configurationPending != null) uncertain.add(path);
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
      final problem = failure is IntegrationFailure
          ? RequestFailure.http(failure.status)
          : RequestFailure.from(failure);
      if (remote) {
        if (configurationPending != null) {
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
