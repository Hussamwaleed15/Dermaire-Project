import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dermaire_app/capture/capture_controller.dart';
import 'package:dermaire_app/capture/capture_panel.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> response(
  String state, {
  String storage = 'not_persisted',
}) => {
  'id': 'server-capture',
  'state': state,
  'storage': storage,
  'provenance': {'quality': 'server_computed'},
  'quality': {
    'version': 'capture-quality-1.0',
    'decision': state,
    'reasons': state == 'rejected' ? ['Hold still and refocus.'] : <String>[],
  },
};

void main() {
  test(
    'capture upload uses quality endpoint, supported MIME and upload provenance',
    () async {
      await http.runWithClient(
        () async {
          final controller = CaptureController(
            ApiService.instance.submitCapture,
          );
          await controller.check(
            Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
            'private-location.png',
          );
          expect(controller.phase, CapturePhase.accepted);
          controller.dispose();
        },
        () => MockClient((request) async {
          final multipart = latin1.decode(request.bodyBytes);
          expect(request.url.path, '/api/v1/captures');
          expect(multipart, contains('image/png'));
          expect(multipart, contains('upload'));
          expect(multipart, isNot(contains('private-location')));
          expect(multipart, isNot(contains('hydration_score')));
          return http.Response(jsonEncode(response('accepted')), 201);
        }),
      );
    },
  );

  test('HTTP 503 cannot become accepted', () async {
    await http.runWithClient(
      () async {
        final controller = CaptureController(ApiService.instance.submitCapture);
        await controller.check(Uint8List(1), 'photo.jpg');
        expect(controller.phase, CapturePhase.failure);
        expect(controller.record, isNull);
        controller.dispose();
      },
      () => MockClient(
        (_) async => http.Response(jsonEncode(response('accepted')), 503),
      ),
    );
  });

  testWidgets('failure clears accepted UI and provides retry', (tester) async {
    var fail = false;
    final controller = CaptureController((_, _) async {
      if (fail) throw Exception('network');
      return response('accepted', storage: 'azure_blob');
    });
    await controller.check(Uint8List(1), 'photo.png');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CapturePanel(controller: controller)),
      ),
    );
    expect(find.textContaining('Image stored on the server'), findsOneWidget);
    fail = true;
    await controller.check(Uint8List(1), 'new.png');
    await tester.pump();
    expect(find.textContaining('Image stored on the server'), findsNothing);
    expect(
      find.textContaining('Quality could not be confirmed'),
      findsOneWidget,
    );
    expect(find.text('Retake / choose another photo'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  test('ready, checking, accepted require completed server response', () async {
    final request = Completer<Map<String, dynamic>>();
    final controller = CaptureController((_, _) => request.future);
    expect(controller.phase, CapturePhase.ready);
    final task = controller.check(Uint8List(1), 'photo.png');
    expect(controller.phase, CapturePhase.checking);
    expect(controller.record, isNull);
    request.complete(response('accepted'));
    await task;
    expect(controller.phase, CapturePhase.accepted);
    controller.dispose();
  });

  test('rejection exposes reasons and retake clears server state', () async {
    final controller = CaptureController((_, _) async => response('rejected'));
    await controller.check(Uint8List(1), 'photo.png');
    expect(controller.phase, CapturePhase.rejected);
    expect(controller.reasons, ['Hold still and refocus.']);
    controller.retake();
    expect(controller.phase, CapturePhase.ready);
    expect(controller.record, isNull);
    expect(controller.reasons, isEmpty);
    controller.dispose();
  });

  test(
    'network failure after acceptance cannot retain stale acceptance',
    () async {
      var calls = 0;
      final controller = CaptureController((_, _) async {
        if (++calls == 1) return response('accepted');
        throw Exception('network');
      });
      await controller.check(Uint8List(1), 'photo.png');
      await controller.check(Uint8List(1), 'new.png');
      expect(controller.phase, CapturePhase.failure);
      expect(controller.record, isNull);
      controller.dispose();
    },
  );

  for (final invalid in [
    <String, dynamic>{},
    {'state': 'accepted'},
    {
      ...response('accepted'),
      'provenance': {'quality': 'local'},
    },
    {...response('accepted'), 'state': 'rejected'},
  ]) {
    test('unconfirmed response is failure ${invalid.toString()}', () async {
      final controller = CaptureController((_, _) async => invalid);
      await controller.check(Uint8List(1), 'photo.png');
      expect(controller.phase, CapturePhase.failure);
      expect(controller.record, isNull);
      controller.dispose();
    });
  }

  test('late server result after retake is ignored', () async {
    final request = Completer<Map<String, dynamic>>();
    final controller = CaptureController((_, _) => request.future);
    final task = controller.check(Uint8List(1), 'photo.png');
    controller.retake();
    request.complete(response('accepted'));
    await task;
    expect(controller.phase, CapturePhase.ready);
    expect(controller.record, isNull);
    controller.dispose();
  });

  test('disposed controller ignores in-flight response', () async {
    final request = Completer<Map<String, dynamic>>();
    final controller = CaptureController((_, _) => request.future);
    final task = controller.check(Uint8List(1), 'photo.png');
    controller.dispose();
    request.complete(response('accepted'));
    await task;
  });

  testWidgets(
    'guidance, server states, rejection reasons, and retake are visible',
    (tester) async {
      final request = Completer<Map<String, dynamic>>();
      final controller = CaptureController((_, _) => request.future);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CapturePanel(controller: controller)),
        ),
      );
      expect(find.textContaining('Ready —'), findsOneWidget);
      expect(find.textContaining('No live camera analysis'), findsOneWidget);
      final task = controller.check(Uint8List(1), 'photo.png');
      await tester.pump();
      expect(find.textContaining('Checking quality'), findsOneWidget);
      request.complete(response('rejected'));
      await task;
      await tester.pump();
      expect(find.text('Hold still and refocus.'), findsOneWidget);
      expect(find.text('Retake / choose another photo'), findsOneWidget);
      controller.retake();
      await tester.pump();
      expect(find.textContaining('Ready —'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );

  testWidgets(
    'accepted metadata-only result explicitly states image not stored',
    (tester) async {
      final controller = CaptureController(
        (_, _) async => response('accepted'),
      );
      await controller.check(Uint8List(1), 'photo.png');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: CapturePanel(controller: controller)),
        ),
      );
      expect(find.textContaining('Image was not stored'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
