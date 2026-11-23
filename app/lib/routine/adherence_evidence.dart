import 'package:flutter/material.dart';
import 'routine_controller.dart';

/// A loaded record is evidence only for its original configuration. Absence in
/// a bounded history is not proof of non-use and cannot create a report.
class AdherenceSlotEvidence extends StatelessWidget {
  const AdherenceSlotEvidence({
    super.key,
    required this.entry,
    required this.history,
    required this.day,
    required this.slot,
    required this.stale,
  });
  final Map entry;
  final List<Map<String, dynamic>> history;
  final String day, slot;
  final bool stale;
  @override
  Widget build(BuildContext context) {
    final rows = history
        .where(
          (r) =>
              r['routine_entry_id'] == entry['id'] &&
              r['date'] == day &&
              r['slot'] == slot,
        )
        .toList();
    if (rows.isEmpty) {
      return Text(
        '$slot · Adherence unknown: no report in the loaded history for $day UTC.${stale ? ' Current read is unconfirmed.' : ''}',
      );
    }
    if (rows.length != 1) {
      return Text(
        '$slot · Conflicting loaded report identities. Refresh before interpreting this slot.',
      );
    }
    final report = rows.single,
        snapshot = rows.single['configuration_snapshot'];
    final same =
        snapshot is Map &&
        [
          'id',
          'product_id',
          'schedule',
          'frequency',
          'active',
          'updated_at',
        ].every((k) => RoutineController.sameWire(snapshot[k], entry[k])) &&
        (snapshot['revision'] == null && entry['revision'] == null ||
            snapshot['revision'] == entry['revision']);
    return Text(
      '$slot · ${same ? 'Recorded for displayed configuration' : 'Historical configuration report'}: ${report['status']} · $day UTC · Record: ${report['id']} · Product: ${snapshot is Map ? snapshot['product_id'] ?? 'unknown' : 'unknown'} · Recorded: ${report['created_at']}${stale ? ' · Current read unconfirmed' : ''}. Configuration does not prove actual use.',
    );
  }
}
