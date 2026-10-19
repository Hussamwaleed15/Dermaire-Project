import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../integration/operation_identity.dart';
import '../integration/private_view.dart';
import 'operation_journal.dart';
import 'product_receipt_reader.dart';
import 'configuration_receipt_reader.dart';
import 'clinical_receipt_reader.dart';
import 'adherence_receipt_reader.dart';
import 'message_receipt_reader.dart';
import 'plan_receipt_reader.dart';
import 'grant_receipt_reader.dart';
import 'recovery_check.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;

class RecoveryReviewController extends PrivateController {
  List<OperationIdentity> identities = [];
  String? outcome;
  final checks = <String, RecoveryCheck>{};
  String? activeKey;
  @override
  void wipe() {
    identities = [];
    outcome = null;
    checks.clear();
    activeKey = null;
  }

  @override
  Future<void> refresh() async {
    if (!current) return;
    identities = api.quarantinedOperations;
    notifyListeners();
  }

  JournalReceiptReader? readerFor(OperationIdentity i) {
    try {
      if (i.path == 'doctor/claim' ||
          i.path == 'doctor/generate-qr' ||
          i.path.startsWith('doctor/access/') ||
          i.path.startsWith('doctor/revoke/')) {
        final reader = GrantReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (i.path.startsWith('messaging/threads/')) {
        final reader = MessageReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (i.path == 'clinical-plans' || i.path.startsWith('clinical-plans/')) {
        final reader = PlanReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (role == 'doctor') {
        final reader = ClinicalReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (role != 'patient') return null;
      if (i.path == 'routine/adherence') {
        final reader = AdherenceReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (i.path == 'products' || i.path.startsWith('products/')) {
        final reader = ProductReceiptReader(api, generation);
        reader.kind(i);
        return reader;
      }
      final reader = ConfigurationReceiptReader(api, generation);
      reader.contract(i);
      return reader;
    } on FormatException {
      return null;
    }
  }

  String unsupportedReason(OperationIdentity i) {
    if (i.path.startsWith('agent/')) {
      return 'Agent requests use current-action and session revision checks. No independent original confirmed-request receipt is exposed. Review the request in its original authorized session; nothing is replayed here.';
    }
    if (i.path.startsWith('notifications/')) {
      return 'Notification changes expose current-state or revision checks, without an independent original-attempt receipt. Review current preferences or inbox state; nothing is replayed here.';
    }
    if (i.path == 'routine/calendar-policy') {
      return 'Calendar changes use an original revision precondition, without a keyed receipt. Review the current calendar policy in Routine; no timezone change is repeated here.';
    }
    if (i.path == 'doctor/claim') {
      return 'Original claim routing metadata is unavailable. Review currently authorized patients. This screen cannot restore a bearer code or invent an attempt lookup.';
    }
    if (i.path.endsWith('/evaluation')) {
      return 'This evaluation operation has no matching keyed receipt identity. Review original job history and current authorized consent; no cancellation or processing request is repeated here.';
    }
    return 'Cross-login receipt review is not integrated for this operation. Nothing will be replayed.';
  }

  String domainLabel(OperationIdentity i) => i.path.startsWith('messaging/')
      ? 'message'
      : i.path.startsWith('clinical-plans')
      ? (i.path.contains('/evaluation')
            ? 'comparison request'
            : 'clinical plan')
      : i.path.startsWith('doctor/patients/')
      ? (i.path.endsWith('/notes') ? 'clinical note' : 'clinical review')
      : i.path == 'routine/adherence'
      ? 'reported use'
      : i.path.startsWith('agent/')
      ? 'Agent request'
      : i.path.startsWith('notifications/')
      ? 'notification'
      : i.path == 'routine/calendar-policy'
      ? 'calendar policy'
      : i.path.startsWith('products')
      ? 'product'
      : i.path.startsWith('routine/')
      ? 'routine'
      : 'experiment';

  Future<void> finishReview(OperationIdentity identity) async {
    if (!current ||
        busy ||
        !identities.contains(identity) ||
        checks[identity.key]?.state != RecoveryCheckState.currentRecord) {
      return;
    }
    activeKey = identity.key;
    final ticket = begin();
    outcome = null;
    try {
      final reader = readerFor(identity);
      if (reader == null) throw const FormatException('Unsupported receipt');
      final receipt = await reader.lookup(identity);
      if (!valid(ticket)) return;
      final verified =
          receipt.outcome == ReceiptOutcome.committed &&
          await reader.verifyCurrent(identity, receipt);
      if (!valid(ticket)) return;
      if (!verified) {
        checks[identity.key] = RecoveryCheck(switch (receipt.outcome) {
          ReceiptOutcome.unknown => RecoveryCheckState.unknown,
          ReceiptOutcome.expired => RecoveryCheckState.expired,
          ReceiptOutcome.committed => RecoveryCheckState.reviewRequired,
        }, DateTime.now().toUtc());
        outcome =
            'The original or current evidence changed. The identity remains retained; no change was sent.';
        return;
      }
      if (!api.finishRetainedReview(identity, generation)) {
        throw const FormatException('Original identity changed during review');
      }
      identities = api.quarantinedOperations;
      checks.remove(identity.key);
      outcome =
          'Original receipt and current state rechecked. Review completed; no change was sent.';
    } catch (e) {
      if (valid(ticket)) {
        checks[identity.key] = RecoveryCheck(
          e is RecoveryPermissionLost
              ? RecoveryCheckState.permissionUnavailable
              : RecoveryCheckState.verificationUnavailable,
          DateTime.now().toUtc(),
        );
        error = e is RecoveryPermissionLost
            ? 'Original authorization is unavailable. The identity remains retained.'
            : integrationError(e);
      }
    } finally {
      if (valid(ticket)) activeKey = null;
      finish(ticket);
    }
  }

  Future<void> inspect(OperationIdentity identity) async {
    if (!current || busy || !identities.contains(identity)) return;
    activeKey = identity.key;
    final ticket = begin();
    outcome = null;
    try {
      final reader = readerFor(identity);
      if (reader == null) throw const FormatException('Unsupported receipt');
      final domain = domainLabel(identity);
      final receipt = await reader.lookup(identity);
      if (!valid(ticket)) return;
      final currentVerified = receipt.outcome == ReceiptOutcome.committed
          ? await reader.verifyCurrent(identity, receipt)
          : false;
      if (!valid(ticket)) return;
      checks[identity.key] = RecoveryCheck(switch (receipt.outcome) {
        ReceiptOutcome.unknown => RecoveryCheckState.unknown,
        ReceiptOutcome.expired => RecoveryCheckState.expired,
        ReceiptOutcome.committed =>
          currentVerified
              ? RecoveryCheckState.currentRecord
              : RecoveryCheckState.reviewRequired,
      }, DateTime.now().toUtc());
      outcome = switch (receipt.outcome) {
        ReceiptOutcome.unknown =>
          'Original receipt is unknown. Replacement remains blocked; nothing was replayed.',
        ReceiptOutcome.expired =>
          'Original receipt has expired. Replacement remains blocked; review current records.',
        ReceiptOutcome.committed =>
          currentVerified
              ? 'Original receipt recorded and current $domain verified separately. Nothing was replayed. The identity remains retained for review.'
              : 'Original receipt recorded; current $domain differs, is unavailable, or requires additional related-state review. Review current records. Nothing was replayed.',
      };
    } catch (e) {
      if (valid(ticket)) {
        outcome = null;
        checks[identity.key] = RecoveryCheck(
          e is RecoveryPermissionLost
              ? RecoveryCheckState.permissionUnavailable
              : RecoveryCheckState.verificationUnavailable,
          DateTime.now().toUtc(),
        );
        error = e is RecoveryPermissionLost
            ? 'Original authorization is unavailable. Nothing was replayed. Retain this identity for authorized review.'
            : integrationError(e);
      }
    } finally {
      if (valid(ticket)) activeKey = null;
      finish(ticket);
    }
  }
}

class RecoveryReviewScreen extends StatefulWidget {
  const RecoveryReviewScreen({super.key});
  @override
  State<RecoveryReviewScreen> createState() => _RecoveryReviewState();
}

class _RecoveryReviewState extends State<RecoveryReviewScreen> {
  final controller = RecoveryReviewController();
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      title: 'Pending operation review',
      children: [
        const Text(
          'Private content was cleared when your session ended. Minimum operation identities remain in memory for this account only. They do not restore consent or survive closing the app.',
        ),
        const Text(
          'No automatic retry or replacement. Other operation types may require their original session or a supported recovery contract.',
        ),
        if (c.identities.isEmpty)
          const Text('No retained operation identities for this account.'),
        if (c.busy)
          const Text(
            'Checking original receipt and current authorized record…',
          ),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        for (final i in c.identities)
          DermaireCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending ${c.domainLabel(i)} operation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Original identity retained. No request payload or access token restored.',
                ),
                if (c.checks[i.key] case final check?) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      check.label,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(check.nextStep),
                  Text('Verification read: ${clinicalTime(check.checkedAt)}'),
                  if (check.state == RecoveryCheckState.currentRecord)
                    OutlinedButton(
                      onPressed: c.busy ? null : () => c.finishReview(i),
                      child: const Text('Finish verified receipt review'),
                    ),
                ],
                if (c.readerFor(i) != null)
                  OutlinedButton(
                    onPressed: c.busy ? null : () => c.inspect(i),
                    child: Text(
                      c.busy && c.activeKey == i.key
                          ? 'Checking original receipt…'
                          : 'Check original ${c.domainLabel(i)} receipt',
                    ),
                  )
                else
                  Text(c.unsupportedReason(i)),
              ],
            ),
          ),
      ],
    ),
  );
}
