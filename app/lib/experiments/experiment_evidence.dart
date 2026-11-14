import 'package:flutter/material.dart';
import 'metric_contract.dart';

class FrozenExperimentSummary extends StatelessWidget {
  const FrozenExperimentSummary({super.key, required this.row});
  final Map row;
  @override
  Widget build(BuildContext context) {
    final s = row['definition_snapshot'];
    final expected = s is Map ? s['expected'] : null,
        product = s is Map ? s['product'] : null;
    final verified =
        s is Map &&
        s['engine_version'] == 2 &&
        s['source'] == 'user_configured' &&
        expected is Map &&
        product is Map &&
        expected['id'] == row['routine_entry_id'] &&
        product['id'] == row['product_id'] &&
        expected['product_id'] == product['id'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Experiment: ${row['id']} · Routine: ${row['routine_entry_id'] ?? 'unknown'} · Product: ${row['product_id'] ?? 'unknown'}',
        ),
        Text(
          'Current resource revision: ${row['revision'] ?? 'not supplied by legacy response'}',
        ),
        if (row['status'] != 'draft') ...[
          if (!verified)
            const Text(
              'Complete linked frozen configuration unavailable or inconsistent. No replacement product or baseline is inferred.',
            )
          else ...[
            Text(
              'Frozen product: ${product['name'] ?? 'name unavailable'} · ID: ${product['id']}',
            ),
            Text(
              'Frozen configuration: ${expected['schedule']} · Active: ${expected['active']} · Saved: ${s['frozen_at'] ?? 'unknown'}',
            ),
            if (s['baseline'] is Map)
              Text(
                'Frozen baseline: ${s['baseline']['start'] ?? 'unknown'} to ${s['baseline']['end_exclusive'] ?? 'unknown'} (end excluded). This is the recorded engine window, not a universal treatment or photo schedule.',
              ),
          ],
          if (verified &&
              s['baseline'] is Map &&
              s['baseline']['checkins'] is List)
            for (final reference in (s['baseline']['checkins'] as List).take(
              100,
            ))
              if (reference is Map)
                Text(
                  'Frozen baseline record: ${reference['id'] ?? 'unknown'} · ${reference['created_at'] ?? 'timestamp unavailable'} · ${reference['source'] ?? 'source unknown'}',
                ),
          const Text(
            'Frozen definition is historical evidence, separate from current routine/product metadata. Stopping an experiment does not restore treatment or configure a comparison.',
          ),
        ],
      ],
    );
  }
}

class ExperimentEvidenceDetails extends StatelessWidget {
  const ExperimentEvidenceDetails({super.key, required this.result});
  final Map result;
  @override
  Widget build(BuildContext context) {
    ExperimentMetricContract? metric;
    try {
      metric = ExperimentMetricContract.parse(result);
    } catch (_) {
      return const Text(
        'Unsupported metric metadata. Numeric evaluation evidence is withheld.',
      );
    }
    final comparison = result['comparison'] as Map? ?? {},
        change = result['observed_change'] as Map? ?? {},
        provenance = result['provenance'] as Map? ?? {};
    final snapshot = provenance['definition_snapshot'];
    final adherence = result['adherence'] as Map? ?? {},
        context = result['confounders'] as Map? ?? {};
    final expected = adherence['expected_slots'],
        reported = adherence['reported_slots'],
        followed = adherence['followed_slots'];
    final countsValid =
        expected is int &&
        expected >= 0 &&
        reported is int &&
        reported >= 0 &&
        reported <= expected &&
        followed is int &&
        followed >= 0 &&
        followed <= reported &&
        ExperimentMetricContract.validAdherence(result);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saved evaluation: ${result['evaluated_at']}'),
          Text(
            'Source: ${provenance['source']} · ${provenance['algorithm'] ?? 'Not supplied'}',
          ),
          if (snapshot is Map)
            Text(
              'Saved frozen references: product ${snapshot['product'] is Map ? snapshot['product']['id'] ?? 'unknown' : 'unknown'} · routine ${snapshot['expected'] is Map ? snapshot['expected']['id'] ?? 'unknown' : 'unknown'} · Frozen at: ${snapshot['frozen_at'] ?? 'unknown'}. These are saved evaluation references, not a current product lookup.',
            ),
          if (metric == null)
            const Text(
              'Legacy evaluation: explicit metric units/method contract not supplied. Numeric values are not interpreted as percentages or capture fractions.',
            )
          else ...[
            Text(
              'Metric: ${metric.metric} · Unit: score_0_to_100 · Difference unit: score_points',
            ),
            Text(
              'Reported source: ${metric.source} · Direction: ${metric.direction}',
            ),
            Text(
              'Method versions: ${metric.versions.isEmpty ? 'not recorded' : metric.versions.join(', ')} · Provenance: ${metric.provenance}',
            ),
            const Text(
              'Aggregation: within UTC day mean, then equal day mean. These legacy tracking scores are not clinical measurements or the fractional capture proxies.',
            ),
          ],
          Text(
            'Baseline window: ${comparison['start'] ?? 'Not supplied'} to ${comparison['end_exclusive'] ?? 'Not supplied'} (end excluded)',
          ),
          Text(
            'Source compared: ${comparison['measurement_source'] ?? 'Not supplied'} · Baseline days: ${comparison['baseline_days'] ?? 'Unknown'} · Experiment days: ${comparison['experiment_days'] ?? 'Unknown'}',
          ),
          if (change.isNotEmpty)
            Text(
              'Metric: ${change['metric'] ?? 'Unknown'} · Baseline value: ${change['baseline_mean'] ?? 'Unavailable'} · Experiment value: ${change['experiment_mean'] ?? 'Unavailable'} · Difference: ${change['delta_points'] ?? 'Unavailable'}',
            ),
          if (countsValid)
            Text(
              'Saved adherence: $reported of $expected expected slots reported; $followed followed the expected ${adherence['expected_status'] ?? 'unknown'} status. ${expected - reported} slots remain unknown, not skipped.',
            )
          else
            const Text(
              'Saved adherence counts unavailable or inconsistent. No adherence aggregate inferred.',
            ),
          const Text(
            'Following a stop-entry experiment means explicitly reported skipped use, not automatic non-use.',
          ),
          for (final key in [
            'unusual_days',
            'baseline_unusual_conditions',
            'routine_changed_after_activation',
            'product_changed_after_activation',
            'baseline_inconsistent_routine_reports',
            'inconsistent_routine_reports',
            'cycle_context_days',
          ])
            Text(
              'Recorded ${key.replaceAll('_', ' ')}: ${context[key] ?? 'unknown'}',
            ),
          const Text(
            'Unknown context does not mean no confounder. No medical adjustment or causal interpretation is made.',
          ),
          for (final source in [
            'experiment_checkins',
            'adherence',
            'contexts',
          ]) ...[
            Text('Saved $source references'),
            if (provenance[source] is! List ||
                (provenance[source] as List).isEmpty)
              const Text('No source references supplied.'),
            if (provenance[source] is List)
              for (final item in (provenance[source] as List).take(100))
                if (item is Map)
                  Text(
                    'Record ${item['id'] ?? 'unknown'} · ${item['created_at'] ?? item['updated_at'] ?? item['date'] ?? 'timestamp unavailable'} · Source ${item['source'] ?? 'not supplied'}',
                  ),
          ],
          const Text(
            'At most100 references per source shown. This is saved evaluation evidence, not current resource verification, image comparison, causal proof, diagnosis or an AI-directed treatment plan.',
          ),
        ],
      ),
    );
  }
}
