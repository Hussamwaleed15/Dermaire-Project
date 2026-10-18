import 'dart:async';
import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../notifications/inbox_models.dart';
import '../routine/routine_controller.dart';
import 'server_agent_models.dart';

class BrokerGrant {
  BrokerGrant(Map<String, dynamic> v, String owner)
    : id = resourceId(v['id']),
      doctor = resourceId(v['doctor_id']),
      expires = timestamp(v['expires_at']) {
    if (v['patient_id'] != owner ||
        v['granted_by'] != owner ||
        v['status'] != 'active' ||
        (v['scopes'] as List?)?.contains('VIEW') != true ||
        !expires.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Inactive original VIEW grant');
    }
  }
  final String id, doctor;
  final DateTime expires;
}

class ServerAgentController extends PrivateController {
  BrokerCapabilities? capabilities;
  BrokerSession? _session;
  final _seenSessions = <String, int>{}, _seenActions = <String, int>{};
  final _seenCalls = <String, int>{};
  final _turns = <BrokerTurn>[], _actions = <BrokerAction>[];
  final _grants = <BrokerGrant>[];
  final _routines = <Map<String, dynamic>>[];
  final _notices = <InboxNotice>[];
  Timer? _clock;
  String? outcome;
  @override
  bool get current => super.current && role == 'patient';
  BrokerSession? get session =>
      current && _session?.active == true ? _session : null;
  List<BrokerTurn> get turns =>
      session == null ? [] : List.unmodifiable(_turns);
  List<BrokerAction> get actions =>
      session == null ? [] : List.unmodifiable(_actions);
  List<BrokerGrant> get grants => session == null
      ? []
      : List.unmodifiable(
          _grants.where((g) => g.expires.isAfter(DateTime.now().toUtc())),
        );
  List<Map<String, dynamic>> get routines =>
      session == null ? [] : List.unmodifiable(_routines);
  List<InboxNotice> get notices =>
      session == null ? [] : List.unmodifiable(_notices);
  String? get selected =>
      authenticatedCurrent ? api.integrationReferences['agent-active'] : null;
  List<String> get knownSessions => authenticatedCurrent
      ? api.integrationReferences.entries
            .where((e) => e.key.startsWith('agent-session:'))
            .map((e) => e.value)
            .toList()
      : [];
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents['agent:operation'] : null;
  @override
  void wipe() {
    _clock?.cancel();
    _session = null;
    capabilities = null;
    _turns.clear();
    _actions.clear();
    _grants.clear();
    _routines.clear();
    _notices.clear();
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final v = BrokerCapabilities(
        object(
          (await api.integrationResource(
            'agent/capabilities',
            generation,
          )).data,
        ),
      );
      if (!valid(ticket)) return;
      capabilities = v;
      final id = selected;
      if (id != null) await pull(id, ticket);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> select(String id) async {
    if (!current || busy || pending != null || !knownSessions.contains(id)) {
      return;
    }
    api.integrationReferences['agent-active'] = id;
    await refresh();
  }

  Future<void> pull(String id, int ticket) async {
    final s = BrokerSession(
      object(
        (await api.integrationResource(
          'agent/sessions/${resourceId(id)}',
          generation,
        )).data,
      ),
    );
    if (s.id != id || !s.active) {
      throw const FormatException('Agent session expired');
    }
    final t = object(
      (await api.integrationResource(
        'agent/sessions/$id/turns',
        generation,
      )).data,
    );
    if (t['model_status'] != 'unavailable' ||
        (t['generated_assistant_turns'] as List).isNotEmpty ||
        (t['items'] as List).length > 40) {
      throw const FormatException('Unsupported generated conversation');
    }
    final turns = (t['items'] as List)
        .map((e) => BrokerTurn(object(e)))
        .toList();
    final actions = s.scopes.contains('proposal_actions')
        ? (object(
                    (await api.integrationResource(
                      'agent/sessions/$id/actions',
                      generation,
                    )).data,
                  )['items']
                  as List)
              .map((e) => BrokerAction(object(e)))
              .toList()
        : <BrokerAction>[];
    if (actions.length > 8 ||
        turns.map((t) => t.id).toSet().length != turns.length ||
        actions.map((a) => a.id).toSet().length != actions.length) {
      throw const FormatException('Invalid Agent budget');
    }
    if (!valid(ticket) || !s.active) return;
    if (s.revision < (_seenSessions[id] ?? 0) ||
        s.toolCalls < (_seenCalls[id] ?? 0) ||
        actions.any((a) => a.revision < (_seenActions[a.id] ?? 0))) {
      throw const FormatException('Stale Agent server state');
    }
    _seenSessions[id] = s.revision;
    _seenCalls[id] = s.toolCalls;
    for (final a in actions) {
      _seenActions[a.id] = a.revision;
    }
    _session = s;
    _turns
      ..clear()
      ..addAll(turns);
    _actions
      ..clear()
      ..addAll(actions);
    arm(s);
  }

  void arm(BrokerSession s) {
    _clock?.cancel();
    final now = DateTime.now().toUtc();
    final times = [
      s.expires,
      s.contextAt.add(const Duration(minutes: 5)),
      ..._actions.where((a) => a.state == 'preview').map((a) => a.validUntil),
    ].where((t) => t.isAfter(now)).toList()..sort();
    final next = times.isEmpty ? s.expires : times.first;
    _clock = Timer(next.difference(now), () {
      if (!current || _session?.id != s.id) return;
      if (!s.active) {
        revision++;
        wipe();
        error =
            'Agent consent session expired. Its prior context and requests cannot be reused.';
        busy = false;
      } else {
        arm(s);
      }
      notifyListeners();
    });
  }

  Future<void> loadChoices() async {
    if (session == null || busy) return;
    final ticket = begin();
    _grants.clear();
    _routines.clear();
    _notices.clear();
    try {
      final g =
          (await api.integrationResource('doctor/access', generation)).data
              as List;
      final grants = <BrokerGrant>[];
      for (final row in g) {
        final v = object(row);
        if (v['patient_id'] != owner || v['granted_by'] != owner) {
          throw const FormatException('Foreign grant');
        }
        if (v['status'] == 'active' &&
            v['doctor_id'] != null &&
            (v['scopes'] as List?)?.contains('VIEW') == true &&
            timestamp(v['expires_at']).isAfter(DateTime.now().toUtc())) {
          grants.add(BrokerGrant(v, owner));
        }
      }
      final rows =
          (await api.patientResource('routine/entries', generation) as List)
              .map((r) => object(r))
              .toList();
      if (rows.any((r) => !RoutineController.validRow(r, 'user_configured'))) {
        throw const FormatException('Unverified routine choice');
      }
      final inbox = object(
        (await api.integrationResource(
          'notifications',
          generation,
          query: {'limit': '50'},
        )).data,
      );
      final notices = (inbox['items'] as List)
          .map((n) => InboxNotice(object(n)))
          .where((n) => n.read == null)
          .toList();
      if (!valid(ticket) || session == null) return;
      _grants.addAll(grants);
      _routines.addAll(
        rows
            .where(
              (r) =>
                  r['active'] == true &&
                  r['revision'] is int &&
                  (r['revision'] as int) > 0,
            )
            .map(Map<String, dynamic>.unmodifiable),
      );
      _notices.addAll(notices);
    } catch (e) {
      if (valid(ticket)) {
        _grants.clear();
        _routines.clear();
        _notices.clear();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> start({
    required bool readConsent,
    required bool actionConsent,
  }) async {
    if (!current ||
        busy ||
        capabilities == null ||
        pending != null ||
        !readConsent) {
      return false;
    }
    return newIntent('agent/sessions', {
      'longitudinal_read_consent': true,
      'proposal_actions_consent': actionConsent,
    });
  }

  Future<bool> turn(String message) async {
    final s = session;
    if (s == null ||
        message.trim().isEmpty ||
        message.length > 1000 ||
        _turns.length >= 40) {
      return false;
    }
    return newIntent('agent/sessions/${s.id}/turns', {
      'message': message.trim(),
    });
  }

  Future<bool> refreshContext() async {
    final s = session;
    if (s == null || s.toolCalls >= 8) return false;
    return newIntent('agent/sessions/${s.id}/context', {
      'expected_revision': s.revision,
    });
  }

  Future<bool> preview(
    String kind,
    String rationale, {
    String? routine,
    String? notice,
  }) async {
    final s = session;
    if (s == null ||
        !s.fresh ||
        !s.scopes.contains('proposal_actions') ||
        s.toolCalls >= 8 ||
        !brokerKinds.contains(kind) ||
        rationale.trim().length < 3 ||
        rationale.length > 500) {
      return false;
    }
    final selectedRoutine = _routines
        .where((r) => r['id'] == routine)
        .firstOrNull;
    if (kind == 'propose_routine_adjustment' && selectedRoutine == null ||
        kind == 'mark_notification_read' &&
            !_notices.any((n) => n.id == notice)) {
      return false;
    }
    return newIntent(
      'agent/sessions/${s.id}/actions/preview',
      {
        'expected_session_revision': s.revision,
        'kind': kind,
        'rationale': rationale.trim(),
        if (kind == 'propose_routine_adjustment') ...{
          'routine_id': routine,
          'routine_revision': selectedRoutine!['revision'],
        },
        if (kind == 'mark_notification_read') 'notification_id': notice,
      },
      attemptPath: 'agent/sessions/${s.id}/action-attempts',
    );
  }

  Future<bool> confirm(BrokerAction action) async {
    final s = session;
    if (s == null ||
        !action.fresh ||
        action.state != 'preview' ||
        !_actions.any(
          (a) => a.id == action.id && a.revision == action.revision,
        )) {
      return false;
    }
    return newIntent('agent/sessions/${s.id}/actions/${action.id}/confirm', {
      'expected_revision': action.revision,
      'confirm': true,
    });
  }

  Future<bool> submit(BrokerAction action, BrokerGrant grant) async {
    if (session == null ||
        action.state != 'confirmed' ||
        action.revision != 2 ||
        ![
          'propose_followup',
          'propose_routine_adjustment',
        ].contains(action.kind) ||
        !_actions.any((a) => a.id == action.id) ||
        !grants.any((g) => g.id == grant.id)) {
      return false;
    }
    return newIntent('agent/requests/${action.id}/submit', {
      'expected_revision': action.revision,
      'access_id': grant.id,
      'clinician_request_consent': true,
    });
  }

  Future<bool> newIntent(
    String path,
    Map<String, dynamic> body, {
    String attemptPath = '',
  }) async {
    if (!current || busy || pending != null) return false;
    final intent = PendingIntent(
      path: path,
      attemptPath: attemptPath,
      body: body,
    );
    api.integrationIntents['agent:operation'] = intent;
    return perform(intent);
  }

  Future<bool> retryOriginal() async {
    final p = pending;
    if (p == null || !current || busy) return false;
    return perform(p);
  }

  Future<bool> perform(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin(), uncertain = intent.uncertain;
    bool acknowledged = false;
    try {
      intent.uncertain = true;
      final keyed =
          intent.path == 'agent/sessions' ||
          intent.path.endsWith('/turns') ||
          intent.path.endsWith('/preview');
      final data = object(
        (await api.integrationResource(
          intent.path,
          generation,
          method: 'POST',
          body: intent.body,
          key: keyed ? intent.key : null,
        )).data,
      );
      acknowledged = true;
      if (!valid(ticket)) return false;
      String id;
      if (intent.path == 'agent/sessions') {
        final receipt = BrokerSession(data);
        if (receipt.scopes.contains('proposal_actions') !=
            intent.body['proposal_actions_consent']) {
          throw const FormatException('Different consent receipt');
        }
        id = receipt.id;
        api.integrationReferences['agent-active'] = id;
        api.integrationReferences['agent-session:$id'] = id;
      } else {
        id = selected ?? '';
      }
      if (id.isEmpty) throw const FormatException('Agent session unavailable');
      await pull(id, ticket);
      if (!valid(ticket) || session == null) return false;
      verifyReceipt(intent, data);
      api.integrationIntents.remove('agent:operation');
      outcome =
          'Server state confirmed. Requests and clinician decisions do not execute medical changes.';
      return true;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error =
            'Agent operation is unconfirmed. Reconcile or retry the original intent before a replacement. ${integrationError(e)}';
        if (!uncertain &&
            !acknowledged &&
            e is IntegrationFailure &&
            [403, 404, 409, 410, 422].contains(e.status)) {
          api.integrationIntents.remove('agent:operation');
        }
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  void verifyReceipt(PendingIntent intent, Map<String, dynamic> receipt) {
    if (intent.path == 'agent/sessions' || intent.path.endsWith('/context')) {
      final original = BrokerSession(receipt);
      if (session!.id != original.id ||
          session!.expires != original.expires ||
          session!.scopes.length != original.scopes.length ||
          session!.scopes
              .toSet()
              .difference(original.scopes.toSet())
              .isNotEmpty ||
          (intent.path.endsWith('/context') &&
              original.revision !=
                  (intent.body['expected_revision'] as int) + 1) ||
          session!.revision < original.revision) {
        throw const FormatException('Stale context readback');
      }
      return;
    }
    if (intent.path.endsWith('/turns')) {
      unavailableModel(receipt['model']);
      final row = _turns.where((t) => t.id == receipt['id']).firstOrNull;
      if (receipt['actions_executed'] != 0 ||
          row == null ||
          row.message != intent.body['message']) {
        throw const FormatException('Unconfirmed saved turn');
      }
      return;
    }
    final original = BrokerAction(receipt),
        latest = _actions.where((a) => a.id == original.id).firstOrNull;
    if (latest == null ||
        latest.revision < original.revision ||
        latest.kind != original.kind) {
      throw const FormatException('Unconfirmed action readback');
    }
    if (intent.path.endsWith('/preview')) {
      if (original.kind != intent.body['kind'] ||
          original.payload['rationale'] != intent.body['rationale'] ||
          original.payload['routine_id'] != intent.body['routine_id'] ||
          original.payload['routine_revision'] !=
              intent.body['routine_revision'] ||
          original.payload['notification_id'] !=
              intent.body['notification_id']) {
        throw const FormatException('Preview intent mismatch');
      }
    } else if (intent.path.endsWith('/confirm')) {
      if (!intent.path.contains('/${original.id}/') ||
          original.state != 'confirmed') {
        throw const FormatException('Unconfirmed request');
      }
    } else if (intent.path.endsWith('/submit')) {
      if (!intent.path.contains('/${original.id}/') ||
          original.result?['access_id'] != intent.body['access_id'] ||
          latest.result?['access_id'] != intent.body['access_id']) {
        throw const FormatException('Different routing grant');
      }
    }
  }

  Future<void> reconcileCurrent() async {
    final intent = pending, id = selected;
    if (intent == null ||
        id == null ||
        !current ||
        busy ||
        intent.path == 'agent/sessions') {
      return;
    }
    if (intent.path.endsWith('/preview')) {
      await reconcilePreview();
      return;
    }
    final ticket = begin();
    try {
      await pull(id, ticket);
      if (!valid(ticket) || session == null) return;
      bool resolved = false;
      if (intent.path.endsWith('/context')) {
        resolved =
            session!.revision > (intent.body['expected_revision'] as int);
      } else if (intent.path.endsWith('/confirm') ||
          intent.path.endsWith('/submit')) {
        final actionId = intent.path.split('/').reversed.skip(1).first;
        final a = _actions.where((a) => a.id == actionId).firstOrNull;
        resolved =
            a?.state == 'confirmed' &&
            (intent.path.endsWith('/confirm')
                ? a!.revision >= 2
                : a!.result?['access_id'] == intent.body['access_id']);
      }
      if (resolved) {
        api.integrationIntents.remove('agent:operation');
        outcome =
            'Current server state reconciled. A newer context/request is not proof that a medical action executed.';
      } else {
        error =
            'The original operation is still unconfirmed. Retry only its exact original intent.';
      }
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> reconcilePreview() async {
    final intent = pending;
    if (intent == null || !current || busy || intent.attemptPath.isEmpty) {
      return;
    }
    final ticket = begin();
    try {
      final attempt = object(
        (await api.integrationResource(
          '${intent.attemptPath}/${intent.key}',
          generation,
        )).data,
      );
      if (!valid(ticket)) return;
      if (attempt['status'] == 'unknown') {
        error =
            'Unknown does not prove failure. Only the exact original preview may be retried.';
        return;
      }
      if (attempt['status'] != 'committed') {
        throw const FormatException('Invalid preview attempt');
      }
      final action = BrokerAction(object(attempt['result']));
      if (attempt['attempt_id'] != action.id) {
        throw const FormatException('Attempt mismatch');
      }
      final id = selected;
      if (id == null) throw const FormatException('Agent session unavailable');
      await pull(id, ticket);
      if (!valid(ticket)) return;
      verifyReceipt(intent, object(attempt['result']));
      api.integrationIntents.remove('agent:operation');
      outcome =
          'Original preview reconciled. Confirmation is still a separate explicit action.';
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> revoke({String? action}) async {
    final id = action ?? selected;
    if (!authenticatedCurrent || !visible || busy || id == null) return;
    final ticket = begin();
    try {
      final receipt = object(
        (await api.integrationResource(
          action == null
              ? 'agent/sessions/${resourceId(id)}'
              : 'agent/requests/${resourceId(id)}',
          generation,
          method: 'DELETE',
          withdrawal: true,
        )).data,
      );
      if (!authenticatedCurrent || !visible || revision != ticket) return;
      if (receipt['id'] != id ||
          receipt['state'] != 'revoked' ||
          receipt['memory_erased'] != true) {
        throw const FormatException('Withdrawal not confirmed');
      }
      if (action == null) {
        api.integrationReferences.remove('agent-session:$id');
        if (selected == id) api.integrationReferences.remove('agent-active');
      }
      final original = pending;
      if (original != null &&
          (original.path.contains('/$id/') ||
              original.path == 'agent/sessions/$id')) {
        api.integrationIntents.remove('agent:operation');
      }
      wipe();
      outcome =
          'Server withdrawal confirmed; relevant request/session memory erased. Any unrelated unresolved operation retains its original identity.';
      if (action != null && current && selected != null) {
        await pull(selected!, ticket);
      }
    } catch (e) {
      if (authenticatedCurrent && visible && revision == ticket) {
        wipe();
        error =
            'Withdrawal is unconfirmed. Retry the same withdrawal. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }
}

class ClinicianRequestsController extends PrivateController {
  Timer? _clock;
  final _requests = <BrokerAction>[];
  final _seen = <String, int>{};
  String? outcome;
  @override
  bool get current => super.current && role == 'doctor';
  List<BrokerAction> get requests =>
      current ? List.unmodifiable(_requests) : [];
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents['agent:decision'] : null;
  @override
  void wipe() {
    _clock?.cancel();
    _requests.clear();
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      await pull(ticket);
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> pull(int ticket) async {
    final data = object(
      (await api.integrationResource('agent/requests', generation)).data,
    );
    if (data['limit'] != 100 ||
        data['medical_execution_enabled'] != false ||
        data['notification_delivery'] != 'unavailable' ||
        (data['items'] as List).length > 100) {
      throw const FormatException('Invalid clinician request inbox');
    }
    final rows = (data['items'] as List)
        .map((v) => BrokerAction(object(v), doctor: owner))
        .toList();
    if (rows.map((a) => a.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate requests');
    }
    if (!valid(ticket)) return;
    if (rows.any((a) => a.revision < (_seen[a.id] ?? 0))) {
      throw const FormatException('Stale clinician request state');
    }
    for (final a in rows) {
      _seen[a.id] = a.revision;
    }
    _requests
      ..clear()
      ..addAll(rows);
    _clock?.cancel();
    if (rows.isNotEmpty) {
      final dates = rows.map((r) => timestamp(r.result!['expires_at'])).toList()
        ..sort();
      _clock = Timer(dates.first.difference(DateTime.now().toUtc()), () {
        if (!current) return;
        revision++;
        wipe();
        busy = false;
        error = 'Request authority expired. Refresh the authorized inbox.';
        notifyListeners();
      });
    }
  }

  Future<bool> decide(BrokerAction action, String decision) async {
    if (!current ||
        busy ||
        pending != null ||
        !requests.any(
          (a) => a.id == action.id && a.revision == action.revision,
        ) ||
        !(action.result?['status'] == 'pending_clinician_review'
                ? ['accepted', 'rejected']
                : action.result?['status'] == 'accepted'
                ? ['reviewed']
                : <String>[])
            .contains(decision)) {
      return false;
    }
    final intent = PendingIntent(
      path: 'agent/requests/${action.id}/decision',
      attemptPath: 'agent/requests',
      body: {'expected_revision': action.revision, 'decision': decision},
    );
    api.integrationIntents['agent:decision'] = intent;
    return deliver(intent);
  }

  Future<bool> retryOriginal() async {
    final intent = pending;
    if (intent == null || busy || !current) return false;
    return deliver(intent);
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin();
    try {
      intent.uncertain = true;
      final original = BrokerAction(
        object(
          (await api.integrationResource(
            intent.path,
            generation,
            method: 'POST',
            body: intent.body,
          )).data,
        ),
        doctor: owner,
      );
      if (!valid(ticket)) return false;
      await pull(ticket);
      if (!valid(ticket)) return false;
      final latest = _requests.where((a) => a.id == original.id).firstOrNull;
      if (!intent.path.contains('/${original.id}/') ||
          original.result?['decision'] != intent.body['decision'] ||
          original.result?['decision_base_revision'] !=
              intent.body['expected_revision'] ||
          latest == null ||
          latest.revision < original.revision) {
        throw const FormatException('Unverified clinician decision');
      }
      api.integrationIntents.remove('agent:decision');
      outcome =
          'Clinician request decision recorded. No medical resource was modified.';
      return true;
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error =
            'Decision unconfirmed. Retry only the original request/revision/decision. ${integrationError(e)}';
      }
      return false;
    } finally {
      finish(ticket);
    }
  }
}
