import 'package:flutter/material.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import 'guided_capture_models.dart';

/// Read-only evidence, never a trend, diagnosis or clinical comparison result.
class MeasurementEvidence extends StatelessWidget {
  const MeasurementEvidence({super.key, required this.measurement});
  final CaptureMeasurement measurement;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Algorithm: ${measurement.algorithm} · Status: ${measurement.status}',
      ),
      Text('Recorded: ${clinicalTime(measurement.measuredAt)}'),
      Text(
        'Measurement: ${measurement.id} · Source capture: ${measurement.captureId}',
      ),
      Text(
        measurement.status == 'unavailable'
            ? 'Source: server-recorded unavailability.'
            : 'Source: server-computed upload bytes, bound to this capture and quality fingerprint.',
      ),
      const Text(
        'Region: fixed bilateral cheek rectangles from the frontal face detector.',
      ),
      for (final metric in measurement.metrics.values) ...[
        Text(
          metric.key == 'red_chromaticity_proxy'
              ? 'Red chromaticity proxy'
              : 'Texture contrast proxy',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          metric.value == null
              ? 'Value unavailable (${metric.status})'
              : '${metric.value} · ${metric.unit} · Limited image proxy',
        ),
        if (metric.meaning != null) Text(metric.meaning!),
        if (metric.reason != null)
          Text('Reason: ${metric.reason!.replaceAll('_', ' ')}'),
        for (final limit in metric.limitations) Text(limit),
      ],
      Text(switch (measurement.comparison.state) {
        'not_comparable' =>
          'Server comparison: not comparable. Reason: ${measurement.comparison.reason!.replaceAll('_', ' ')}.',
        'absent' =>
          'Comparison metadata was not returned. Comparability is unknown.',
        _ =>
          'Comparison metadata is unsupported. No verified change result is shown.',
      }),
      const Text(
        'Chronological values are not validated change analysis. Plan-linked evaluation and clinician review are separate.',
      ),
    ],
  );
}
