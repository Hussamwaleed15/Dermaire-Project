import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import '../integration/configuration_receipt.dart';
import '../integration/contract.dart';
import 'adherence_operation.dart';

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
  static const intentId = 'configuration:routine';
  ConfigurationPending? get pending =>
      api.integrationIntents[intentId] is ConfigurationPending
      ? api.integrationIntents[intentId] as ConfigurationPending
      : null;
  void guard(ConfigurationPending op) {
    if (!api.isCurrentSession(op.generation) ||
        api.observationOwner != op.owner ||
        !api.canReadPatientClinicalStatus ||
        !identical(pending, op)) {
      throw const FormatException('Routine request session changed');
    }
  }

  Future<Map<String, dynamic>> dispatchConfiguration(
    ConfigurationPending op,
  ) async {
    guard(op);
    final wasUncertain = op.uncertain;
    try {
      final original =
          await api.patientResource(
                op.path,
                op.generation,
                method: op.method,
                payload: op.body,
                expectedRevision: op.expectedRevision,
                idempotencyKey: op.key,
              )
              as Map<String, dynamic>;
      if (!RoutineController.validRow(original, 'user_configured') ||
          op.resource != null && original['id'] != op.resource ||
          !op.body.entries.every(
            (e) => RoutineController.sameWire(original[e.key], e.value),
          )) {
        throw const FormatException('Invalid original routine response');
      }
      final current =
          await api.patientResource(
                'routine/entries/${original['id']}',
                op.generation,
              )
              as Map<String, dynamic>;
      if (!RoutineController.validRow(current, 'user_configured') ||
          !RoutineController.sameWire(original, current)) {
        throw const FormatException('Routine current readback changed');
      }
      guard(op);
      api.integrationIntents.remove(intentId);
      return current;
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
        (!RoutineController.validRow(original, 'user_configured') ||
            original['id'] != receipt.resource ||
            original['revision'] != receipt.revision)) {
      throw const FormatException('Wrong original routine snapshot');
    }
    try {
      final current =
          await api.patientResource(
                'routine/entries/${receipt.resource}',
                op.generation,
              )
              as Map<String, dynamic>;
      if (!RoutineController.validRow(current, 'user_configured') ||
          current['id'] != receipt.resource) {
        throw const FormatException('Invalid current routine');
      }
    } on PatientResourceMissing {
      /* Historical receipt does not restore an erased row. */
    }
    guard(op);
    if ((receipt.status == 'expired' || receipt.availability == 'erased') &&
        !finishUnavailableReview) {
      return false;
    }
    api.integrationIntents.remove(intentId);
    return true;
  }

  static const adherenceIntentId = 'routine:adherence';
  AdherencePending? get adherencePending =>
      api.integrationIntents[adherenceIntentId] is AdherencePending
      ? api.integrationIntents[adherenceIntentId] as AdherencePending
      : null;
  void guardAdherence(AdherencePending op) {
    if (!api.isCurrentSession(op.generation) ||
        api.observationOwner != op.owner ||
        !api.canReadPatientClinicalStatus ||
        !identical(adherencePending, op)) {
      throw const FormatException('Adherence request session changed');
    }
  }

  Future<Map<String, dynamic>> dispatchAdherence(AdherencePending op) async {
    guardAdherence(op);
    final wasUncertain = op.uncertain;
    try {
      final record =
          await api.patientResource(
                op.path,
                op.generation,
                method: 'POST',
                payload: op.body,
                idempotencyKey: op.key,
              )
              as Map<String, dynamic>;
      final nested = record['receipt'];
      if (nested is! Map) {
        throw const FormatException('Missing keyed adherence receipt');
      }
      final receipt = AdherenceReceipt.parse({...nested, 'result': record}, op);
      if (!RoutineController.validRow(record, 'user_reported') ||
          receipt.status != 'committed') {
        throw const FormatException('Unconfirmed original report');
      }
      final rows =
          await api.patientResource(
                'routine/adherence?routine_entry_id=${resourceId(op.body['routine_entry_id'])}&limit=100&offset=0',
                op.generation,
              )
              as List;
      if (rows.any(
            (r) =>
                r is! Map<String, dynamic> ||
                !RoutineController.validRow(r, 'user_reported') ||
                r['routine_entry_id'] != op.body['routine_entry_id'],
          ) ||
          rows.map((r) => (r as Map)['id']).toSet().length != rows.length) {
        throw const FormatException('Invalid current report window');
      }
      final match = rows
          .whereType<Map<String, dynamic>>()
          .where((r) => r['id'] == record['id'])
          .firstOrNull;
      if (match != null && !RoutineController.sameWire(match, record) ||
          match == null && rows.length < 100) {
        throw const FormatException('Adherence current history unconfirmed');
      }
      guardAdherence(op);
      api.integrationIntents.remove(adherenceIntentId);
      return match ?? record;
    } catch (failure) {
      if (identical(adherencePending, op)) {
        if (!wasUncertain &&
            failure is IntegrationFailure &&
            failure.status == 422) {
          api.integrationIntents.remove(adherenceIntentId);
        } else {
          op.uncertain = true;
        }
      }
      rethrow;
    }
  }

  Future<bool> reconcileAdherence({
    bool retryOriginal = false,
    bool finishExpiredReview = false,
  }) async {
    final op = adherencePending;
    if (op == null) return true;
    guardAdherence(op);
    final value = await api.patientResource(
      '${op.attemptPath}/${op.key}',
      op.generation,
    );
    guardAdherence(op);
    final receipt = AdherenceReceipt.parse(value, op);
    op.lookupStatus = receipt.status;
    if (receipt.status == 'unknown') {
      op.uncertain = true;
      if (!retryOriginal) return false;
      await dispatchAdherence(op);
      return true;
    }
    if (receipt.original != null &&
        !RoutineController.validRow(receipt.original!, 'user_reported')) {
      throw const FormatException('Malformed original adherence evidence');
    }
    // Current history is independent of the original configuration in the receipt.
    final rows =
        await api.patientResource(
              'routine/adherence?routine_entry_id=${resourceId(op.body['routine_entry_id'])}&limit=100&offset=0',
              op.generation,
            )
            as List;
    if (rows.any(
      (r) =>
          r is! Map<String, dynamic> ||
          !RoutineController.validRow(r, 'user_reported'),
    )) {
      throw const FormatException('Invalid current adherence history');
    }
    // Lookup itself reads the immutable owned report. A current bounded history
    // page may omit an old report; never insert it or call absence a failure.
    final match = rows
        .whereType<Map<String, dynamic>>()
        .where((r) => r['id'] == receipt.resource)
        .firstOrNull;
    if (match != null &&
        receipt.original != null &&
        !RoutineController.sameWire(match, receipt.original)) {
      throw const FormatException('Immutable report changed');
    }
    guardAdherence(op);
    if (receipt.status == 'expired' && !finishExpiredReview) return false;
    api.integrationIntents.remove(adherenceIntentId);
    return true;
  }

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
    int? expectedRevision,
  }) async {
    if (!api.canReadPatientClinicalStatus || api.observationOwner == null) {
      throw RequestFailure.session();
    }
    if (!(resource == 'entries' && method == 'POST' ||
        RegExp(r'^entries/[A-Za-z0-9_-]+$').hasMatch(resource) &&
            method == 'PATCH' ||
        resource == 'adherence' && method == 'POST')) {
      throw ArgumentError('Unsupported routine write');
    }
    final generation = api.sessionGeneration;
    var patch = Map<String, dynamic>.of(payload);
    int? precondition;
    if (method == 'PATCH') {
      final current =
          await api.patientResource('routine/$resource', generation)
              as Map<String, dynamic>;
      if (!RoutineController.validRow(current, 'user_configured') ||
          current['id'] != resource.split('/').last) {
        throw const FormatException('Invalid routine snapshot');
      }
      if (expectedUpdatedAt == null ||
          current['updated_at'] != expectedUpdatedAt ||
          current['revision'] != expectedRevision) {
        throw RequestFailure.http(412);
      }
      // Linked experiment activation also supplies its reviewed routine revision.
      precondition = expectedRevision;
      patch.removeWhere((k, v) => current[k] == v);
      if (patch.isEmpty) return current;
    }
    if (resource != 'adherence') {
      if (pending != null) {
        throw const FormatException('Resolve original routine request first');
      }
      final op = ConfigurationPending(
        domain: 'routine',
        operation: method == 'POST' ? 'create' : 'update',
        owner: api.observationOwner!,
        generation: generation,
        path: 'routine/$resource',
        body: patch,
        method: method,
        resource: method == 'POST' ? null : resource.split('/').last,
        expectedRevision: precondition,
      );
      api.integrationIntents[intentId] = op;
      return dispatchConfiguration(op);
    }
    if (adherencePending != null) {
      throw const FormatException('Resolve original adherence request first');
    }
    final op = AdherencePending(
      owner: api.observationOwner!,
      generation: generation,
      body: patch,
    );
    api.integrationIntents[adherenceIntentId] = op;
    return dispatchAdherence(op);
  }
}

class RoutineController extends ChangeNotifier {
  RoutineController(this.repository, {this.onRecoveryConfirmed}) {
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

  ConfigurationPending? get configurationPending =>
      remote && ApiService.instance.canReadPatientClinicalStatus
      ? (repository as RemoteRoutineRepository).pending
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
    final ticket = _generation, original = configurationPending!;
    var expectedTicket = ticket;
    var receiptResolved = false;
    final sessionGeneration = ApiService.instance.sessionGeneration;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final resolved = await (repository as RemoteRoutineRepository)
          .reconcileConfiguration(
            retryOriginal: retryOriginal,
            finishUnavailableReview: finishUnavailableReview,
          );
      receiptResolved = resolved;
      if (_disposed || ticket != _generation) return false;
      if (resolved) {
        uncertain.remove(
          original.resource == null
              ? 'entries'
              : 'entries/${original.resource}',
        );
      }
      saving = false;
      expectedTicket = ticket + 1;
      await refresh();
      if (_disposed || _generation != expectedTicket) return false;
      if (resolved && !stale) {
        saving = true;
        notifyListeners();
        await onRecoveryConfirmed?.call(sessionGeneration);
      }
      if (_disposed ||
          _generation != expectedTicket ||
          !ApiService.instance.isCurrentSession(sessionGeneration)) {
        return false;
      }
      if (!stale) {
        error = resolved
            ? finishUnavailableReview
                  ? 'Receipt review complete. No original request was repeated.'
                  : 'Original routine request confirmed. Current routine refreshed.'
            : configurationPending?.lookupStatus == 'unknown'
            ? 'The original routine request remains uncertain. No committed receipt is available yet.'
            : 'The original receipt content is expired or erased. Review current records before finishing receipt review.';
      }
      notifyListeners();
      return resolved && !stale;
    } catch (failure) {
      if (_disposed || expectedTicket != _generation) return false;
      stale = true;
      error =
          '${receiptResolved ? 'Original routine request confirmed, but related information could not refresh.' : 'Routine request remains unconfirmed.'} ${failure is IntegrationFailure ? RequestFailure.http(failure.status).message : RequestFailure.from(failure).message}';
      return false;
    } finally {
      if (!_disposed && expectedTicket == _generation) {
        saving = false;
        notifyListeners();
      }
    }
  }

  AdherencePending? get adherencePending =>
      remote && ApiService.instance.canReadPatientClinicalStatus
      ? (repository as RemoteRoutineRepository).adherencePending
      : null;
  Future<bool> recoverAdherence({
    bool retryOriginal = false,
    bool finishExpiredReview = false,
  }) async {
    if (_disposed || saving || loading || !remote || adherencePending == null) {
      return false;
    }
    final ticket = _generation, original = adherencePending!;
    var expectedTicket = ticket;
    var receiptResolved = false;
    final sessionGeneration = ApiService.instance.sessionGeneration;
    saving = true;
    error = null;
    notifyListeners();
    try {
      final resolved = await (repository as RemoteRoutineRepository)
          .reconcileAdherence(
            retryOriginal: retryOriginal,
            finishExpiredReview: finishExpiredReview,
          );
      receiptResolved = resolved;
      if (_disposed || ticket != _generation) return false;
      if (resolved) uncertain.remove(writeKey('adherence', original.body));
      saving = false;
      expectedTicket = ticket + 1;
      await refresh();
      if (_disposed || _generation != expectedTicket) return false;
      if (resolved && !stale) {
        saving = true;
        notifyListeners();
        await onRecoveryConfirmed?.call(sessionGeneration);
      }
      if (_disposed ||
          _generation != expectedTicket ||
          !ApiService.instance.isCurrentSession(sessionGeneration)) {
        return false;
      }
      if (!stale) {
        error = resolved
            ? finishExpiredReview
                  ? 'Expired report receipt reviewed. No report was repeated.'
                  : 'Original adherence report confirmed. Current history refreshed.'
            : adherencePending?.lookupStatus == 'unknown'
            ? 'The original report remains uncertain. An occupied reporting slot is not proof of this request.'
            : 'The original receipt expired. Review current history; do not repeat this report.';
      }
      notifyListeners();
      return resolved && !stale;
    } catch (failure) {
      if (_disposed || expectedTicket != _generation) return false;
      stale = true;
      error =
          '${receiptResolved ? 'Original report confirmed, but related information could not refresh.' : 'Report remains unconfirmed.'} ${failure is IntegrationFailure ? RequestFailure.http(failure.status).message : RequestFailure.from(failure).message}';
      return false;
    } finally {
      if (!_disposed && expectedTicket == _generation) {
        saving = false;
        notifyListeners();
      }
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
  final Future<void> Function(int generation)? onRecoveryConfirmed;
  List<Map<String, dynamic>>? entries;
  List<Map<String, dynamic>>? history;
  bool loading = false;
  bool saving = false;
  String? error;
  RequestFailure? readFailure;
  DateTime? lastConfirmedAt;
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
          ? validRevision(row) &&
                row['product_id'] is String &&
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
  static bool validRevision(Map<String, dynamic> row) =>
      !row.containsKey('revision') && !row.containsKey('revision_protected') ||
      row['revision'] is int &&
          row['revision'] >= 1 &&
          row['revision'] <= 2147483647 &&
          row['revision_protected'] is bool;
  void discardUnauthorizedRead(RequestFailure failure) {
    if (failure.kind != RequestFailureKind.denied &&
        failure.kind != RequestFailureKind.session) {
      return;
    }
    entries = null;
    history = null;
    historyHasMore = false;
    lastConfirmedAt = null;
  }

  Future<void> refresh() async {
    if (_disposed || saving || loadingMore || loading) return;
    final generation = ++_generation;
    loading = true;
    stale = entries != null;
    readFailure = null;
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
      lastConfirmedAt = DateTime.now().toUtc();
      entries = configured;
      history = reported;
      if (remote) {
        if (configurationPending == null) {
          uncertain.removeWhere(
            (key) => key == 'entries' || key.startsWith('entries/'),
          );
        }
        if (adherencePending == null) {
          uncertain.removeWhere((key) => key.startsWith('adherence:'));
        }
      }
      historyHasMore = reported.length == 100;
      loadingMore = false;
      stale = false;
    } catch (failure) {
      if (generation != _generation || _disposed) return;
      stale = true;
      readFailure = RequestFailure.from(failure);
      discardUnauthorizedRead(readFailure!);
      error = 'Routine unavailable. ${readFailure!.message}';
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
    int? expectedRevision,
  }) async {
    if (saving ||
        loading ||
        (remote &&
            (entries == null ||
                stale ||
                uncertain.contains(writeKey(resource, payload)) ||
                resource.startsWith('entries') &&
                    configurationPending != null ||
                resource == 'adherence' && adherencePending != null))) {
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
              expectedRevision: expectedRevision,
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
        if (configurationPending != null) {
          uncertain.add(writeKey(resource, payload));
        }
        stale = true;
        notifyListeners();
      }
      return confirmed;
    } catch (failure) {
      if (generation != _generation || _disposed) return false;
      final problem = failure is IntegrationFailure
          ? RequestFailure.http(failure.status)
          : RequestFailure.from(failure);
      if (remote) {
        // Configuration writes retain their own exact pending operation. An
        // Adherence409 is not proof that the original report committed.
        if (adherencePending != null || configurationPending != null) {
          uncertain.add(writeKey(resource, payload));
        }
        stale = true;
      }
      error = 'Save unconfirmed. ${problem.message}';
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
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      stale = true;
      readFailure = RequestFailure.from(failure);
      discardUnauthorizedRead(readFailure!);
      error =
          'History unavailable. ${readFailure!.message} Refresh before recording.';
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
    readFailure = null;
    lastConfirmedAt = null;
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
