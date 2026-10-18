import 'package:flutter/material.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';

/// Session-memory correlation only. Backend DELETE has no Idempotency-Key or
/// attempt lookup; the generated PendingIntent key is never sent as one.
class EvaluationWithdrawalIntent extends PendingIntent {
  EvaluationWithdrawalIntent(this.plan, this.job)
    : super(
        path: 'clinical-plans/${plan['id']}/evaluation',
        attemptPath: 'clinical-plans/${plan['id']}/evaluation',
        method: 'DELETE',
        body: {},
      );
  final Map<String, dynamic> plan, job;
}

class EvaluationWithdrawalController extends PrivateController {
  EvaluationWithdrawalController(this.id);
  final String id;
  static const storage = 'withdrawal:evaluation';
  Map<String, dynamic>? plan, job;
  bool confirmed = false;
  String? outcome;
  bool get allowed => authenticatedCurrent && visible && role == 'patient';
  bool usable(int ticket) => allowed && ticket == revision;
  EvaluationWithdrawalIntent? get pending => authenticatedCurrent
      ? api.integrationIntents[storage] as EvaluationWithdrawalIntent?
      : null;
  @override
  void wipe() {
    plan = null;
    job = null;
    confirmed = false;
    outcome = null;
  }

  void approve(bool v) {
    if (allowed && !busy && pending == null) {
      confirmed = v;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> readPlan() => api.planWithdrawalMetadata(
    'clinical-plans/${resourceId(id)}',
    generation,
  );
  Future<Map<String, dynamic>> readJob() => api.planWithdrawalMetadata(
    'clinical-plans/${resourceId(id)}/evaluation',
    generation,
  );
  @override
  Future<void> refresh() async {
    if (!allowed || busy) return;
    final ticket = begin();
    wipe();
    try {
      final p = await readPlan();
      final j = await readJob();
      if (!usable(ticket)) return;
      if (p['kind'] != 'comparison') {
        throw const FormatException('Comparison plan required');
      }
      plan = p;
      job = j;
    } catch (e) {
      if (usable(ticket)) {
        wipe();
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  bool samePlan(Map value, EvaluationWithdrawalIntent op) => [
    'id',
    'patient_id',
    'doctor_id',
    'access_id',
    'kind',
  ].every((k) => value[k] == op.plan[k]);
  Future<void> cancel() async {
    if (!allowed ||
        busy ||
        !confirmed ||
        pending != null ||
        plan == null ||
        job?['id'] == null ||
        job?['state'] == 'cancelled') {
      return;
    }
    final op = EvaluationWithdrawalIntent(
      Map.unmodifiable(plan!),
      Map.unmodifiable(job!),
    );
    api.integrationIntents[storage] = op;
    confirmed = false;
    final ticket = begin();
    try {
      await send(op, ticket);
    } catch (e) {
      if (usable(ticket)) {
        if (!op.uncertain &&
            e is IntegrationFailure &&
            [403, 404, 409, 422].contains(e.status)) {
          api.integrationIntents.remove(storage);
        } else {
          op.uncertain = true;
        }
        plan = null;
        job = null;
        error =
            'Evaluation cancellation is unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> send(EvaluationWithdrawalIntent op, int ticket) async {
    final p = await readPlan(), j = await readJob();
    if (!usable(ticket)) return;
    if (!samePlan(p, op) ||
        p['revision'] != op.plan['revision'] ||
        j['id'] != op.job['id'] ||
        j['state'] == 'not_requested') {
      throw IntegrationFailure(409);
    }
    if (j['state'] == 'cancelled') {
      await finishOriginal(op, ticket, p, j);
      return;
    }
    final wasUncertain = op.uncertain;
    op.uncertain = true; // DELETE may commit from this point onward.
    Map<String, dynamic> result;
    try {
      result = await api.planWithdrawalMetadata(
        op.path,
        generation,
        method: 'DELETE',
        query: {'expected_revision': '${op.plan['revision']}'},
      );
    } catch (e) {
      if (!wasUncertain &&
          e is IntegrationFailure &&
          [403, 404, 409, 422].contains(e.status)) {
        op.uncertain = false;
      }
      rethrow;
    }
    if (!usable(ticket)) return;
    if (result['id'] != op.job['id'] || result['state'] != 'cancelled') {
      throw const FormatException('Original job cancellation not verified');
    }
    await check(op, ticket, false);
  }

  Future<void> finishOriginal(
    EvaluationWithdrawalIntent op,
    int ticket,
    Map<String, dynamic> p,
    Map<String, dynamic> j,
  ) async {
    if (!usable(ticket) || !identical(pending, op)) return;
    if (!samePlan(p, op) ||
        j['id'] != op.job['id'] ||
        j['state'] != 'cancelled' ||
        p['revision'] < j['plan_revision']) {
      throw const FormatException('Original evaluation scope changed');
    }
    api.integrationIntents.remove(storage);
    plan = p;
    job = j;
    outcome =
        'Original evaluation job cancellation confirmed by current server state. Parent plan state: ${p['state']}. No plan cancellation or clinical conclusion is implied.';
  }

  Future<void> check(
    EvaluationWithdrawalIntent op,
    int ticket,
    bool retry,
  ) async {
    final p = await readPlan(), j = await readJob();
    if (!usable(ticket)) return;
    if (!samePlan(p, op) || j['id'] != op.job['id']) {
      throw IntegrationFailure(409);
    }
    if (j['state'] == 'cancelled') {
      await finishOriginal(op, ticket, p, j);
      return;
    }
    if (retry) {
      await send(op, ticket);
    } else {
      outcome =
          'Original evaluation cancellation remains unconfirmed. No DELETE was repeated.';
    }
  }

  Future<void> reconcile({bool retryOriginal = false}) async {
    final op = pending;
    if (!allowed || busy || op == null || op.plan['id'] != id) return;
    final ticket = begin();
    try {
      await check(op, ticket, retryOriginal);
    } catch (e) {
      if (usable(ticket)) {
        plan = null;
        job = null;
        error =
            'Original evaluation remains unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }
}

class EvaluationWithdrawalScreen extends StatelessWidget {
  const EvaluationWithdrawalScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: EvaluationWithdrawalController(id),
    builder: page,
    unavailableBuilder: page,
  );
  Widget page(
    BuildContext context,
    EvaluationWithdrawalController c,
  ) => Scaffold(
    appBar: AppBar(title: const Text('Withdraw evaluation consent')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Cancel processing for one original comparison job. The parent plan and human review are separate. No images or inference results are displayed.',
        ),
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh evaluation metadata'),
        ),
        if (c.busy) const Text('Verifying evaluation cancellation…'),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        if (c.plan != null)
          Text(
            'Parent plan: ${c.plan!['state']} · revision ${c.plan!['revision']}',
          ),
        if (c.job != null) Text('Evaluation job: ${c.job!['state']}'),
        if (c.pending == null &&
            c.job?['id'] != null &&
            c.job?['state'] != 'cancelled') ...[
          CheckboxListTile(
            value: c.confirmed,
            onChanged: c.busy ? null : (v) => c.approve(v == true),
            title: const Text('Cancel only this original evaluation job.'),
          ),
          FilledButton(
            onPressed: c.busy || !c.confirmed ? null : c.cancel,
            child: const Text('Cancel evaluation job'),
          ),
        ],
        if (c.pending != null) ...[
          OutlinedButton(
            onPressed: c.busy ? null : c.reconcile,
            child: const Text('Check original evaluation'),
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(retryOriginal: true),
            child: const Text('Verify scope, then retry original cancellation'),
          ),
          const Text(
            'A different current job cannot resolve this original request. No replacement job will be cancelled.',
          ),
        ],
      ],
    ),
  );
}
