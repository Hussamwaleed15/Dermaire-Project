import 'dart:async';
import 'package:flutter/material.dart';
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import 'capture_history_controller.dart';
import 'capture_history_models.dart';
import 'capture_history_screen.dart';
import 'measurement_evidence.dart';
import 'private_capture_image.dart';

class MeasurementHistoryScreen extends StatefulWidget {
  const MeasurementHistoryScreen({
    super.key,
    required this.state,
    this.repository,
    this.images,
  });
  final DermaireState state;
  final CaptureHistoryRepository? repository;
  final PrivateCaptureImages? images;
  @override
  State<MeasurementHistoryScreen> createState() => _MeasurementHistoryState();
}

class _MeasurementHistoryState extends State<MeasurementHistoryScreen>
    with WidgetsBindingObserver {
  late MeasurementHistoryController controller;
  bool backgrounded = false;
  void bind() {
    controller = MeasurementHistoryController(
      ApiService.instance,
      repository: widget.repository,
    )..addListener(changed);
    unawaited(controller.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bind();
  }

  @override
  void didUpdateWidget(covariant MeasurementHistoryScreen old) {
    super.didUpdateWidget(old);
    if (old.repository != widget.repository || old.state != widget.state) {
      if (!controller.disposed) {
        controller.removeListener(changed);
        controller.dispose();
      }
      backgrounded = false;
      bind();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ([
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.detached,
        ].contains(state) &&
        !backgrounded) {
      controller.removeListener(changed);
      controller.dispose();
      setState(() => backgrounded = true);
    } else if (state == AppLifecycleState.resumed && backgrounded) {
      final sameSession = ApiService.instance.isCurrentSession(
        controller.generation,
      );
      setState(() => backgrounded = false);
      if (sameSession) bind();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!controller.disposed) {
      controller.removeListener(changed);
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DermairePage(
    title: 'Recorded measurement history',
    subtitle:
        'Read-only image appearance proxies. Not diagnoses or validated change analysis.',
    children: [
      if (backgrounded)
        const Text(
          'Private measurements hidden while the app is in the background.',
        )
      else if (!controller.current)
        const Text(
          'Session ended. Private measurements have been cleared. Reopen after sign-in.',
        )
      else ...[
        const Text(
          'Latest 100 capture receipts, newest first in UTC. Read five records at a time. Older records beyond this window are not available here; this is not a complete lifetime history.',
        ),
        const Text(
          'Receipt time is not camera time. Camera/upload source and front view are client-reported. Values from different images are not automatically comparable.',
        ),
        OutlinedButton(
          onPressed: controller.loading ? null : controller.refresh,
          child: const Text('Refresh measurement history'),
        ),
        if (controller.loading) const Text('Reading capture receipts…'),
        if (controller.error != null)
          Semantics(liveRegion: true, child: Text(controller.error!)),
        if (controller.confirmed && controller.records.isEmpty)
          const Text('No capture records returned by the server.'),
        for (final record in controller.visibleRecords)
          DermaireCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  captureTime(record.receivedAt),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Capture: ${record.id} · ${record.source} · ${record.view}',
                ),
                Text(
                  'Server capture decision: ${record.state} · Quality version: ${record.quality.version}',
                ),
                if (record.state == 'rejected')
                  const Text(
                    'Quality-rejected capture. No measurement read or value is inferred.',
                  )
                else if (controller.readingId == record.id)
                  const Text('Reading recorded measurement…')
                else if (controller.measurements[record.id] != null)
                  ExpansionTile(
                    key: ValueKey('measurement:${record.id}'),
                    title: const Text('Recorded nonclinical estimates'),
                    expansionAnimationStyle: EntryMotion.reduced(context)
                        ? AnimationStyle.noAnimation
                        : null,
                    children: [
                      MeasurementEvidence(
                        measurement: controller.measurements[record.id]!,
                      ),
                    ],
                  )
                else if (controller.failures[record.id] != null) ...[
                  Text(controller.failures[record.id]!),
                  TextButton(
                    onPressed: controller.reading
                        ? null
                        : () => controller.retry(record.id),
                    child: const Text('Retry measurement read'),
                  ),
                ] else
                  const Text('Measurement read pending.'),
                TextButton(
                  key: ValueKey('measurementDetails:${record.id}'),
                  onPressed: () {
                    if (controller.current) {
                      openEntry(
                        context,
                        CaptureDetailScreen(
                          state: widget.state,
                          id: record.id,
                          repository: widget.repository,
                          images: widget.images,
                        ),
                      );
                    }
                  },
                  child: const Text('Open authorized capture details'),
                ),
              ],
            ),
          ),
        if (controller.reading)
          const Text('Reading bounded measurement batch…'),
        if (controller.hasMore)
          OutlinedButton(
            key: const Key('moreMeasurements'),
            onPressed: controller.reading ? null : controller.loadMore,
            child: const Text('Read next five capture records'),
          ),
        if (controller.confirmed &&
            !controller.hasMore &&
            controller.records.isNotEmpty)
          const Text(
            'End of the returned capture window. No earlier data is inferred.',
          ),
      ],
    ],
  );
}
