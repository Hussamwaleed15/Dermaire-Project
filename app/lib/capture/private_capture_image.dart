import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'capture_history_models.dart';

class PrivateImageLease {
  PrivateImageLease(this._image, this._release);
  ui.Image? _image;
  final void Function(PrivateImageLease) _release;
  ui.Image? get image => _image;
  int get pixels => (_image?.width ?? 0) * (_image?.height ?? 0);
  void dispose() {
    if (_image == null) return;
    _release(this);
    _image!.dispose();
    _image = null;
  }
}

typedef PrivateImageReader =
    Future<PrivateImageBytes> Function(String id, int generation);

// No ImageProvider, disk files or global ImageCache entry. Explicit decoded
// leases and one queue bound downloads/decodes across history and detail routes.
class PrivateCaptureImages extends ChangeNotifier {
  PrivateCaptureImages(
    this.api, {
    PrivateImageReader? reader,
    this.authorization,
    this.scope,
  }) : reader = reader ?? ApiService.instance.readPrivateCaptureImage {
    api.addListener(sessionChanged);
    scope?.addListener(sessionChanged);
  }
  static final shared = PrivateCaptureImages(ApiService.instance);
  final ApiService api;
  final PrivateImageReader reader;
  final bool Function(int)? authorization;
  final Listenable? scope;
  static final Set<PrivateImageLease> _allLeases = {};
  final Set<PrivateImageLease> _leases = {};
  Future<void> _tail = Future.value();
  static int _reservedPixels = 0;
  bool disposed = false;
  int? _leaseGeneration;
  int get decodedPixels => _allLeases.fold(0, (n, l) => n + l.pixels);
  bool allowed(int generation) =>
      !disposed &&
      api.isCurrentSession(generation) &&
      (authorization?.call(generation) ?? api.canReadPatientClinicalStatus);
  void sessionChanged() {
    if (!allowed(_leaseGeneration ?? -1)) {
      for (final lease in _leases.toList()) {
        lease.dispose();
      }
      notifyListeners();
    }
  }

  Future<PrivateImageLease> load(
    String id,
    int generation,
    int edge, {
    required bool Function() active,
  }) async {
    final before = _tail;
    final done = Completer<void>();
    _tail = done.future;
    bool valid() => allowed(generation) && active();
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? decoded;
    bool decoding = false;
    int reserved = 0;
    try {
      await before;
      if (!valid()) throw const FormatException('Image request ended');
      if (edge < 1 || edge > privateViewerEdge) {
        throw ArgumentError('Invalid decode size');
      }
      final response = await reader(
        id,
        generation,
      ).timeout(const Duration(seconds: 20));
      if (!valid()) throw const FormatException('Image request ended');
      final bytes = response.bytes;
      final mime = response.mime.split(';').first.trim().toLowerCase();
      final png =
          bytes.length >= 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71 &&
          bytes[4] == 13 &&
          bytes[5] == 10 &&
          bytes[6] == 26 &&
          bytes[7] == 10;
      final jpeg =
          bytes.length >= 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      if (bytes.isEmpty ||
          bytes.length > maxPrivateImageBytes ||
          !(png && mime == 'image/png' || jpeg && mime == 'image/jpeg')) {
        throw const FormatException('Unsupported private image');
      }
      decoding = true;
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (!valid()) throw const FormatException('Image request ended');
      if (descriptor.width < 1 ||
          descriptor.height < 1 ||
          descriptor.width * descriptor.height > maxPrivateSourcePixels) {
        throw const FormatException('Image exceeds the memory limit');
      }
      final scale = math.min(
        1.0,
        edge / math.max(descriptor.width, descriptor.height),
      );
      final width = math.max(1, (descriptor.width * scale).floor());
      final height = math.max(1, (descriptor.height * scale).floor());
      if (decodedPixels + _reservedPixels + width * height >
          maxPrivateDecodedPixels) {
        throw const FormatException('Image exceeds the memory limit');
      }
      reserved = width * height;
      _reservedPixels += reserved;
      codec = await descriptor.instantiateCodec(
        targetWidth: width,
        targetHeight: height,
      );
      if (codec.frameCount != 1) {
        throw const FormatException('Animated images are unsupported');
      }
      decoded = (await codec.getNextFrame()).image;
      if (!valid()) throw const FormatException('Image request ended');
      if (decoded.width > edge ||
          decoded.height > edge ||
          decodedPixels + decoded.width * decoded.height >
              maxPrivateDecodedPixels) {
        throw const FormatException('Image exceeds the memory limit');
      }
      _leaseGeneration = generation;
      final lease = PrivateImageLease(decoded, (lease) {
        _leases.remove(lease);
        _allLeases.remove(lease);
      });
      _allLeases.add(lease);
      _leases.add(lease);
      decoded = null;
      return lease;
    } catch (e) {
      if (decoding && e is! FormatException) {
        throw const FormatException('Unreadable private image');
      }
      rethrow;
    } finally {
      decoded?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
      _reservedPixels -= reserved;
      done.complete();
    }
  }

  @override
  void dispose() {
    disposed = true;
    api.removeListener(sessionChanged);
    scope?.removeListener(sessionChanged);
    for (final lease in _leases.toList()) {
      lease.dispose();
    }
    super.dispose();
  }
}

class PrivateCaptureImage extends StatefulWidget {
  const PrivateCaptureImage({
    super.key,
    required this.id,
    required this.generation,
    required this.stored,
    this.viewer = false,
    this.images,
  });
  final String id;
  final int generation;
  final bool stored, viewer;
  final PrivateCaptureImages? images;
  @override
  State<PrivateCaptureImage> createState() => _PrivateCaptureImageState();
}

class _PrivateCaptureImageState extends State<PrivateCaptureImage> {
  late PrivateCaptureImages images;
  PrivateImageLease? lease;
  final transform = TransformationController();
  int revision = 0;
  bool loading = false;
  String? error;
  bool get current => mounted && images.allowed(widget.generation);
  @override
  void initState() {
    super.initState();
    images = widget.images ?? PrivateCaptureImages.shared;
    images.addListener(changed);
    unawaited(load());
  }

  @override
  void didUpdateWidget(PrivateCaptureImage old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id ||
        old.generation != widget.generation ||
        old.viewer != widget.viewer ||
        old.stored != widget.stored ||
        old.images != widget.images) {
      images.removeListener(changed);
      lease?.dispose();
      lease = null;
      images = widget.images ?? PrivateCaptureImages.shared;
      images.addListener(changed);
      transform.value = Matrix4.identity();
      unawaited(load());
    }
  }

  void changed() {
    if (!current) {
      revision++;
      lease?.dispose();
      lease = null;
      loading = false;
      error = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> load() async {
    final request = ++revision;
    lease?.dispose();
    lease = null;
    error = null;
    loading = current && widget.stored;
    if (mounted) setState(() {});
    if (!loading) return;
    try {
      final value = await images.load(
        widget.id,
        widget.generation,
        widget.viewer ? privateViewerEdge : privateThumbnailEdge,
        active: () => current && request == revision,
      );
      if (!current || request != revision) {
        value.dispose();
        return;
      }
      lease = value;
    } catch (e) {
      if (!current || request != revision) return;
      error = e is TimeoutException
          ? 'Image request timed out. Please retry.'
          : captureReadError(e, image: true);
    }
    if (current && request == revision) setState(() => loading = false);
  }

  void zoom(double factor) {
    final next = (transform.value.getMaxScaleOnAxis() * factor).clamp(1.0, 4.0);
    transform.value = Matrix4.diagonal3Values(next, next, 1);
  }

  @override
  void dispose() {
    revision++;
    images.removeListener(changed);
    lease?.dispose();
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!current) return const Text('Private image cleared. Session ended.');
    if (!widget.stored) {
      return const Text('No image was stored for this capture.');
    }
    if (loading) {
      return SizedBox(
        height: 100,
        child: Center(
          child: Semantics(
            liveRegion: true,
            child: Text('Loading private image…'),
          ),
        ),
      );
    }
    if (lease?.image == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(error ?? 'Image unavailable.'),
          ),
          TextButton.icon(
            onPressed: load,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry image read'),
          ),
        ],
      );
    }
    final image = Semantics(
      label: widget.viewer
          ? 'Private capture image. Pinch to zoom and drag to pan.'
          : 'Private capture thumbnail',
      image: true,
      child: RawImage(image: lease!.image, fit: BoxFit.contain),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: widget.viewer ? 340 : 180,
            width: double.infinity,
            child: widget.viewer
                ? InteractiveViewer(
                    key: const Key('privateImageZoom'),
                    transformationController: transform,
                    minScale: 1,
                    maxScale: 4,
                    child: SizedBox.expand(child: image),
                  )
                : image,
          ),
        ),
        if (widget.viewer) ...[
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                label: const Text('Zoom in'),
                onPressed: () => zoom(1.5),
                icon: const Icon(Icons.zoom_in),
              ),
              OutlinedButton.icon(
                label: const Text('Zoom out'),
                onPressed: () => zoom(1 / 1.5),
                icon: const Icon(Icons.zoom_out),
              ),
              OutlinedButton.icon(
                label: const Text('Reset image zoom'),
                onPressed: () => transform.value = Matrix4.identity(),
                icon: const Icon(Icons.fit_screen),
              ),
            ],
          ),
          const Text(
            'Private image preview. Display size is limited to 1600 pixels on the longest edge.',
          ),
        ],
      ],
    );
  }
}
