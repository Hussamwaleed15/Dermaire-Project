import 'plan_evaluation.dart';
import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../doctor/doctor_connection.dart';
import 'plan_models.dart';

class PlansController extends PrivateController {
  PlansController({this.patient});
  final String? patient;
  final _plans = <ClinicalPlan>[];
  String? next;
  List<ClinicalPlan> get plans => current ? List.unmodifiable(_plans) : [];
  @override
  void wipe() {
    _plans.clear();
    next = null;
  }

  @override
  Future<void> refresh() async => load();
  Future<void> load({bool more = false}) async {
    if (!current || busy || more && next == null) return;
    final after = more ? next : null, ticket = begin();
    if (!more) wipe();
    try {
      final body = object(
        (await api.integrationResource(
          'clinical-plans',
          generation,
          query: {'limit': '50', 'after': ?after},
        )).data,
      );
      final rows = (body['items'] as List)
          .map((v) => ClinicalPlan.fromApi(object(v), owner, role))
          .toList();
      final cursor = body['next_after'] == null
          ? null
          : resourceId(body['next_after']);
      if (!valid(ticket)) return;
      final ids = _plans.map((p) => p.id).toSet();
      if (rows.any((p) => !ids.add(p.id)) ||
          cursor != null && cursor == after) {
        throw const FormatException('Changed plan pages');
      }
      _plans.addAll(rows.where((p) => patient == null || p.patient == patient));
      next = cursor;
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }
}

class PlanController extends PrivateController {
  PlanController(this.id);
  final String id;
  ClinicalPlan? _value;
  int _seenRevision = 0;
  String? _patient, _doctor, _grant;
  final _history = <PlanEvent>[];
  int? nextHistory;
  String? outcome;
  PlanEvaluation? _evaluation;
  PlanEvaluation? get evaluation => current ? _evaluation : null;
  ClinicalPlan? get value => current ? _value : null;
  List<PlanEvent> get history => current ? List.unmodifiable(_history) : [];
  String get intentId => 'plan:$id';
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents[intentId] : null;
  @override
  void wipe() {
    _value = null;
    _evaluation = null;
    _history.clear();
    nextHistory = null;
    outcome = null;
  }

  void invalidateEvidence() {
    if (disposed) return;
    revision++;
    wipe();
    busy = false;
    error =
        'Plan or private image authority changed. Refresh current plan before viewing evidence.';
    notifyListeners();
  }

  Future<ClinicalPlan> read() async => ClinicalPlan.fromApi(
    object(
      (await api.integrationResource(
        'clinical-plans/${resourceId(id)}',
        generation,
      )).data,
    ),
    owner,
    role,
  );
  void apply(ClinicalPlan row) {
    if (row.id != id ||
        row.revision < _seenRevision ||
        (_patient != null &&
            (row.patient != _patient ||
                row.doctor != _doctor ||
                row.grant != _grant))) {
      throw const FormatException('Stale plan');
    }
    _value = row;
    _seenRevision = row.revision;
    _patient = row.patient;
    _doctor = row.doctor;
    _grant = row.grant;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final row = await read();
      if (!valid(ticket)) return;
      apply(row);
      await readHistory(ticket, 0);
      if (valid(ticket)) await readEvaluation(ticket);
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> readHistory(int ticket, int after) async {
    final plan = value;
    if (plan == null) return;
    final data = object(
      (await api.integrationResource(
        'clinical-plans/$id/history',
        generation,
        query: {'after_revision': '$after', 'limit': '50'},
      )).data,
    );
    final events = (data['items'] as List)
        .map((v) => PlanEvent.fromApi(object(v), plan, owner, role))
        .toList();
    if (!valid(ticket)) return;
    if (data['numeric_comparison_metrics'] != null ||
        events.any((e) => e.revision <= after) ||
        events.map((e) => e.revision).toSet().length != events.length) {
      throw const FormatException('Invalid plan history');
    }
    for (int i = 1; i < events.length; i++) {
      if (events[i - 1].revision >= events[i].revision) {
        throw const FormatException('Unordered history');
      }
    }
    final next = data['next_after_revision'] as int?;
    if (next != null && (events.isEmpty || next != events.last.revision)) {
      throw const FormatException('Invalid history cursor');
    }
    if (events.any((e) => e.revision > (_value?.revision ?? 0))) {
      final latest = await read();
      if (!valid(ticket)) return;
      apply(latest);
      if (events.any((e) => e.revision > latest.revision)) {
        throw const FormatException('Current plan read is behind history');
      }
    }
    _history.addAll(events);
    nextHistory = next;
  }

  Future<void> readEvaluation(int ticket) async {
    final plan = value;
    if (plan == null || plan.kind != 'comparison') return;
    final job = PlanEvaluation(
      object(
        (await api.integrationResource(
          'clinical-plans/$id/evaluation',
          generation,
        )).data,
      ),
      plan,
    );
    if (!valid(ticket)) return;
    if (job.state != 'not_requested' &&
        (job.wire['plan_revision'] as int) > plan.revision) {
      final latest = await read();
      if (!valid(ticket)) return;
      apply(latest);
      if ((job.wire['plan_revision'] as int) > latest.revision) {
        throw const FormatException('Plan read is behind evaluation');
      }
    }
    _evaluation = job;
  }

  Future<void> moreHistory() async {
    if (!current || busy || nextHistory == null || _history.length >= 500) {
      return;
    }
    final ticket = begin();
    try {
      await readHistory(ticket, nextHistory!);
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> mutate(
    String operation,
    Map<String, dynamic> fields,
    int expected,
  ) async {
    final plan = value;
    if (!current ||
        busy ||
        plan == null ||
        pending != null ||
        plan.revision != expected) {
      return false;
    }
    final allowed = <String, Set<String>>{
      'acknowledge': {'consent'},
      'cancel': {'reason'},
      'reschedule': {'local_due', 'timezone', 'fold'},
      'review': {'assessment'},
      'capture': {'capture_id'},
      'evaluation': {'image_processing_consent'},
      'evaluation/review': {'job_id', 'decision', 'assessment'},
    };
    if (!allowed.containsKey(operation) ||
        fields.keys.any((k) => !allowed[operation]!.contains(k))) {
      return false;
    }
    if (['acknowledge', 'capture', 'evaluation'].contains(operation) &&
            role != 'patient' ||
        ['review', 'reschedule', 'evaluation/review'].contains(operation) &&
            role != 'doctor') {
      return false;
    }
    if (operation == 'reschedule' &&
        validateWallSchedule(
              fields['local_due'] as String,
              fields['timezone'] as String,
              fields['fold'] as int?,
            ) !=
            null) {
      return false;
    }
    if (operation == 'evaluation' &&
        (plan.kind != 'comparison' ||
            plan.state != 'captured' ||
            fields['image_processing_consent'] != true)) {
      return false;
    }
    if (operation == 'evaluation/review' &&
        (evaluation?.currentState != 'pending_human_review' ||
            fields['job_id'] != evaluation?.wire['id'] ||
            !['reviewed', 'rejected'].contains(fields['decision']))) {
      return false;
    }
    final intent = PendingIntent(
      path: 'clinical-plans/$id/$operation',
      attemptPath:
          'clinical-plans/$id/attempts/${operation == 'evaluation'
              ? 'evaluate'
              : operation == 'evaluation/review'
              ? 'evaluation_review'
              : operation}',
      body: {'expected_revision': expected, ...fields},
    );
    api.integrationIntents[intentId] = intent;
    return deliver(intent);
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin(), wasUncertain = intent.uncertain;
    bool sent = false, acknowledged = false;
    try {
      final latest = await read();
      if (!valid(ticket)) return false;
      final expected = intent.body['expected_revision'];
      if (latest.revision != expected) {
        apply(latest);
        error =
            'The plan changed. Reconcile the original attempt and review current history before another action.';
        if (!wasUncertain) api.integrationIntents.remove(intentId);
        return false;
      }
      sent = true;
      intent.uncertain = true;
      final data = object(
        (await api.integrationResource(
          intent.path,
          generation,
          method: 'POST',
          body: intent.body,
          key: intent.key,
        )).data,
      );
      acknowledged = true;
      if (!valid(ticket)) return false;
      if (intent.path.contains('/evaluation')) {
        return await confirmEvaluation(data, intent, ticket);
      }
      return await confirm(
        ClinicalPlan.fromApi(data, owner, role),
        intent,
        ticket,
      );
    } catch (failure) {
      if (!authenticatedCurrent) return false;
      if (!wasUncertain &&
          !acknowledged &&
          failure is IntegrationFailure &&
          [403, 404, 409, 410, 422].contains(failure.status)) {
        api.integrationIntents.remove(intentId);
      }
      if (valid(ticket)) {
        wipe();
        error = sent
            ? 'The plan change is unconfirmed. Reconcile the original key before retrying. ${integrationError(failure)}'
            : integrationError(failure);
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  Future<bool> confirm(
    ClinicalPlan receipt,
    PendingIntent intent,
    int ticket,
  ) async {
    if (receipt.id != id ||
        receipt.revision != (intent.body['expected_revision'] as int) + 1) {
      throw const FormatException('Unverified plan receipt');
    }
    final operation = intent.path.split('/').last;
    final expectedState = {
      'acknowledge': 'scheduled',
      'cancel': 'cancelled',
      'reschedule': 'proposed',
      'review': 'reviewed',
      'capture': 'captured',
    }[operation];
    if (receipt.state != expectedState ||
        operation == 'capture' &&
            receipt.followup != intent.body['capture_id']) {
      throw const FormatException('Unverified plan result');
    }
    if (operation == 'reschedule' &&
        (receipt.timezone != intent.body['timezone'] ||
            DateTime.parse(receipt.localWallTime) !=
                DateTime.parse(intent.body['local_due'] as String))) {
      throw const FormatException('Schedule not confirmed');
    }
    final latest = await read();
    if (!valid(ticket)) return false;
    if (latest.revision < receipt.revision ||
        latest.grant != receipt.grant ||
        latest.patient != receipt.patient ||
        latest.doctor != receipt.doctor) {
      throw const FormatException('Changed plan identity');
    }
    apply(latest);
    _history.clear();
    await readHistory(ticket, 0);
    if (valid(ticket)) await readEvaluation(ticket);
    if (!valid(ticket)) return false;
    api.integrationIntents.remove(intentId);
    outcome =
        'Change confirmed at revision ${receipt.revision}. Current plan revision ${latest.revision}; no notification delivery is implied.';
    return true;
  }

  Future<bool> confirmEvaluation(
    Map<String, dynamic> data,
    PendingIntent intent,
    int ticket,
  ) async {
    final plan = await read();
    if (!valid(ticket)) return false;
    final receipt = PlanEvaluation(data, plan),
        expected = intent.body['expected_revision'] as int;
    final isReview = intent.path.endsWith('/review');
    if (receipt.wire['plan_revision'] != expected + 1 ||
        plan.revision < expected + 1 ||
        (!isReview && receipt.state != 'queued') ||
        (isReview &&
            (receipt.state != intent.body['decision'] ||
                receipt.wire['id'] != intent.body['job_id'] ||
                object(receipt.wire['human_review'])['assessment'] !=
                    intent.body['assessment']))) {
      throw const FormatException('Unverified evaluation receipt');
    }
    apply(plan);
    await readEvaluation(ticket);
    if (!valid(ticket)) return false;
    _history.clear();
    await readHistory(ticket, 0);
    if (!valid(ticket)) return false;
    api.integrationIntents.remove(intentId);
    outcome = isReview
        ? 'Clinician inference review recorded. This does not certify clinical accuracy or clearance.'
        : 'Evaluation request recorded. Current evaluation state: ${evaluation?.currentState}. This is not a completed clinical analysis.';
    return true;
  }

  Future<void> cancelEvaluation() async {
    final plan = value;
    if (!current ||
        busy ||
        pending != null ||
        plan == null ||
        plan.kind != 'comparison' ||
        evaluation == null ||
        evaluation!.state == 'not_requested') {
      return;
    }
    final ticket = begin();
    try {
      final before = await read();
      if (!valid(ticket)) return;
      if (before.revision != plan.revision) throw IntegrationFailure(409);
      final data = object(
        (await api.integrationResource(
          'clinical-plans/$id/evaluation',
          generation,
          method: 'DELETE',
          query: {'expected_revision': '${plan.revision}'},
          withdrawal: true,
        )).data,
      );
      final receipt = PlanEvaluation(data, plan);
      if (receipt.state != 'cancelled') {
        throw const FormatException('Unverified evaluation cancellation');
      }
      final latest = await read();
      if (!valid(ticket)) return;
      apply(latest);
      await readEvaluation(ticket);
      if (!valid(ticket)) return;
      _history.clear();
      await readHistory(ticket, 0);
      if (valid(ticket)) {
        outcome =
            'Evaluation cancellation acknowledged. Current state: ${evaluation?.currentState}.';
      }
    } catch (e) {
      if (valid(ticket)) {
        wipe();
        error =
            'Cancellation is unconfirmed. Refresh current evaluation before another request. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> reconcile({bool retryOriginal = false}) async {
    final intent = pending;
    if (intent == null || !current || busy) return false;
    final ticket = begin();
    try {
      final data = object(
        (await api.integrationResource(
          '${intent.attemptPath}/${intent.key}',
          generation,
        )).data,
      );
      if (!valid(ticket)) return false;
      if (data['status'] == 'committed') {
        if (intent.path.contains('/evaluation')) {
          return await confirmEvaluation(
            object(data['result']),
            intent,
            ticket,
          );
        }
        return await confirm(
          ClinicalPlan.fromApi(object(data['result']), owner, role),
          intent,
          ticket,
        );
      }
      if (!['unknown', 'expired'].contains(data['status'])) {
        throw const FormatException('Unverified plan attempt');
      }
      if (data['status'] == 'unknown' && retryOriginal) {
        busy = false;
        return deliver(intent);
      }
      error = data['status'] == 'expired'
          ? 'The receipt expired. Review current plan/history; no automatic replacement action.'
          : 'The result is unknown. Only the original body, key and revision may be retried explicitly.';
      return false;
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
      return false;
    } finally {
      finish(ticket);
    }
  }
}

class CreatePlanController extends PrivateController {
  CreatePlanController(this.connection) : originalGrant = connection.grant?.id {
    connection.addListener(connectionChanged);
  }
  final DoctorConnectionController connection;
  final String? originalGrant;
  ClinicalPlan? created;
  @override
  bool get current =>
      super.current &&
      role == 'doctor' &&
      connection.confirmed &&
      connection.parent.generation == generation &&
      originalGrant != null &&
      connection.grant?.id == originalGrant;
  String get intentId =>
      'plan-create:${connection.patientId}:${originalGrant ?? 'unverified'}';
  PendingIntent? get pending =>
      current ? api.integrationIntents[intentId] : null;
  void connectionChanged() {
    if (!current) {
      revision++;
      wipe();
      busy = false;
      notifyListeners();
    }
  }

  @override
  void wipe() {
    created = null;
  }

  @override
  Future<void> refresh() async {
    if (!current) return;
    error = null;
    notifyListeners();
  }

  Future<bool> create(Map<String, dynamic> fields) async {
    if (!current ||
        busy ||
        pending != null ||
        fields.keys.any(
          (k) => !{
            'kind',
            'purpose',
            'local_due',
            'timezone',
            'fold',
            'source_type',
            'source_id',
            'baseline_capture_id',
          }.contains(k),
        ) ||
        !['follow_up', 'comparison'].contains(fields['kind']) ||
        (fields['purpose'] as String? ?? '').trim().length < 10 ||
        (fields['purpose'] as String).length > 1000 ||
        validateWallSchedule(
              fields['local_due'] as String,
              fields['timezone'] as String,
              fields['fold'] as int?,
            ) !=
            null) {
      return false;
    }
    final intent = PendingIntent(
      path: 'clinical-plans',
      attemptPath: 'clinical-plans/creation-attempts/${connection.patientId}',
      body: {'access_id': connection.grant!.id, ...fields},
    );
    api.integrationIntents[intentId] = intent;
    return deliver(intent);
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin(), operationId = intentId;
    bool acknowledged = false;
    final wasUncertain = intent.uncertain;
    try {
      if (!await connection.verifyForRead() ||
          !valid(ticket) ||
          connection.grant?.id != intent.body['access_id']) {
        return false;
      }
      intent.uncertain = true;
      final receipt = ClinicalPlan.fromApi(
        object(
          (await api.integrationResource(
            intent.path,
            generation,
            method: 'POST',
            body: intent.body,
            key: intent.key,
          )).data,
        ),
        owner,
        role,
      );
      acknowledged = true;
      if (!valid(ticket)) return false;
      return await confirm(receipt, intent, operationId, ticket);
    } catch (failure) {
      if (!authenticatedCurrent) return false;
      if (!wasUncertain &&
          !acknowledged &&
          failure is IntegrationFailure &&
          [403, 404, 422].contains(failure.status)) {
        api.integrationIntents.remove(operationId);
      }
      if (valid(ticket)) {
        error =
            'Creation is unconfirmed. Check the original attempt. ${integrationError(failure)}';
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  Future<bool> confirm(
    ClinicalPlan receipt,
    PendingIntent intent,
    String operationId,
    int ticket,
  ) async {
    if (receipt.patient != connection.patientId ||
        receipt.grant != intent.body['access_id'] ||
        receipt.revision != 1 ||
        receipt.state != 'proposed' ||
        receipt.kind != intent.body['kind'] ||
        receipt.purpose != intent.body['purpose'] ||
        receipt.baseline != intent.body['baseline_capture_id'] ||
        (intent.body['source_id'] != null &&
            (receipt.source['source_id'] != intent.body['source_id'] ||
                receipt.source['source_type'] != intent.body['source_type'])) ||
        receipt.timezone != intent.body['timezone'] ||
        DateTime.parse(receipt.localWallTime) !=
            DateTime.parse(intent.body['local_due'] as String)) {
      throw const FormatException('Unverified new plan');
    }
    final latest = ClinicalPlan.fromApi(
      object(
        (await api.integrationResource(
          'clinical-plans/${receipt.id}',
          generation,
        )).data,
      ),
      owner,
      role,
    );
    if (!valid(ticket)) return false;
    if (latest.id != receipt.id ||
        latest.revision < receipt.revision ||
        latest.patient != receipt.patient ||
        latest.baseline != receipt.baseline ||
        latest.kind != receipt.kind ||
        latest.grant != receipt.grant) {
      throw const FormatException('Unverified current plan');
    }
    created = latest;
    api.integrationIntents.remove(operationId);
    return true;
  }

  Future<bool> reconcile({bool retryOriginal = false}) async {
    final intent = pending;
    if (intent == null || busy) return false;
    final ticket = begin(), operationId = intentId;
    try {
      final data = object(
        (await api.integrationResource(
          '${intent.attemptPath}/${intent.key}',
          generation,
        )).data,
      );
      if (!valid(ticket)) return false;
      if (data['status'] == 'committed') {
        return await confirm(
          ClinicalPlan.fromApi(object(data['result']), owner, role),
          intent,
          operationId,
          ticket,
        );
      }
      if (data['status'] == 'unknown' && retryOriginal) {
        busy = false;
        return deliver(intent);
      }
      if (!['unknown', 'expired'].contains(data['status'])) {
        throw const FormatException('Unverified create attempt');
      }
      error =
          'Creation ${data['status']}. Preserve the original intent; no new appointment is assumed.';
      return false;
    } catch (failure) {
      if (valid(ticket)) error = integrationError(failure);
      return false;
    } finally {
      finish(ticket);
    }
  }

  @override
  void dispose() {
    connection.removeListener(connectionChanged);
    super.dispose();
  }
}
