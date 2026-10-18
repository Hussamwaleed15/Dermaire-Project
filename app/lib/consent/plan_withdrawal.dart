import 'package:flutter/material.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../entry/entry_motion.dart';
import 'evaluation_withdrawal.dart';

class PlanWithdrawalIntent extends PendingIntent {
  PlanWithdrawalIntent(this.plan)
    : super(
        path: 'clinical-plans/${plan['id']}/cancel',
        attemptPath: 'clinical-plans/${plan['id']}/attempts/cancel',
        method: 'POST',
        body: {
          'expected_revision': plan['revision'],
          'reason': 'Patient requested withdrawal',
        },
      );
  final Map<String, dynamic> plan;
}

class PlanWithdrawalController extends PrivateController {
  static const storage = 'withdrawal:plan';
  List<Map<String, dynamic>> plans = [];
  String? next, outcome, lookupStatus;
  Map<String, dynamic>? candidate;
  bool confirmed = false;
  void select(Map<String, dynamic> plan) {
    if (!allowed || busy || pending != null) return;
    candidate = plan;
    confirmed = false;
    notifyListeners();
  }

  void approve(bool value) {
    if (!allowed || busy) return;
    confirmed = value;
    notifyListeners();
  }

  PlanWithdrawalIntent? get pending => authenticatedCurrent
      ? api.integrationIntents[storage] as PlanWithdrawalIntent?
      : null;
  bool get allowed => authenticatedCurrent && visible && role == 'patient';
  bool usable(int ticket) => allowed && revision == ticket;
  @override
  void wipe() {
    plans = [];
    candidate = null;
    confirmed = false;
    next = null;
    outcome = null;
    lookupStatus = null;
  }

  @override
  Future<void> refresh() => load();
  Future<void> load({bool more = false}) async {
    if (!allowed || busy || more && next == null) return;
    final after = more ? next : null, ticket = begin();
    candidate = null;
    confirmed = false;
    if (!more) plans = [];
    try {
      final data = await api.planWithdrawalMetadata(
        'clinical-plans',
        generation,
        query: {'limit': '50', 'after': ?after},
      );
      if (!usable(ticket)) return;
      final rows = (data['items'] as List).cast<Map<String, dynamic>>();
      final ids = plans.map((v) => v['id']).toSet();
      if (rows.any((v) => !ids.add(v['id'])) ||
          data['next_after'] != null && data['next_after'] == after) {
        throw const FormatException('Changed plan page');
      }
      plans = [...plans, ...rows];
      next = data['next_after'];
    } catch (e) {
      if (usable(ticket)) {
        plans = [];
        next = null;
        error = integrationError(e);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> cancel(Map<String, dynamic> selected) async {
    if (!allowed ||
        busy ||
        pending != null ||
        ['cancelled', 'reviewed'].contains(selected['state']) ||
        !plans.any((p) => identical(p, selected))) {
      return;
    }
    final op = PlanWithdrawalIntent(Map.unmodifiable(selected));
    api.integrationIntents[storage] = op;
    candidate = null;
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
        plans = [];
        error = 'Cancellation is unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  bool sameScope(Map v, PlanWithdrawalIntent op) => [
    'id',
    'patient_id',
    'doctor_id',
    'access_id',
    'kind',
  ].every((k) => v[k] == op.plan[k]);
  Future<void> send(PlanWithdrawalIntent op, int ticket) async {
    final result = await api.planWithdrawalMetadata(
      op.path,
      generation,
      method: 'POST',
      key: op.key,
      body: op.body,
    );
    if (!usable(ticket)) return;
    op.uncertain = true;
    if (!sameScope(result, op) ||
        result['state'] != 'cancelled' ||
        result['revision'] != op.plan['revision'] + 1) {
      throw const FormatException('Invalid cancellation acknowledgement');
    }
    await readReceipt(op, ticket, false);
  }

  Future<void> reconcile({bool retryOriginal = false}) async {
    final op = pending;
    if (!allowed || busy || op == null) return;
    final ticket = begin();
    try {
      await readReceipt(op, ticket, retryOriginal);
    } catch (e) {
      if (usable(ticket)) {
        plans = [];
        error = 'Cancellation remains unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> readReceipt(
    PlanWithdrawalIntent op,
    int ticket,
    bool retry,
  ) async {
    final data = await api.planWithdrawalMetadata(
      '${op.attemptPath}/${op.key}',
      generation,
    );
    if (!usable(ticket)) return;
    lookupStatus = data['status'];
    if (data['status'] != 'committed') {
      if (data['status'] == 'unknown' && retry) {
        await send(op, ticket);
      } else {
        outcome = data['status'] == 'expired'
            ? 'The original receipt expired. Do not replace this uncertain request.'
            : 'The original cancellation is unknown. No replacement was created.';
      }
      return;
    }
    final original = data['result'];
    if (original is! Map ||
        !sameScope(original, op) ||
        original['state'] != 'cancelled' ||
        original['revision'] != op.plan['revision'] + 1) {
      throw const FormatException('Invalid original cancellation');
    }
    final latest = await api.planWithdrawalMetadata(
      'clinical-plans/${op.plan['id']}',
      generation,
    );
    if (!usable(ticket)) return;
    if (!sameScope(latest, op) || latest['revision'] < original['revision']) {
      throw const FormatException('Invalid current plan');
    }
    if (!identical(pending, op)) return;
    api.integrationIntents.remove(storage);
    plans = [latest];
    next = null;
    outcome =
        'Original plan cancellation confirmed. Current server state: ${latest['state']}. Evaluation jobs have separate cancellation controls.';
  }
}

class PlanWithdrawalScreen extends StatelessWidget {
  const PlanWithdrawalScreen({super.key});
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: PlanWithdrawalController(),
    builder: page,
    unavailableBuilder: page,
  );
  Widget page(BuildContext context, PlanWithdrawalController c) => Scaffold(
    appBar: AppBar(title: const Text('Withdraw plan participation')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Follow-up and comparison plan cancellation. No photos, clinical notes or results are displayed. Evaluation cancellation is separate.',
        ),
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh plan metadata'),
        ),
        if (c.busy) const Text('Verifying plan withdrawal…'),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        if (!c.busy && c.error == null && c.plans.isEmpty)
          const Text('No plan metadata returned.'),
        for (final p in c.plans)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['kind'] == 'comparison'
                        ? 'Comparison plan'
                        : 'Follow-up plan',
                  ),
                  Text('Plan: ${p['id']}'),
                  if (p['kind'] == 'comparison')
                    OutlinedButton(
                      onPressed: c.busy
                          ? null
                          : () => Navigator.of(context).push(
                              entryRoute<void>(
                                context,
                                EvaluationWithdrawalScreen(id: p['id']),
                              ),
                            ),
                      child: const Text('Manage evaluation withdrawal'),
                    ),
                  Text('Status: ${p['state']} · revision ${p['revision']}'),
                  if (!['cancelled', 'reviewed'].contains(p['state']))
                    OutlinedButton(
                      onPressed: c.busy || c.pending != null
                          ? null
                          : () => c.select(p),
                      child: const Text('Withdraw from this plan'),
                    ),
                ],
              ),
            ),
          ),
        if (c.candidate != null && c.pending == null) ...[
          Text(
            'Selected plan: ${c.candidate!['id']} · revision ${c.candidate!['revision']}',
          ),
          CheckboxListTile(
            value: c.confirmed,
            onChanged: c.busy ? null : (v) => c.approve(v == true),
            title: const Text(
              'Withdraw participation in this original plan. Evaluation cancellation remains separate.',
            ),
          ),
          FilledButton(
            onPressed: c.busy || !c.confirmed
                ? null
                : () => c.cancel(c.candidate!),
            child: const Text('Cancel plan'),
          ),
        ],
        if (c.next != null)
          OutlinedButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('More plan metadata'),
          ),
        if (c.pending != null) ...[
          OutlinedButton(
            onPressed: c.busy ? null : c.reconcile,
            child: const Text('Check original cancellation'),
          ),
          if (c.lookupStatus == 'unknown')
            OutlinedButton(
              onPressed: c.busy ? null : () => c.reconcile(retryOriginal: true),
              child: const Text('Retry original cancellation'),
            ),
        ],
      ],
    ),
  );
}
