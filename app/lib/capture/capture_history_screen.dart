import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import 'capture_history_controller.dart';
import 'capture_history_models.dart';
import 'guided_camera_screen.dart';
import 'guided_capture_models.dart';
import 'private_capture_image.dart';

class CaptureHistoryScreen extends StatefulWidget {
  const CaptureHistoryScreen({
    super.key,
    required this.state,
    this.repository,
    this.images,
  });
  final DermaireState state;
  final CaptureHistoryRepository? repository;
  final PrivateCaptureImages? images;
  @override
  State<CaptureHistoryScreen> createState() => _CaptureHistoryScreenState();
}

class _CaptureHistoryScreenState extends State<CaptureHistoryScreen> {
  late final CaptureHistoryController history;
  @override
  void initState() {
    super.initState();
    history = CaptureHistoryController(
      ApiService.instance,
      repository: widget.repository,
    )..addListener(changed);
    unawaited(history.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    history.removeListener(changed);
    history.dispose();
    super.dispose();
  }

  Future<void> camera() async {
    if (!history.current) return;
    await openEntry(context, GuidedCameraScreen(state: widget.state));
    if (history.current) {
      await history
          .refresh(); // GET only. Upload attempts are never inferred as saved rows.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!history.current) {
      return const DermairePage(
        title: 'Session ended',
        children: [
          Text(
            'Private capture history has been cleared. Reopen it after sign-in.',
          ),
        ],
      );
    }
    final rows = <Widget>[
      const Eyebrow('Private image history'),
      Text(
        'Your capture timeline',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      const Text(
        'Most recent 100 capture records. Dates are server receipt dates in UTC, not camera time. This history is separate from observation check-ins.',
      ),
      const SizedBox(height: 16),
      ClinicalHomePanel(controller: widget.state.clinical),
      FilledButton.icon(
        key: const Key('historyOpenCamera'),
        onPressed: camera,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('New guided capture'),
      ),
      OutlinedButton.icon(
        key: const Key('refreshCaptureHistory'),
        onPressed: history.loading ? null : history.refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh history'),
      ),
      if (history.loading)
        Semantics(liveRegion: true, child: Text('Reading capture history…')),
      if (history.error != null)
        Semantics(liveRegion: true, child: Text(history.error!)),
      if (history.confirmed && history.records.isEmpty)
        const DermaireCard(
          child: Text(
            'No captures returned by the server. Start a guided capture when you are ready.',
          ),
        ),
    ];
    String? previous;
    for (final record in history.records) {
      final date = captureDate(record.receivedAt);
      if (date != previous) {
        rows.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              '$date · UTC',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        );
        previous = date;
      }
      rows.add(
        _CaptureTile(
          key: ValueKey('${history.generation}:${record.id}'),
          record: record,
          generation: history.generation,
          images: widget.images,
          onOpen: () {
            if (history.current) {
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
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Image history')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: history.refresh,
          child: ListView.builder(
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            addAutomaticKeepAlives: false,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            itemCount: rows.length,
            itemBuilder: (_, index) => rows[index],
          ),
        ),
      ),
    );
  }
}

class _CaptureTile extends StatelessWidget {
  const _CaptureTile({
    super.key,
    required this.record,
    required this.generation,
    required this.onOpen,
    this.images,
  });
  final GuidedCaptureRecord record;
  final int generation;
  final VoidCallback onOpen;
  final PrivateCaptureImages? images;
  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          record.state == 'rejected'
              ? 'Quality-rejected capture'
              : 'Accepted capture',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(captureTime(record.receivedAt)),
        Text('Reported source: ${record.source} · ${record.view} view'),
        const SizedBox(height: 12),
        InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: PrivateCaptureImage(
            id: record.id,
            generation: generation,
            stored: record.stored,
            images: images,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          record.stored
              ? 'Storage recorded as private Azure. Availability is checked when the image loads.'
              : 'Image not stored; capture metadata only.',
        ),
        TextButton.icon(
          key: ValueKey('captureDetails:${record.id}'),
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_full),
          label: const Text('Open capture details'),
        ),
      ],
    ),
  );
}

class CaptureDetailScreen extends StatefulWidget {
  const CaptureDetailScreen({
    super.key,
    required this.state,
    required this.id,
    this.repository,
    this.images,
  });
  final DermaireState state;
  final String id;
  final CaptureHistoryRepository? repository;
  final PrivateCaptureImages? images;
  @override
  State<CaptureDetailScreen> createState() => _CaptureDetailScreenState();
}

class _CaptureDetailScreenState extends State<CaptureDetailScreen> {
  late final CaptureDetailController detail;
  @override
  void initState() {
    super.initState();
    detail = CaptureDetailController(
      ApiService.instance,
      widget.id,
      repository: widget.repository,
    )..addListener(changed);
    unawaited(detail.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    detail.removeListener(changed);
    detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!detail.current) {
      return const DermairePage(
        title: 'Session ended',
        children: [
          Text(
            'Private capture details have been cleared. Reopen from your current account.',
          ),
        ],
      );
    }
    final record = detail.record;
    return DermairePage(
      title: 'Capture details',
      subtitle:
          'Private image and verified server information. Image availability is independent of the stored receipt.',
      children: [
        ClinicalHomePanel(controller: widget.state.clinical),
        if (detail.loading)
          Semantics(liveRegion: true, child: Text('Reading capture details…')),
        if (detail.error != null) ...[
          Semantics(liveRegion: true, child: Text(detail.error!)),
          OutlinedButton(
            onPressed: detail.refresh,
            child: const Text('Retry capture read'),
          ),
        ],
        if (record != null) ...[
          DermaireCard(
            child: PrivateCaptureImage(
              key: ValueKey(record),
              id: record.id,
              generation: detail.generation,
              stored: record.stored,
              viewer: true,
              images: widget.images,
            ),
          ),
          Text('Reported source: ${record.source} · ${record.view} view'),
          Text('Quality version: ${record.quality.version}'),
          const Text(
            'Images are privately uploaded/stored on Azure when accepted and storage is confirmed. Account deletion includes stored images. Individual photo deletion and public sharing are not available here.',
          ),
          CaptureResult(
            record: record,
            measurement: detail.measurement,
            measurementError: detail.measurementError,
            reading: detail.reading,
            onRead: detail.readMeasurement,
          ),
          if (detail.measurement != null) ...[
            Text(
              detail.measurement!.status == 'unavailable'
                  ? 'Source: server-recorded unavailability.'
                  : 'Source: server-computed upload bytes, bound to this capture and quality fingerprint.',
            ),
            const Text(
              'Region: fixed bilateral cheek rectangles from the frontal face detector.',
            ),
            for (final metric in detail.measurement!.metrics.values)
              Text(
                'Source capture: ${detail.measurement!.captureId} · Method: ${detail.measurement!.algorithm} · Metric: ${metric.key}',
              ),
          ],
        ],
      ],
    );
  }
}
