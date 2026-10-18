import 'package:flutter/material.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import '../entry/entry_motion.dart';

/// A withdrawal-only patient action. It never reads grants/patient records or
/// establishes safety acceptance; a historical receipt is not current access.
class ClinicianWithdrawalController extends PrivateController {
  static const intentId = 'consent:revoke_all';
  bool confirmedScope = false;
  String? outcome, lookupStatus;
  bool get canWithdraw => authenticatedCurrent && visible && role == 'patient';
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents[intentId] : null;
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
      path: 'doctor/revoke/${resourceId(owner)}',
      attemptPath: 'doctor/consent-attempts/revoke_all',
      method: 'DELETE',
      body: {},
    );
    api.integrationIntents[intentId] = op;
    confirmedScope = false;
    final ticket = begin();
    try {
      await send(op, ticket);
    } catch (e) {
      if (usable(ticket)) {
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
    if (data is! Map || data['success'] != true) {
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
        error = 'Withdrawal remains unconfirmed. ${integrationError(e)}';
      }
    } finally {
      finish(ticket);
    }
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
        value['operation'] != 'revoke_all' ||
        value['access_id'] != owner ||
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
        result['success'] != true) {
      throw const FormatException('Unverified withdrawal result');
    }
    if (!identical(pending, op)) return;
    api.integrationIntents.remove(intentId);
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
