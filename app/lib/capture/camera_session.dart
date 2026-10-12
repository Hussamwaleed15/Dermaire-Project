import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'photo_preparation.dart';

enum CameraProblem {
  unavailable,
  denied,
  permanentlyDenied,
  restricted,
  initialization,
  capture,
  selection,
}

class CameraFailure implements Exception {
  const CameraFailure(this.problem);
  final CameraProblem problem;
}

abstract interface class CameraPort {
  Future<void> initialize();
  Widget preview();
  Future<Uint8List> take();
  Future<Uint8List?> pick();
  Future<void> close();
  Future<bool> settings();
}

enum CameraSessionPhase {
  idle,
  initializing,
  live,
  taking,
  selecting,
  preparing,
  paused,
  failed,
  disposed,
}

class CameraSession extends ChangeNotifier {
  CameraSession(
    this.port, {
    required this.allowed,
    required this.onPhoto,
    Future<PreparedPhoto> Function(Uint8List)? prepare,
  }) : prepare = prepare ?? preparePhoto;
  final CameraPort port;
  final bool Function() allowed;
  final void Function(PreparedPhoto, String) onPhoto;
  final Future<PreparedPhoto> Function(Uint8List) prepare;
  CameraSessionPhase phase = CameraSessionPhase.idle;
  CameraProblem? problem;
  String? error;
  int _revision = 0;
  bool _disposed = false;
  bool requestedCamera = false;
  bool backgrounded = false;
  int? _pickerRevision;
  bool get awaitingPicker =>
      !_disposed &&
      _pickerRevision == _revision &&
      [
        CameraSessionPhase.selecting,
        CameraSessionPhase.preparing,
      ].contains(phase);
  bool get busy => [
    CameraSessionPhase.initializing,
    CameraSessionPhase.taking,
    CameraSessionPhase.selecting,
    CameraSessionPhase.preparing,
  ].contains(phase);
  bool _valid(int revision) => !_disposed && revision == _revision && allowed();
  Future<void> _release = Future.value();
  Future<void> _close() {
    final previous = _release, closing = port.close();
    return _release = Future.wait([
      previous,
      closing,
    ]).then<void>((_) {}).catchError((_) {});
  }

  Future<void> start() async {
    if (_disposed ||
        !allowed() ||
        busy ||
        backgrounded ||
        phase == CameraSessionPhase.live) {
      return;
    }
    final revision = ++_revision;
    requestedCamera = true;
    phase = CameraSessionPhase.initializing;
    problem = null;
    error = null;
    notifyListeners();
    try {
      await _release.timeout(const Duration(seconds: 20));
      if (!_valid(revision)) return;
      await port.initialize().timeout(const Duration(seconds: 20));
      if (!_valid(revision)) return;
      if (backgrounded) {
        phase = CameraSessionPhase.paused;
        unawaited(_close());
      } else {
        phase = CameraSessionPhase.live;
      }
    } catch (failure) {
      if (!_valid(revision)) return;
      unawaited(_close());
      if (!_valid(revision)) return;
      if (backgrounded) {
        phase = CameraSessionPhase.paused;
        error = null;
      } else {
        _failure(failure);
      }
    }
    if (_valid(revision)) notifyListeners();
  }

  Future<void> take() async {
    if (phase != CameraSessionPhase.live || !allowed() || _disposed) return;
    await _acquire(camera: true);
  }

  Future<void> pick() async {
    if (_disposed || !allowed() || busy) return;
    requestedCamera = false;
    await _acquire(camera: false);
  }

  Future<void> _acquire({required bool camera}) async {
    final revision = ++_revision;
    _pickerRevision = camera ? null : revision;
    phase = camera ? CameraSessionPhase.taking : CameraSessionPhase.selecting;
    error = null;
    problem = null;
    notifyListeners();
    try {
      if (!camera) unawaited(_close());
      if (!_valid(revision)) return;
      final bytes = camera
          ? await port.take().timeout(const Duration(seconds: 30))
          : await port.pick();
      if (!_valid(revision)) return;
      if (bytes == null) {
        phase = CameraSessionPhase.idle;
        notifyListeners();
        return;
      }
      phase = CameraSessionPhase.preparing;
      notifyListeners();
      final photo = await prepare(bytes).timeout(const Duration(seconds: 30));
      if (!_valid(revision)) return;
      unawaited(_close());
      if (!_valid(revision)) return;
      phase = CameraSessionPhase.idle;
      notifyListeners();
      onPhoto(photo, camera ? 'camera' : 'upload');
    } catch (failure) {
      if (!_valid(revision)) return;
      unawaited(_close());
      if (!_valid(revision)) return;
      _failure(failure, camera: camera);
      notifyListeners();
    }
  }

  void _failure(Object failure, {bool camera = true}) {
    phase = CameraSessionPhase.failed;
    problem = failure is CameraFailure
        ? failure.problem
        : camera
        ? CameraProblem.initialization
        : CameraProblem.selection;
    error = failure is PhotoPreparationException
        ? failure.message
        : switch (problem!) {
            CameraProblem.unavailable =>
              'A live camera is not available here. Choose an existing JPEG or PNG instead.',
            CameraProblem.denied =>
              'Camera permission was denied. You can try again or choose a photo.',
            CameraProblem.permanentlyDenied =>
              'Camera permission needs to be enabled in app settings. You can also choose a photo.',
            CameraProblem.restricted =>
              'Camera access is restricted by the device. Choose a photo if permitted.',
            CameraProblem.capture =>
              'The camera could not take a photo. Try again or choose a photo.',
            CameraProblem.selection =>
              'The photo picker could not open this file. Try a JPEG or PNG.',
            CameraProblem.initialization =>
              'The camera could not initialize. Try again or choose a photo.',
          };
  }

  void deviceFailed(CameraFailure failure) {
    if (_disposed || !allowed()) return;
    _revision++;
    _failure(failure);
    notifyListeners();
    unawaited(_close());
  }

  void suspend() {
    if (_disposed) return;
    // Picker/OS permission prompts also emit inactive; don't invalidate the
    // user-authorized chooser merely because its native dialog is foreground.
    if (awaitingPicker || phase == CameraSessionPhase.initializing) {
      return;
    }
    _revision++;
    phase = CameraSessionPhase.paused;
    notifyListeners();
    unawaited(_close());
  }

  void background({bool permissionOrDiscoveryPending = false}) {
    if (_disposed) return;
    backgrounded = true;
    // Android's document/photo picker can own a full-screen Activity. Retain
    // that explicit selection, never a camera feed or cross-session callback.
    if (awaitingPicker ||
        phase == CameraSessionPhase.initializing &&
            permissionOrDiscoveryPending) {
      return;
    }
    invalidate();
  }

  void foreground() {
    backgrounded = false;
  }

  void invalidate() {
    if (_disposed) return;
    _revision++;
    phase = CameraSessionPhase.paused;
    notifyListeners();
    unawaited(_close());
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    phase = CameraSessionPhase.disposed;
    unawaited(_close());
    super.dispose();
  }
}
