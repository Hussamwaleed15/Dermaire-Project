import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../integration/operation_identity.dart';
import '../integration/private_view.dart';
import 'operation_journal.dart';
import 'product_receipt_reader.dart';
import 'configuration_receipt_reader.dart';

class RecoveryReviewController extends PrivateController {
  List<OperationIdentity> identities = [];
  String? outcome;
  @override
  void wipe() {
    identities = [];
    outcome = null;
  }

  @override
  Future<void> refresh() async {
    if (!current) return;
    identities = api.quarantinedOperations;
    notifyListeners();
  }

  JournalReceiptReader? readerFor(OperationIdentity i) {
    if (role != 'patient') return null;
    try {
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

  String domainLabel(OperationIdentity i) => i.path.startsWith('products')
      ? 'product'
      : i.path.startsWith('routine/')
      ? 'routine'
      : 'experiment';

  Future<void> inspect(OperationIdentity identity) async {
    if (!current || busy || !identities.contains(identity)) return;
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
        error = integrationError(e);
      }
    } finally {
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
                Text('Pending ${i.path.split('/').first} operation'),
                const Text(
                  'Original identity retained. No request payload or access token restored.',
                ),
                if (c.readerFor(i) != null)
                  OutlinedButton(
                    onPressed: c.busy ? null : () => c.inspect(i),
                    child: Text('Check original ${c.domainLabel(i)} receipt'),
                  )
                else
                  const Text(
                    'Cross-login receipt review is not integrated for this operation. Nothing will be replayed.',
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
