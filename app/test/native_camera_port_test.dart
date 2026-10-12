import 'dart:io';
import 'package:camera/camera.dart';
import 'package:dermaire_app/capture/camera_session.dart';
import 'package:dermaire_app/capture/native_camera_port.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'guided_capture_test.dart' as fixtures;

void main() {
  const channel = MethodChannel('plugins.flutter.io/camera');
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  var permission = 1;
  var inventory = true;
  String? failure;
  final calls = <MethodCall>[];
  File? temporary;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    permission = 1;
    inventory = true;
    failure = null;
    calls.clear();
    temporary = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(permissionChannel, (call) async {
      if (call.method == 'requestPermissions') {
        expect(call.arguments, [1]);
        return {1: permission};
      }
      if (call.method == 'openAppSettings') return true;
      throw StateError('Unexpected permission method');
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'availableCameras':
          return inventory
              ? [
                  {
                    'name': 'front',
                    'lensFacing': 'front',
                    'sensorOrientation': 0,
                  },
                ]
              : [];
        case 'create':
          if (failure != null) throw PlatformException(code: failure!);
          expect((call.arguments as Map)['enableAudio'], false);
          return {'cameraId': 0};
        case 'initialize':
          ServicesBinding.instance.channelBuffers.push(
            'flutter.io/cameraPlugin/camera0',
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('initialized', {
                'previewWidth': 480.0,
                'previewHeight': 640.0,
                'exposureMode': 'auto',
                'exposurePointSupported': true,
                'focusMode': 'auto',
                'focusPointSupported': true,
              }),
            ),
            (_) {},
          );
          return null;
        case 'takePicture':
          return temporary!.path;
        default:
          return null;
      }
    });
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(permissionChannel, null);
    if (temporary != null && await temporary!.exists()) {
      await temporary!.delete();
    }
  });
  test(
    'native camera uses actual plugin preview, portrait, flash off and no audio',
    () async {
      final port = NativeCameraPort();
      await port.initialize();
      expect(port.preview(), isA<CameraPreview>());
      expect(calls.any((c) => c.method == 'lockCaptureOrientation'), true);
      expect(
        calls.any(
          (c) =>
              c.method == 'setFlashMode' &&
              (c.arguments as Map)['mode'] == 'off',
        ),
        true,
      );
      await port.close();
      expect(calls.last.method, 'dispose');
    },
  );
  test(
    'camera-plugin temporary photo is read and deleted immediately',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'dermaire-synthetic-camera-',
      );
      addTearDown(() => dir.delete(recursive: true));
      temporary = File('${dir.path}/synthetic.png');
      await temporary!.writeAsBytes(fixtures.pngBytes());
      final port = NativeCameraPort();
      await port.initialize();
      final Uint8List bytes = await port.take();
      expect(bytes, fixtures.pngBytes());
      expect(await temporary!.exists(), false);
      await port.close();
    },
  );
  for (final status in [0, 2, 4]) {
    test('native permission status $status prevents camera creation', () async {
      permission = status;
      final port = NativeCameraPort();
      await expectLater(
        port.initialize(),
        throwsA(
          isA<CameraFailure>().having(
            (e) => e.problem,
            'problem',
            status == 4
                ? CameraProblem.permanentlyDenied
                : status == 2
                ? CameraProblem.restricted
                : CameraProblem.denied,
          ),
        ),
      );
      expect(calls.where((c) => c.method == 'create'), isEmpty);
      await port.close();
    });
  }
  test(
    'empty native camera inventory offers unsupported hardware state',
    () async {
      inventory = false;
      final port = NativeCameraPort();
      await expectLater(
        port.initialize(),
        throwsA(
          isA<CameraFailure>().having(
            (e) => e.problem,
            'problem',
            CameraProblem.unavailable,
          ),
        ),
      );
      await port.close();
    },
  );
  test(
    'desktop camera is unavailable before any native permission call',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final port = NativeCameraPort();
      await expectLater(port.initialize(), throwsA(isA<CameraFailure>()));
      expect(calls, isEmpty);
      await port.close();
    },
  );
  test(
    'native runtime error is mapped without exposing the private native description',
    () async {
      CameraFailure? failure;
      final port = NativeCameraPort(onFailure: (f) => failure = f);
      await port.initialize();
      ServicesBinding.instance.channelBuffers.push(
        'flutter.io/cameraPlugin/camera0',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('error', {
            'description': 'private-native-path-and-token',
          }),
        ),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(failure?.problem, CameraProblem.capture);
      await port.close();
    },
  );
  test(
    'native permanent denial error is mapped without exposing raw exception',
    () async {
      failure = 'CameraAccessDeniedWithoutPrompt';
      final port = NativeCameraPort();
      await expectLater(
        port.initialize(),
        throwsA(
          isA<CameraFailure>().having(
            (e) => e.problem,
            'problem',
            CameraProblem.permanentlyDenied,
          ),
        ),
      );
      try {
        await port.close();
      } catch (_) {
        /* Native creation itself failed. */
      }
    },
  );
}
