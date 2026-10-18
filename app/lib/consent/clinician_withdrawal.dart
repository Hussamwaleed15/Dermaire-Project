import 'package:flutter/material.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../entry/entry_motion.dart';
import '../doctor/doctor_models.dart';

/// A withdrawal-only patient action. It never reads grants/patient records or
/// establishes safety acceptance; a historical receipt is not current access.
class ClinicianWithdrawalController extends PrivateController {
  static const intentId = 'consent:revoke_all';
  String? get selectedId => null;
  String get storageId => intentId;
  Future<void> verifyCurrent(PendingIntent op, int ticket) async {}
  void discardDenied(Object failure) {}
  bool confirmedScope = false;
  String? outcome, lookupStatus;
  bool get canWithdraw => authenticatedCurrent && visible && role == 'patient';
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents[storageId] : null;
  bool usable(int ticket) => canWithdraw && ticket == revision;
  void confirmScope(bool value) {
    if (!canWithdraw || busy || pending != null) return;
    confirmedScope = value;
    notifyListeners();
  }

  @override
  void wipe() {
    confirmedScope = false;
    outcome = null;
    lookupStatus = null;
  }

  @override
  Future<void> refresh() async {
    if (canWithdraw) notifyListeners();
  }

  Future<void> withdrawAll() async {
    if (!canWithdraw || busy || !confirmedScope || pending != null) return;
    final op = PendingIntent(
      path: selectedId == null
          ? 'doctor/revoke/${resourceId(owner)}'
          : 'doctor/access/${resourceId(selectedId)}',
      attemptPath: selectedId == null
          ? 'doctor/consent-attempts/revoke_all'
          : 'doctor/consent-attempts/revoke',
      method: 'DELETE',
      body: {},
    );
    api.integrationIntents[storageId] = op;
    confirmedScope = false;
    final ticket = begin();
    try {
      await send(op, ticket);
    } catch (e) {
      if (usable(ticket)) {
        discardDenied(e);
        op.uncertain = true;
        error = 'Withdrawal is unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> send(PendingIntent op, int ticket) async {
    final data = (await api.integrationResource(
      op.path,
      generation,
      method: 'DELETE',
      key: op.key,
      withdrawal: true,
    )).data;
    if (!usable(ticket)) return;
    if (data is! Map ||
        (op.path.startsWith('doctor/access/')
            ? !validSelectedResult(data, op)
            : data['success'] != true)) {
      throw const FormatException('Withdrawal acknowledgement unavailable');
    }
    // The SQL receipt proves only the original withdrawal, not later grants.
    await readReceipt(op, ticket, retryOriginal: false);
  }

  Future<void> reconcile({bool retryOriginal = false}) async {
    final op = pending;
    if (!canWithdraw || busy || op == null) return;
    final ticket = begin();
    try {
      await readReceipt(op, ticket, retryOriginal: retryOriginal);
    } catch (e) {
      if (usable(ticket)) {
        discardDenied(e);
        error = 'Withdrawal remains unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
  }

  bool validSelectedResult(Map data, PendingIntent op) {
    final grant = DoctorGrant.fromApi(
      Map<String, dynamic>.from(data),
      patient: owner,
    );
    return grant.id == op.path.split('/').last && grant.confirmedRevoked;
  }

  Future<void> readReceipt(
    PendingIntent op,
    int ticket, {
    required bool retryOriginal,
  }) async {
    final value = (await api.integrationResource(
      '${op.attemptPath}/${op.key}',
      generation,
      withdrawal: true,
    )).data;
    if (!usable(ticket)) return;
    if (value is! Map ||
        value['schema_version'] != 1 ||
        value['attempt_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(value['attempt_id'] as String)) {
      throw const FormatException('Invalid withdrawal receipt');
    }
    if (value['status'] == 'unknown') {
      if (value['result'] != null ||
          value['retry_safe'] != false ||
          value['owner_id'] != null && value['owner_id'] != owner ||
          value['actor_id'] != null && value['actor_id'] != owner) {
        throw const FormatException('Unknown is not a withdrawal confirmation');
      }
      lookupStatus = 'unknown';
      op.uncertain = true;
      if (retryOriginal) {
        await send(op, ticket);
      } else {
        outcome =
            'The original withdrawal is still unconfirmed. No replacement request was created.';
      }
      return;
    }
    if (value['owner_id'] != owner ||
        value['actor_id'] != owner ||
        value['operation'] !=
            (op.path.startsWith('doctor/access/') ? 'revoke' : 'revoke_all') ||
        value['access_id'] !=
            (op.path.startsWith('doctor/access/')
                ? op.path.split('/').last
                : owner) ||
        value['snapshot_basis'] != 'original_committed_not_current') {
      throw const FormatException('Wrong original withdrawal scope');
    }
    if (value['status'] == 'expired') {
      if (value['result_availability'] != 'expired' ||
          value['result'] != null) {
        throw const FormatException('Expired withdrawal result unavailable');
      }
      lookupStatus = 'expired';
      outcome =
          'The original receipt expired. Review current permissions before starting another withdrawal. This request was not repeated.';
      return;
    }
    final result = value['result'];
    if (value['status'] != 'committed' ||
        value['result_availability'] != 'retained' ||
        result is! Map ||
        (op.path.startsWith('doctor/access/')
            ? !validSelectedResult(result, op)
            : result['success'] != true)) {
      throw const FormatException('Unverified withdrawal result');
    }
    await verifyCurrent(op, ticket);
    if (!usable(ticket) || !identical(pending, op)) return;
    api.integrationIntents.remove(storageId);
    lookupStatus = 'committed';
    outcome =
        'The server recorded the original withdrawal. Permissions granted afterwards are not included in that receipt.';
  }
}

class ClinicianWithdrawalScreen extends StatelessWidget {
  const ClinicianWithdrawalScreen({super.key});
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: ClinicianWithdrawalController(),
    builder: page,
    unavailableBuilder: page,
  );
  Widget page(
    BuildContext context,
    ClinicianWithdrawalController c,
  ) => Scaffold(
    appBar: AppBar(title: const Text('Clinician access controls')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Manage permission to share your patient records.'),
        const Text(
          'You can withdraw clinician permissions without accepting the current safety policy. Your saved account records remain.',
        ),
        if (c.role != 'patient')
          const Text('These controls are available to patient accounts.')
        else ...[
          OutlinedButton(
            onPressed: c.busy
                ? null
                : () => Navigator.of(context).push(
                    entryRoute<void>(
                      context,
                      const SelectiveWithdrawalScreen(),
                    ),
                  ),
            child: const Text('Choose one clinician grant'),
          ),
          if (c.outcome != null)
            Semantics(liveRegion: true, child: Text(c.outcome!)),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                c.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (c.busy)
            EntryMotion.reduced(context)
                ? const Text('Waiting for withdrawal confirmation…')
                : const LinearProgressIndicator(
                    semanticsLabel: 'Waiting for withdrawal confirmation',
                  ),
          if (c.pending == null) ...[
            CheckboxListTile(
              key: const Key('confirmClinicianWithdrawal'),
              contentPadding: EdgeInsets.zero,
              value: c.confirmedScope,
              onChanged: c.busy ? null : (v) => c.confirmScope(v == true),
              title: const Text(
                'Revoke all active clinician access and pending invitations.',
              ),
            ),
            FilledButton(
              onPressed: c.busy || !c.confirmedScope ? null : c.withdrawAll,
              child: const Text('Withdraw clinician access'),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: c.busy ? null : c.reconcile,
              child: const Text('Check original withdrawal'),
            ),
            if (c.lookupStatus == 'unknown')
              OutlinedButton(
                onPressed: c.busy
                    ? null
                    : () => c.reconcile(retryOriginal: true),
                child: const Text('Retry original withdrawal'),
              ),
            if (c.lookupStatus == 'expired')
              const Text(
                'Return to the accepted-policy workspace to review current permissions.',
              ),
          ],
          const Text(
            'An original withdrawal receipt does not describe the current permission list. A new grant requires its own explicit withdrawal.',
          ),
        ],
      ],
    ),
  );
}

class SelectiveWithdrawalController extends ClinicianWithdrawalController {
  List<DoctorGrant> grants = [];
  String? selection;
  @override
  String? get selectedId => selection;
  @override
  String get storageId => 'consent:revoke';
  @override
  void wipe() {
    super.wipe();
    grants = [];
    selection = null;
  }

  @override
  void discardDenied(Object failure) {
    if (failure is IntegrationFailure && [401, 403].contains(failure.status)) {
      grants = [];
      selection = null;
      confirmedScope = false;
    }
  }

  Future<List<DoctorGrant>> readGrants() async {
    final data = (await api.integrationResource(
      'doctor/access',
      generation,
      withdrawal: true,
    )).data;
    if (data is! List) throw const FormatException('Invalid access metadata');
    final rows = data
        .map(
          (v) => DoctorGrant.fromApi(
            Map<String, dynamic>.from(v as Map),
            patient: owner,
          ),
        )
        .toList();
    if (rows.map((r) => r.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate access metadata');
    }
    return rows;
  }

  @override
  Future<void> refresh() async {
    if (!canWithdraw || busy) return;
    final ticket = begin();
    grants = [];
    selection = null;
    confirmedScope = false;
    try {
      final rows = await readGrants();
      if (usable(ticket)) grants = rows;
    } catch (e) {
      if (usable(ticket)) error = integrationError(e);
    } finally {
      finish(ticket);
    }
  }

  void select(String id) {
    if (!canWithdraw ||
        busy ||
        pending != null ||
        !grants.any(
          (g) =>
              g.id == id &&
              ['active', 'pending'].contains(g.status) &&
              g.expiresAt.isAfter(DateTime.now().toUtc()),
        )) {
      return;
    }
    selection = id;
    confirmedScope = false;
    outcome = null;
    notifyListeners();
  }

  @override
  Future<void> withdrawAll() async {
    if (selection == null ||
        !grants.any(
          (g) =>
              g.id == selection &&
              ['active', 'pending'].contains(g.status) &&
              g.expiresAt.isAfter(DateTime.now().toUtc()),
        )) {
      return;
    }
    await super.withdrawAll();
  }

  @override
  Future<void> verifyCurrent(PendingIntent op, int ticket) async {
    final rows = await readGrants();
    if (!usable(ticket)) return;
    if (!rows.any(
      (g) => g.id == op.path.split('/').last && g.confirmedRevoked,
    )) {
      throw const FormatException('Current revocation not confirmed');
    }
    grants = rows;
    selection = null;
  }
}

class SelectiveWithdrawalScreen extends StatelessWidget {
  const SelectiveWithdrawalScreen({super.key});
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: SelectiveWithdrawalController(),
    builder: page,
    unavailableBuilder: page,
  );
  Widget page(
    BuildContext context,
    SelectiveWithdrawalController c,
  ) => Scaffold(
    appBar: AppBar(title: const Text('Choose clinician access')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Withdraw one original grant. Other grants remain separate. Only sharing metadata is shown here.',
        ),
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh sharing metadata'),
        ),
        if (c.busy) const Text('Verifying sharing permissions…'),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        if (!c.busy && c.error == null && c.grants.isEmpty)
          const Text('No clinician grants returned.'),
        for (final g in c.grants)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.doctorName ??
                        (g.doctorIdValue == null
                            ? 'Pending invitation'
                            : 'Linked clinician'),
                  ),
                  Text('Grant: ${g.id}'),
                  Text('Status: ${g.status}'),
                  Text('Expires: ${g.expiresAt.toUtc().toIso8601String()} UTC'),
                  if (['active', 'pending'].contains(g.status) &&
                      g.expiresAt.isAfter(DateTime.now().toUtc()))
                    OutlinedButton(
                      onPressed: c.busy || c.pending != null
                          ? null
                          : () => c.select(g.id),
                      child: Text(
                        c.selection == g.id
                            ? 'Selected grant'
                            : 'Select this grant',
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (c.pending == null && c.selection != null) ...[
          CheckboxListTile(
            value: c.confirmedScope,
            onChanged: c.busy ? null : (v) => c.confirmScope(v == true),
            title: const Text('Withdraw only the selected clinician grant.'),
          ),
          FilledButton(
            onPressed: c.busy || !c.confirmedScope ? null : c.withdrawAll,
            child: const Text('Revoke selected grant'),
          ),
        ],
        if (c.pending != null) ...[
          OutlinedButton(
            onPressed: c.busy ? null : c.reconcile,
            child: const Text('Check original withdrawal'),
          ),
          if (c.lookupStatus == 'unknown')
            OutlinedButton(
              onPressed: c.busy ? null : () => c.reconcile(retryOriginal: true),
              child: const Text('Retry original withdrawal'),
            ),
          if (c.lookupStatus == 'expired')
            const Text(
              'The original result expired. Review current sharing; do not replace an uncertain request.',
            ),
        ],
      ],
    ),
  );
}
