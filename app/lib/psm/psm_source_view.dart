import '../clinical/clinical_models.dart' show ReviewState, SafetyLevel;
import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import 'psm_models.dart';

class PsmFreshnessLabel extends StatelessWidget {
  const PsmFreshnessLabel({super.key, required this.value});
  final PsmFreshness value;
  @override
  Widget build(BuildContext context) => Text(
    'Server freshness: ${value.state} · Age: ${value.ageDays == null ? 'unknown' : '${value.ageDays} UTC calendar days'} · Latest source: ${value.latestAt == null ? 'not supplied' : clinicalTime(value.latestAt!)}',
  );
}

class PsmSourceView extends StatelessWidget {
  const PsmSourceView({super.key, required this.model});
  final PersonalSkinModel model;
  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Context, routine & product evidence',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Read-time PSM snapshot. Missing context is unknown, not proof of missed treatment or disease progression. No exposure or causation is inferred.',
        ),
        const Text('Daily context · patient-reported'),
        if (model.contextDays.isEmpty)
          const Text('No supported daily-context records were returned.'),
        for (final day in model.contextDays) ...[
          Text('Context: ${day.id} · Reported date: ${day.date}'),
          PsmFreshnessLabel(value: day.freshness),
          Text(
            day.conditions.isEmpty
                ? 'No unusual conditions listed in this record; other context is unknown.'
                : 'Reported conditions: ${day.conditions.join(', ')}',
          ),
        ],
        const Text('Routine · patient-reported configuration'),
        if (model.routine == null)
          const Text('Supported routine evidence is unavailable.')
        else ...[
          for (final entry in model.routine!.entries) ...[
            Text(
              'Entry: ${entry.id} · Product: ${entry.product} · ${entry.schedule} · ${entry.frequency} · Starts: ${entry.start}',
            ),
            PsmFreshnessLabel(value: entry.freshness),
          ],
          if (model.routine!.entries.isEmpty)
            const Text(
              'No configured entries returned. This does not describe actual product use.',
            ),
          Text(
            'Server summary over ${model.routine!.window} days: ${model.routine!.reported} reported slots, ${model.routine!.completed} reported completed, ${model.routine!.unknown} unknown of ${model.routine!.expected} known expected slots.',
          ),
          const Text(
            'Derived from self-reports, not independently verified application. Unknown slots are not skipped slots.',
          ),
          PsmFreshnessLabel(value: model.routine!.freshness),
          for (final row in model.routine!.history)
            Text(
              'Historical self-report: ${row.id} · Entry: ${row.entry} · ${row.date} ${row.slot} · ${row.status} · Frozen product: ${row.product ?? 'unknown'} · Recorded: ${clinicalTime(row.recorded)}',
            ),
          for (final caveat in model.routine!.caveats) Text(caveat),
        ],
        const Text('Products · deterministic evidence completeness'),
        if (model.productEvidence.isEmpty)
          const Text(
            'No supported product evidence records returned. Missing warnings do not establish compatibility.',
          ),
        for (final product in model.productEvidence) ...[
          Text(
            'Product: ${product.id} · Data completeness: ${product.completeness}',
          ),
          PsmFreshnessLabel(value: product.freshness),
          for (final unknown in product.unknowns) Text(unknown),
        ],
        for (final warning in model.productWarnings) ...[
          Text(
            'Recorded product warning: ${warning.key} · ${warning.severity}',
          ),
          Text(warning.explanation),
          Text(
            'Deterministic rule evidence · Products: ${warning.products.join(', ')} · Returned label: ${warning.confidence} (not a probability)',
          ),
          for (final limit in warning.limitations) Text(limit),
        ],
        const Text(
          'This summary does not replace current product warnings, clinician guidance or Safety. Ingredient concentration and actual exposure may be unknown.',
        ),
      ],
    ),
  );
}

class PsmClinicianPanel extends StatelessWidget {
  const PsmClinicianPanel({super.key, required this.value, this.stale = false});
  final PsmClinicianSnapshot value;
  final bool stale;
  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Clinician decision · PSM snapshot',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Source: clinician-authored decision. Read current guidance independently above.',
        ),
        if (stale)
          const Text(
            'Previously received clinician snapshot. Current read is unconfirmed; this cannot authorize action or establish clearance.',
          ),
        Text('Decision record: ${value.id}'),
        Text('State: ${value.state}'),
        if (ReviewState.parse(value.state) == ReviewState.unknown ||
            value.recommendation != null &&
                SafetyLevel.parse(value.recommendation!) == SafetyLevel.unknown)
          const Text(
            'Unsupported clinician snapshot value. Read current guidance separately.',
          ),
        if (value.recommendation == 'urgent')
          const Text(
            'Clinician snapshot reports urgent guidance. Do not delay seeking appropriate medical assessment while refreshing.',
          ),
        if (value.recommendation != null)
          Text('Server recommendation: ${value.recommendation}'),
        if (value.rationale != null) Text(value.rationale!),
        Text(
          'Recorded: ${clinicalTime(value.recordedAt)} · Freshness: ${value.freshness.state}',
        ),
        PsmFreshnessLabel(value: value.freshness),
        const Text(
          'A lower clinician recommendation does not remove independent urgent Safety Engine guidance.',
        ),
      ],
    ),
  );
}
