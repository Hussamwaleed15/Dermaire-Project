import 'dart:async';
import 'package:flutter/material.dart';
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import 'camera_session.dart';
import 'native_camera_port.dart';
import 'photo_preparation.dart';
import 'dart:typed_data';
import 'guided_capture_controller.dart';
import 'guided_capture_models.dart';
import 'guided_photo_disclosure.dart';
export 'guided_photo_disclosure.dart' show guidedPhotoDisclosure;

class GuidedCaptureEntry extends StatelessWidget {
  const GuidedCaptureEntry({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) {
    final generation = ApiService.instance.sessionGeneration;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Take a guided front-face photo or choose a JPEG/PNG. Review it before any upload. Captures stay separate from observations and tracking measurements.',
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('openGuidedCamera'),
            onPressed: () {
              if (ApiService.instance.isCurrentSession(generation) &&
                  ApiService.instance.canReadPatientClinicalStatus) {
                openEntry(context, GuidedCameraScreen(state: state));
              }
            },
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Open guided camera'),
          ),
        ],
      ),
    );
  }
}

class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({
    super.key,
    required this.state,
    this.cameraPort,
    this.prepare,
  });
  final DermaireState state;
  final CameraPort? cameraPort;
  final Future<PreparedPhoto> Function(Uint8List)? prepare;
  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen>
    with WidgetsBindingObserver {
  late final int generation;
  late final GuidedCaptureController capture;
  late final CameraSession camera;
  final scroll = ScrollController();
  ImageProvider? preview;
  Uint8List? previewBytes;
  bool previewFailed = false;
  bool allowPop = false;
  GuidedCapturePhase? previousPhase;
  bool get current =>
      mounted &&
      ApiService.instance.isCurrentSession(generation) &&
      capture.current;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    capture = widget.state.guidedCapture;
    capture.begin(generation);
    camera = CameraSession(
      widget.cameraPort ??
          NativeCameraPort(
            onFailure: (failure) => camera.deviceFailed(failure),
            canInitialize: () => current && !camera.backgrounded,
          ),
      allowed: () => current && capture.canChoose,
      prepare: widget.prepare,
      onPhoto: (photo, source) =>
          capture.select(photo, source, generation: generation),
    );
    widget.state.account.addListener(accountChanged);
    capture.addListener(changed);
    camera.addListener(changed);
    ApiService.instance.addListener(sessionChanged);
    WidgetsBinding.instance.addObserver(this);
    previousPhase = capture.phase;
    updatePreview();
  }

  void updatePreview() {
    final bytes = capture.photo?.bytes;
    if (bytes == previewBytes) return;
    final old = preview;
    previewBytes = bytes;
    previewFailed = false;
    preview = bytes == null
        ? null
        : ResizeImage.resizeIfNeeded(800, null, MemoryImage(bytes));
    if (old != null) unawaited(old.evict());
  }

  void changed() {
    if (!mounted) return;
    updatePreview();
    final next = capture.phase;
    if (previousPhase != next &&
        [
          GuidedCapturePhase.confirmed,
          GuidedCapturePhase.uncertain,
        ].contains(next)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (current && scroll.hasClients) scroll.jumpTo(0);
      });
    }
    previousPhase = next;
    setState(() {});
  }

  void accountChanged() {
    if (!mounted) return;
    if (!current) {
      camera.invalidate();
      if (ApiService.instance.sessionGeneration == generation &&
          !capture.allowed) {
        capture.clear();
      }
    }
    changed();
  }

  void sessionChanged() {
    if (mounted) camera.invalidate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState value) {
    if (value == AppLifecycleState.inactive) camera.suspend();
    if (value == AppLifecycleState.paused ||
        value == AppLifecycleState.hidden ||
        value == AppLifecycleState.detached) {
      final port = camera.port;
      camera.background(
        permissionOrDiscoveryPending:
            camera.phase == CameraSessionPhase.initializing &&
            port is NativeCameraPort &&
            !port.hardwareAllocated,
      );
    }
    if (value == AppLifecycleState.resumed) {
      camera.foreground();
      if (current &&
          camera.phase == CameraSessionPhase.paused &&
          camera.requestedCamera &&
          capture.phase == GuidedCapturePhase.ready) {
        unawaited(camera.start());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ApiService.instance.removeListener(sessionChanged);
    widget.state.account.removeListener(accountChanged);
    capture.removeListener(changed);
    camera.removeListener(changed);
    camera.dispose();
    capture.releasePreview(generation: generation);
    final old = preview;
    if (old != null) unawaited(old.evict());
    scroll.dispose();
    super.dispose();
  }

  Future<bool> confirmLeave() async {
    if (capture.phase != GuidedCapturePhase.uploading) return true;
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave while uploading?'),
        content: const Text(
          'An upload already sent may continue and store the photo. Leaving does not cancel it. Reopen this flow to see the confirmed result or unknown outcome.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> leave({bool home = false}) async {
    if (!mounted || (home && !current) || !await confirmLeave() || !mounted) {
      return;
    }
    if (home && !current) return;
    setState(() => allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (home) {
        if (!current) return;
        widget.state.selectTab(0);
        Navigator.of(context).popUntil((r) => r.isFirst);
      } else if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop();
      }
    });
  }

  Future<void> another() async {
    if (!current || capture.phase == GuidedCapturePhase.uploading) return;
    var acknowledged = false;
    if (capture.phase == GuidedCapturePhase.uncertain) {
      acknowledged =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Start a separate capture?'),
              content: const Text(
                'The previous upload may already be stored. This starts a new attempt and does not prove the previous one failed.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep current attempt'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Start separate capture'),
                ),
              ],
            ),
          ) ==
          true;
      if (!acknowledged || !current) return;
    }
    capture.reset(generation: generation, acknowledgeUncertain: acknowledged);
    if (current) await camera.start();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop || capture.phase != GuidedCapturePhase.uploading,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(leave());
    },
    child: !current
        ? const DermairePage(
            title: 'Session ended',
            children: [
              Text(
                'Reopen guided capture from your current account. Private photos and results have been cleared.',
              ),
            ],
          )
        : DermairePage(
            scrollController: scroll,
            title: 'Guided capture',
            subtitle:
                'Front-face photo quality and nonclinical image estimates. A photo never completes an observation or grants medical clearance.',
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClinicalHomePanel(controller: widget.state.clinical),
                  const SizedBox(height: 16),
                  if (capture.phase == GuidedCapturePhase.confirmed &&
                      capture.record != null)
                    CaptureResult(
                      record: capture.record!,
                      measurement: capture.measurement,
                      measurementError: capture.measurementError,
                      reading: capture.reading,
                      onRead: () =>
                          capture.refreshMeasurement(generation: generation),
                    )
                  else if (capture.phase == GuidedCapturePhase.uploading) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Uploading photo and awaiting the server response…',
                      ),
                    ),
                    if (!EntryMotion.reduced(context))
                      const LinearProgressIndicator(),
                    const Text(
                      'No stored result is confirmed yet. Do not submit a second upload.',
                    ),
                  ] else if (capture.phase == GuidedCapturePhase.uncertain) ...[
                    Semantics(
                      liveRegion: true,
                      child: Text(capture.error ?? 'Upload outcome unknown.'),
                    ),
                    const Text(
                      'This flow does not retry uploads automatically. It can read the original result only when the server returned a capture ID matching this upload.',
                    ),
                    if (capture.canReconcile)
                      OutlinedButton(
                        key: const Key('readCaptureAttempt'),
                        onPressed: capture.reading
                            ? null
                            : () => capture.reconcile(generation: generation),
                        child: Text(
                          capture.reading
                              ? 'Reading original capture…'
                              : 'Read original capture result',
                        ),
                      ),
                  ] else ...[
                    if (capture.error != null)
                      Semantics(liveRegion: true, child: Text(capture.error!)),
                    if (preview != null) ...[
                      Text(
                        'Review your photo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 10),
                      Image(
                        key: const Key('localPhotoPreview'),
                        image: preview!,
                        height: 300,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) {
                          final failedBytes = previewBytes;
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (current &&
                                previewBytes == failedBytes &&
                                !previewFailed) {
                              setState(() => previewFailed = true);
                            }
                          });
                          return const Text(
                            'Preview unavailable. Choose another readable photo before uploading.',
                          );
                        },
                      ),
                      const Text(
                        'Selected local photo. It has not been uploaded by choosing or taking it.',
                      ),
                      const SizedBox(height: 12),
                      const Text(guidedPhotoDisclosure),
                      const SizedBox(height: 12),
                      EntryPress(
                        child: FilledButton.icon(
                          key: const Key('confirmCaptureUpload'),
                          onPressed:
                              capture.phase == GuidedCapturePhase.review &&
                                  !previewFailed
                              ? () => capture.upload(generation: generation)
                              : null,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Confirm photo & upload'),
                        ),
                      ),
                      OutlinedButton(
                        key: const Key('retakeCapture'),
                        onPressed: another,
                        child: const Text('Retake'),
                      ),
                      TextButton(
                        key: const Key('cancelPhoto'),
                        onPressed: () {
                          if (current) {
                            capture.reset(generation: generation);
                            camera.invalidate();
                          }
                        },
                        child: const Text('Discard local preview'),
                      ),
                    ] else ...[
                      if (camera.phase == CameraSessionPhase.live) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: AspectRatio(
                            aspectRatio: 3 / 4,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(child: camera.port.preview()),
                                IgnorePointer(
                                  child: Center(
                                    child: FractionallySizedBox(
                                      widthFactor: .65,
                                      heightFactor: .68,
                                      child: DecoratedBox(
                                        key: const Key('cameraFramingGuide'),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            width: 2,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            100,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Text(
                          'Framing guide only — no live alignment or lighting validation.',
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const Key('takeGuidedPhoto'),
                          onPressed: camera.take,
                          icon: const Icon(Icons.camera_alt_rounded),
                          label: const Text('Take photo'),
                        ),
                      ],
                      if (camera.busy)
                        Semantics(
                          liveRegion: true,
                          child: Text(switch (camera.phase) {
                            CameraSessionPhase.initializing =>
                              'Opening camera…',
                            CameraSessionPhase.taking => 'Taking photo…',
                            CameraSessionPhase.selecting => 'Choosing a photo…',
                            _ => 'Preparing a readable upright preview…',
                          }),
                        ),
                      if (camera.error != null)
                        Semantics(liveRegion: true, child: Text(camera.error!)),
                      const Text(
                        'Face forward in portrait orientation. Keep your whole face and both eyes visible. Use consistent soft light, avoid heavy shadows, hold steady and keep a similar distance.',
                      ),
                      const Text(
                        'These instructions do not verify image quality. The server checks only after your explicit upload.',
                      ),
                      const Text(
                        'Use a single opaque JPEG or PNG up to 8 MiB and 16 megapixels. The server quality screen expects at least 640 pixels on each side.',
                      ),
                      if (camera.phase != CameraSessionPhase.live)
                        FilledButton.icon(
                          key: const Key('startLiveCamera'),
                          onPressed: camera.busy ? null : camera.start,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(
                            camera.phase == CameraSessionPhase.failed
                                ? 'Try camera again'
                                : 'Open camera',
                          ),
                        ),
                      if (camera.problem == CameraProblem.permanentlyDenied)
                        OutlinedButton(
                          key: const Key('cameraSettings'),
                          onPressed: () async {
                            if (!current) return;
                            final opened = await camera.port.settings();
                            if (context.mounted && current && !opened) {
                              showDermaireSnack(
                                context,
                                'App settings could not be opened. Use device settings or choose a photo.',
                              );
                            }
                          },
                          child: const Text('Open app settings'),
                        ),
                      OutlinedButton.icon(
                        key: const Key('chooseGuidedPhoto'),
                        onPressed: camera.busy ? null : camera.pick,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Choose JPEG / PNG'),
                      ),
                      const Text(guidedPhotoDisclosure),
                    ],
                  ],
                  const SizedBox(height: 14),
                  if ([
                    GuidedCapturePhase.confirmed,
                    GuidedCapturePhase.uncertain,
                  ].contains(capture.phase))
                    OutlinedButton(
                      key: const Key('anotherCapture'),
                      onPressed: capture.reading ? null : another,
                      child: const Text('Capture another photo'),
                    ),
                  TextButton(
                    key: const Key('captureReturnHome'),
                    onPressed: () => leave(home: true),
                    child: const Text('Return Home'),
                  ),
                  TextButton(
                    key: const Key('captureCancelBack'),
                    onPressed: () => leave(),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ],
          ),
  );
}

class CaptureResult extends StatelessWidget {
  const CaptureResult({
    super.key,
    required this.record,
    required this.measurement,
    required this.measurementError,
    required this.reading,
    required this.onRead,
  });
  final GuidedCaptureRecord record;
  final CaptureMeasurement? measurement;
  final String? measurementError;
  final bool reading;
  final VoidCallback onRead;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Server-confirmed capture result',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Capture: ${record.id}'),
            Text('Received by server: ${clinicalTime(record.receivedAt)}'),
            Text(
              record.stored
                  ? 'Accepted image stored in private Azure Blob Storage.'
                  : record.state == 'rejected'
                  ? 'Quality rejected. The server did not retain this image; rejection metadata is recorded.'
                  : 'Accepted by the server, but the image was not stored.',
            ),
            const Text(
              'Capture receipt is separate from an observation, check-in and tracking reference.',
            ),
          ],
        ),
      ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Image quality',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              record.quality.supported
                  ? 'Server quality decision: ${record.state}'
                  : 'The server returned an unsupported quality format. No verified quality pass is shown.',
            ),
            if (record.quality.supported)
              ExpansionTile(
                title: const Text('View individual quality checks'),
                expansionAnimationStyle: EntryMotion.reduced(context)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 180),
                      ),
                children: [
                  for (final entry in record.quality.checks.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${entry.key.replaceAll('_', ' ')}: ${entry.value.status} · ${entry.value.confidence}${entry.value.reason == null ? '' : ' — ${entry.value.reason}'}',
                      ),
                    ),
                ],
              ),
            for (final reason in record.quality.reasons) Text(reason),
            const Text('Quality-check limitations'),
            for (final limit in record.quality.limitations) Text(limit),
          ],
        ),
      ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nonclinical image estimates',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Image appearance proxies, not diagnoses, redness severity, calibrated skin measurements or treatment recommendations.',
            ),
            if (measurement == null)
              const Text(
                'No verified image estimates are available in this response.',
              )
            else ...[
              Text(
                'Algorithm: ${measurement!.algorithm} · Status: ${measurement!.status}',
              ),
              Text('Computed: ${clinicalTime(measurement!.measuredAt)}'),
              for (final metric in measurement!.metrics.values) ...[
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
                for (final limit in metric.limitations) Text(limit),
              ],
            ],
            if (measurementError != null)
              Semantics(liveRegion: true, child: Text(measurementError!)),
            if (record.state == 'accepted' && measurement == null)
              OutlinedButton(
                key: const Key('readCaptureEstimates'),
                onPressed: reading ? null : onRead,
                child: Text(
                  reading
                      ? 'Reading estimates…'
                      : 'Read available image estimates',
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
