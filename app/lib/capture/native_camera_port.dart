import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'camera_session.dart';
import 'photo_preparation.dart';

CameraProblem cameraProblem(String code) => switch (code) {
  'CameraAccessDenied' => CameraProblem.denied,
  'CameraAccessDeniedWithoutPrompt' => CameraProblem.permanentlyDenied,
  'CameraAccessRestricted' => CameraProblem.restricted,
  _ => CameraProblem.initialization,
};
Future<Uint8List> readPhotoBytes(Stream<List<int>> stream) async {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in stream.timeout(const Duration(seconds: 20))) {
    if (buffer.length + chunk.length > maxPhotoBytes) {
      throw const PhotoPreparationException(
        'Choose a JPEG or PNG up to 8 MiB.',
      );
    }
    buffer.add(chunk);
  }
  return buffer.takeBytes();
}

class NativeCameraPort implements CameraPort {
  NativeCameraPort({this.onFailure, this.canInitialize});
  final void Function(CameraFailure)? onFailure;
  final bool Function()? canInitialize;
  bool get hardwareAllocated => _controller != null;
  CameraController? _controller;
  int _revision = 0;
  bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform);
  @override
  Future<void> initialize() async {
    if (!supported) throw const CameraFailure(CameraProblem.unavailable);
    final revision = ++_revision;
    try {
      final cameras = await availableCameras();
      if (canInitialize?.call() == false) {
        throw const CameraFailure(CameraProblem.initialization);
      }
      if (revision != _revision) {
        throw const CameraFailure(CameraProblem.initialization);
      }
      if (cameras.isEmpty) throw const CameraFailure(CameraProblem.unavailable);
      final permission = await Permission.camera.request();
      if (revision != _revision) {
        throw const CameraFailure(CameraProblem.initialization);
      }
      if (!permission.isGranted) {
        throw CameraFailure(
          permission.isPermanentlyDenied
              ? CameraProblem.permanentlyDenied
              : permission.isRestricted
              ? CameraProblem.restricted
              : CameraProblem.denied,
        );
      }
      if (canInitialize?.call() == false) {
        throw const CameraFailure(CameraProblem.initialization);
      }
      final lens = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        lens,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _controller = controller;
      controller.addListener(() {
        if (revision == _revision && controller.value.hasError) {
          onFailure?.call(const CameraFailure(CameraProblem.capture));
        }
      });
      await controller.initialize();
      if (revision != _revision) {
        await controller.dispose();
        return;
      }
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {
        /* Some front cameras have no flash. */
      }
    } on CameraException catch (e) {
      throw CameraFailure(cameraProblem(e.code));
    }
  }

  @override
  Widget preview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: Text('Camera preview unavailable'));
    }
    return CameraPreview(controller);
  }

  @override
  Future<Uint8List> take() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraFailure(CameraProblem.capture);
    }
    try {
      final file = await controller.takePicture();
      try {
        return await readPhotoBytes(file.openRead());
      } finally {
        // Only camera-plugin-created cache files, never a picker/original file.
        final temporary = File(file.path);
        if (await temporary.exists()) await temporary.delete();
      }
    } on CameraException {
      throw const CameraFailure(CameraProblem.capture);
    }
  }

  @override
  Future<Uint8List?> pick() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (file == null) return null;
      return await readPhotoBytes(file.readAsByteStream());
    } finally {
      // Native provider source files are never deleted by the app.
      try {
        await FilePicker.clearTemporaryFiles();
      } catch (_) {
        /* No picker cache API on some platforms. */
      }
    }
  }

  @override
  Future<void> close() async {
    _revision++;
    final old = _controller;
    _controller = null;
    if (old != null) await old.dispose();
  }

  @override
  Future<bool> settings() => openAppSettings();
}
