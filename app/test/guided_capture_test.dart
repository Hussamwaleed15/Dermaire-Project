import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/capture/camera_session.dart';
import 'package:dermaire_app/capture/native_camera_port.dart';
import 'package:dermaire_app/capture/photo_preparation.dart';
import 'package:dermaire_app/capture/guided_capture_models.dart';
import 'package:dermaire_app/capture/guided_capture_controller.dart';
import 'package:dermaire_app/capture/guided_camera_screen.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'observation_test.dart' as o;
import 'clinical_status_test.dart' as c;

final api = ApiService.instance;
Uint8List pngBytes({int width = 32, int height = 40, int channels = 3}) => img
    .encodePng(img.Image(width: width, height: height, numChannels: channels));
PreparedPhoto sample() => preparePhotoSync(pngBytes());
Map<String, dynamic> quality({
  String state = 'accepted',
  String source = 'camera',
  PreparedPhoto? photo,
}) => {
  'version': 'capture-quality-1.0',
  'decision': state,
  'request_fingerprint': (photo ?? sample()).requestFingerprint(source),
  'reasons': state == 'rejected' ? ['Hold still and refocus.'] : [],
  'limitations': [
    'Heuristic quality screen, not proof of comparability.',
    'Yaw, pitch and uneven lighting remain unknown.',
  ],
  'checks': {
    for (final key in [
      'resolution',
      'orientation',
      'face',
      'framing',
      'scale',
      'roll',
      'coarse_front_view',
      'sharpness',
      'exposure',
      'yaw',
      'pitch',
      'occlusion',
      'uneven_lighting',
    ])
      key: {
        'status': state == 'rejected' && key == 'sharpness'
            ? 'fail'
            : ['yaw', 'pitch', 'occlusion', 'uneven_lighting'].contains(key)
            ? 'unknown'
            : 'pass',
        'confidence':
            ['yaw', 'pitch', 'occlusion', 'uneven_lighting'].contains(key)
            ? 'unavailable'
            : key == 'resolution'
            ? 'measured'
            : 'heuristic',
        'metrics': {},
        'reason': key == 'sharpness' && state == 'rejected'
            ? 'Hold still and refocus.'
            : null,
      },
  },
};
Map<String, dynamic> measurement({
  String source = 'camera',
  PreparedPhoto? photo,
  String id = 'capture-id',
  String status = 'measured',
}) => {
  'id': 'measurement-id',
  'capture_id': id,
  'algorithm_version': 'measurement-1.0',
  'status': status,
  'measured_at': '2026-10-12T14:01:00Z',
  'provenance': status == 'unavailable'
      ? 'server_recorded_unavailability'
      : 'server_computed_from_upload_bytes',
  'capture_quality': quality(source: source, photo: photo),
  'metrics': {
    for (final key in ['red_chromaticity_proxy', 'texture_contrast_proxy'])
      key: {
        'key': key,
        'value': status == 'measured'
            ? (key == 'red_chromaticity_proxy' ? 0.351 : 0.041)
            : null,
        'unit': 'fraction_0_to_1',
        'status': status,
        'reliability': status == 'measured'
            ? 'limited_image_proxy'
            : 'unavailable',
        'method_version': 'measurement-1.0',
        'source_capture_id': id,
        'region': 'fixed_bilateral_cheek_rectangles_from_frontal_face_detector',
        'measured_at': '2026-10-12T14:01:00Z',
        'limitations': [
          'Lighting and camera processing affect these nonclinical estimates.',
        ],
      },
  },
};
Map<String, dynamic> receipt({
  String owner = 'a',
  String id = 'capture-id',
  String state = 'accepted',
  bool stored = true,
  String source = 'camera',
  PreparedPhoto? photo,
  bool inline = true,
}) => {
  'id': id,
  'state': state,
  'source': source,
  'view': 'front',
  'received_at': '2026-10-12T14:00:00+00:00',
  'storage': stored && state == 'accepted' ? 'azure_blob' : 'not_persisted',
  'image_reference': stored && state == 'accepted'
      ? 'skin_photos/$owner/${owner}_synthetic.png'
      : null,
  'quality': quality(state: state, source: source, photo: photo),
  'provenance': {
    'timestamp': 'server_received_not_camera_time',
    'source': 'client_reported',
    'view': 'client_reported',
    'quality': 'server_computed',
    'server_version': 'synthetic-version',
  },
  if (state == 'accepted' && inline)
    'measurement': measurement(id: id, source: source, photo: photo),
};

class FakePort implements CameraPort {
  CameraProblem? problem;
  int starts = 0, takes = 0, picks = 0, closes = 0, settingsCalls = 0;
  Uint8List? chosen = pngBytes();
  Completer<void>? initialization;
  Completer<void>? closing;
  Completer<Uint8List>? taking;
  Completer<Uint8List?>? picking;
  @override
  Future<void> initialize() async {
    starts++;
    if (problem != null) throw CameraFailure(problem!);
    if (initialization != null) await initialization!.future;
  }

  @override
  Widget preview() => const Text('Synthetic camera frame');
  @override
  Future<Uint8List> take() async {
    takes++;
    return taking?.future ?? pngBytes();
  }

  @override
  Future<Uint8List?> pick() async {
    picks++;
    return picking?.future ?? chosen;
  }

  @override
  Future<void> close() async {
    closes++;
    if (closing != null) await closing!.future;
  }

  @override
  Future<bool> settings() async {
    settingsCalls++;
    return true;
  }
}

class Fixture {
  final camera = FakePort();
  String owner = 'a';
  int posts = 0;
  int status = 201;
  int ttl = 3600;
  bool offline = false;
  String resultState = 'accepted';
  bool inline = true, broken = false;
  Completer<http.Response>? pending;
  PreparedPhoto photo = sample();
  String source = 'camera';
  Map<String, dynamic>? readback;
  final paths = <String>[];
  late final state = DermaireState();
  GuidedCaptureController get capture => state.guidedCapture;
  Future<void> login() async {
    await o.login(owner);
    await state.account.hydrate();
    capture.begin(api.sessionGeneration);
  }

  Future<http.Response> transport(http.Request r) async {
    paths.add(r.url.path);
    if (r.url.path.endsWith('/auth/login')) return o.auth(owner, ttl: ttl);
    if (r.url.path.endsWith('/users/me')) return o.user(owner);
    if (r.url.path.endsWith('/auth/logout')) return o.jsonResponse({});
    if (r.url.path.endsWith('/safety')) {
      return o.jsonResponse(c.safety(status: 'urgent'));
    }
    if (r.url.path.endsWith('/doctor/review-status')) {
      return o.jsonResponse(c.review(owner: owner));
    }
    if (r.url.path.endsWith('/captures') && r.method == 'POST') {
      posts++;
      expectSync(r.headers['Authorization'], 'Bearer reused-synthetic-token');
      expectSync(
        r.headers['Idempotency-Key'],
        matches(RegExp(r'^[a-f0-9]{32}$')),
      );
      final multipart = latin1.decode(r.bodyBytes);
      expectSync(multipart, contains('filename="capture.png"'));
      expectSync(multipart, contains('image/png'));
      expectSync(multipart, isNot(contains('private-location')));
      expectSync(multipart, isNot(contains('hydration_score')));
      if (offline) throw http.ClientException('Synthetic offline');
      if (pending != null) return pending!.future;
      final data = receipt(
        owner: owner,
        source: source,
        photo: photo,
        state: resultState,
        inline: inline,
      );
      if (broken) {
        data['quality'] = {...data['quality'] as Map, 'checks': 'malformed'};
      }
      return o.jsonResponse(data, status);
    }
    if (r.url.path.endsWith('/captures/capture-id')) {
      return o.jsonResponse(
        readback ??
            receipt(owner: owner, source: source, photo: photo, inline: false),
      );
    }
    if (r.url.path.endsWith('/measurements/capture-id')) {
      return o.jsonResponse(measurement(source: source, photo: photo));
    }
    throw StateError('Unexpected fixture path ${r.url.path}');
  }

  void choose() =>
      capture.select(photo, source, generation: api.sessionGeneration);
  Future<void> done([WidgetTester? t]) async {
    if (t != null) await t.pumpWidget(const SizedBox());
    state.dispose();
    await api.init();
  }
}

Future<void> mount(
  WidgetTester t,
  Fixture f, {
  bool dark = false,
  bool reduced = false,
  double scale = 1,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? DermaireTheme.dark : DermaireTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduced,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: GuidedCameraScreen(
        state: f.state,
        cameraPort: f.camera,
        prepare: (b) async => preparePhotoSync(b),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);
  await t.pumpAndSettle();
}

void main() {
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final problem in CameraProblem.values) {
    test(
      'camera problem $problem has honest failure and picker remains available',
      () async {
        final port = FakePort()..problem = problem;
        PreparedPhoto? selected;
        final session = CameraSession(
          port,
          allowed: () => true,
          onPhoto: (p, source) => selected = p,
          prepare: (b) async => preparePhotoSync(b),
        );
        await session.start();
        expect(session.phase, CameraSessionPhase.failed);
        expect(session.problem, problem);
        expect(session.error, isNotEmpty);
        await session.pick();
        expect(selected, isNotNull);
        expect(port.picks, 1);
        session.dispose();
      },
    );
  }
  test(
    'camera initializes, captures once and prepares a local review only',
    () async {
      final port = FakePort();
      var photos = 0;
      String? source;
      final session = CameraSession(
        port,
        allowed: () => true,
        onPhoto: (p, s) {
          photos++;
          source = s;
        },
        prepare: (b) async => preparePhotoSync(b),
      );
      await session.start();
      expect(session.phase, CameraSessionPhase.live);
      port.taking = Completer();
      final taking = session.take();
      await Future<void>.delayed(Duration.zero);
      await session.take();
      expect(port.takes, 1);
      port.taking!.complete(pngBytes());
      await taking;
      expect(photos, 1);
      expect(source, 'camera');
      expect(port.closes, greaterThan(0));
      session.dispose();
    },
  );
  test(
    'cancelled picker sends no photo and inactive native dialog does not discard selection',
    () async {
      final port = FakePort()..picking = Completer();
      var photos = 0;
      final session = CameraSession(
        port,
        allowed: () => true,
        onPhoto: (p, s) => photos++,
        prepare: (b) async => preparePhotoSync(b),
      );
      final pick = session.pick();
      await Future<void>.delayed(Duration.zero);
      session.suspend();
      expect(session.phase, CameraSessionPhase.selecting);
      port.picking!.complete(null);
      await pick;
      expect(photos, 0);
      expect(session.phase, CameraSessionPhase.idle);
      session.dispose();
    },
  );
  for (final operation in ['initialize', 'take', 'pick', 'prepare']) {
    test(
      'background/disposal invalidates late $operation without new private preview',
      () async {
        final port = FakePort();
        var allowed = true, photos = 0;
        final prepared = Completer<PreparedPhoto>();
        final session = CameraSession(
          port,
          allowed: () => allowed,
          onPhoto: (p, s) => photos++,
          prepare: operation == 'prepare'
              ? (b) => prepared.future
              : (b) async => preparePhotoSync(b),
        );
        Future<void> task;
        switch (operation) {
          case 'initialize':
            port.initialization = Completer();
            task = session.start();
          case 'take':
            await session.start();
            port.taking = Completer();
            task = session.take();
          case 'pick':
            port.picking = Completer();
            task = session.pick();
          default:
            task = session.pick();
        }
        await Future<void>.delayed(Duration.zero);
        allowed = false;
        session.invalidate();
        switch (operation) {
          case 'initialize':
            port.initialization!.complete();
          case 'take':
            port.taking!.complete(pngBytes());
          case 'pick':
            port.picking!.complete(pngBytes());
          default:
            prepared.complete(sample());
        }
        await task;
        expect(photos, 0);
        expect(session.phase, CameraSessionPhase.paused);
        expect(port.closes, greaterThan(0));
        session.dispose();
      },
    );
  }
  for (final code in [
    'CameraAccessDenied',
    'CameraAccessDeniedWithoutPrompt',
    'CameraAccessRestricted',
    'unknown',
  ]) {
    test('native camera exception $code maps accurately', () {
      expect(cameraProblem(code), switch (code) {
        'CameraAccessDenied' => CameraProblem.denied,
        'CameraAccessDeniedWithoutPrompt' => CameraProblem.permanentlyDenied,
        'CameraAccessRestricted' => CameraProblem.restricted,
        _ => CameraProblem.initialization,
      });
    });
  }
  test('bounded stream rejects excess before any downstream decode', () async {
    await expectLater(
      readPhotoBytes(Stream.value(Uint8List(maxPhotoBytes + 1))),
      throwsA(isA<PhotoPreparationException>()),
    );
  });
  for (final failure in [
    'unsupported',
    'oversized',
    'corrupt',
    'alpha',
    'animated',
  ]) {
    test('photo preparation rejects $failure locally without a POST', () {
      final Uint8List bytes = switch (failure) {
        'unsupported' => Uint8List.fromList('GIF89a'.codeUnits),
        'oversized' => Uint8List(maxPhotoBytes + 1),
        'corrupt' => Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        'alpha' => pngBytes(channels: 4),
        _ => _animated(),
      };
      expect(
        () => preparePhotoSync(bytes),
        throwsA(isA<PhotoPreparationException>()),
      );
    });
  }
  test(
    'PNG pixels are preserved; JPEG metadata removed without recompressing normal orientation',
    () {
      final png = pngBytes();
      expect(preparePhotoSync(png).bytes, png);
      final pixels = img.Image(width: 40, height: 50)
        ..exif.imageIfd.imageDescription = 'private-location-name';
      final original = img.encodeJpg(pixels);
      final prepared = preparePhotoSync(original);
      expect(
        latin1.decode(prepared.bytes),
        isNot(contains('private-location-name')),
      );
      expect(
        img.decodeJpg(prepared.bytes)!.getBytes(),
        img.decodeJpg(original)!.getBytes(),
      );
    },
  );
  for (final orientation in [0, 6, 9]) {
    test('JPEG orientation $orientation is applied or rejected honestly', () {
      final image = img.Image(width: 50, height: 40)
        ..exif.imageIfd.orientation = orientation;
      final bytes = img.encodeJpg(image);
      if (orientation != 6) {
        expect(
          () => preparePhotoSync(bytes),
          throwsA(isA<PhotoPreparationException>()),
        );
      } else {
        final photo = preparePhotoSync(bytes);
        expect(photo.width, 40);
        expect(photo.height, 50);
        expect(img.decodeJpg(photo.bytes)!.exif.imageIfd.hasOrientation, false);
      }
    });
  }
  for (final state in ['accepted', 'rejected']) {
    test(
      'record $state preserves server storage/time/quality and no diagnosis',
      () {
        final data = receipt(state: state);
        final record = GuidedCaptureRecord.fromApi(data, owner: 'a');
        expect(record.state, state);
        expect(record.stored, state == 'accepted');
        expect(record.receivedAt.toIso8601String(), '2026-10-12T14:00:00.000Z');
        expect(record.quality.checks['yaw']!.status, 'unknown');
        expect(record.quality.supported, true);
      },
    );
  }
  for (final invalid in [
    'owner',
    'timestamp',
    'provenance',
    'decision',
    'stored_rejection',
    'invalid_id',
    'contradictory_quality',
  ]) {
    test(
      'capture contract rejects $invalid rather than fabricate confirmed storage',
      () {
        final data = receipt();
        switch (invalid) {
          case 'owner':
            data['image_reference'] = 'skin_photos/b/b_private.png';
          case 'timestamp':
            data['received_at'] = '2026-02-31T10:00:00Z';
          case 'provenance':
            data['provenance'] = {
              ...data['provenance'] as Map,
              'quality': 'local',
            };
          case 'decision':
            data['state'] = 'rejected';
          case 'stored_rejection':
            data['quality'] = quality(state: 'rejected');
            data['state'] = 'rejected';
          case 'invalid_id':
            data['id'] = '../foreign';
          case 'contradictory_quality':
            ((data['quality'] as Map)['checks'] as Map)['resolution'] = {
              'status': 'fail',
              'confidence': 'measured',
              'reason': 'Too small',
            };
        }
        expect(
          () => GuidedCaptureRecord.fromApi(data, owner: 'a'),
          throwsFormatException,
        );
      },
    );
  }
  for (final status in [
    'measured',
    'insufficient_quality',
    'unavailable',
    'failed',
  ]) {
    test('proxy state $status does not fill unavailable values with zero', () {
      final parsed = CaptureMeasurement.fromApi(
        measurement(status: status),
        captureId: 'capture-id',
      );
      expect(parsed.status, status);
      expect(
        parsed.metrics.values.first.value,
        status == 'measured' ? 0.351 : null,
      );
      expect(parsed.metrics.values.first.unit, 'fraction_0_to_1');
    });
  }
  for (final invalid in [
    'foreign_capture',
    'value',
    'unit',
    'method',
    'missing',
  ]) {
    test(
      'bad optional measurement $invalid does not revoke a confirmed capture or show fake numbers',
      () {
        final data = receipt();
        final m = data['measurement'] as Map;
        final metric = (m['metrics'] as Map)['red_chromaticity_proxy'] as Map;
        switch (invalid) {
          case 'foreign_capture':
            m['capture_id'] = 'foreign';
          case 'value':
            metric['value'] = double.infinity;
          case 'unit':
            metric['unit'] = 'clinical_percent';
          case 'method':
            metric['method_version'] = 'future';
          default:
            (m['metrics'] as Map).remove('red_chromaticity_proxy');
        }
        final parsed = GuidedCaptureRecord.fromApi(data, owner: 'a');
        expect(parsed.state, 'accepted');
        expect(parsed.measurement, isNull);
        expect(parsed.measurementUnavailable, true);
      },
    );
  }
  test('unknown quality version is explicit rather than a verified pass', () {
    final data = receipt();
    (data['quality'] as Map)['version'] = 'future-quality';
    final record = GuidedCaptureRecord.fromApi(data, owner: 'a');
    expect(record.quality.supported, false);
  });
  test(
    'review then explicit authenticated upload uses source, MIME, stable key and server proof',
    () async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        expect(f.posts, 0);
        expect(f.capture.phase, GuidedCapturePhase.review);
        expect(await f.capture.upload(generation: api.sessionGeneration), true);
        expect(f.posts, 1);
        expect(f.capture.record!.stored, true);
        expect(
          f.capture.measurement!.metrics['red_chromaticity_proxy']!.value,
          0.351,
        );
        expect(f.state.home.current, isNull);
        expect(f.state.baseline.completedDays, isNull);
        expect(f.paths.where((p) => p.endsWith('/checkins')), isEmpty);
        await f.done();
      }, () => o.isolated(f.transport));
    },
  );
  for (final status in [400, 403, 409, 413, 415, 422, 503]) {
    test(
      'HTTP $status differentiates rejected request and uncertain persistence',
      () async {
        final f = Fixture()..status = status;
        await http.runWithClient(() async {
          await f.login();
          f.choose();
          expect(
            await f.capture.upload(generation: api.sessionGeneration),
            false,
          );
          expect(
            f.capture.phase,
            status == 503
                ? GuidedCapturePhase.uncertain
                : GuidedCapturePhase.rejected,
          );
          expect(f.capture.record, isNull);
          expect(
            await f.capture.upload(generation: api.sessionGeneration),
            false,
          );
          expect(f.posts, 1);
          await f.done();
        }, () => o.isolated(f.transport));
      },
    );
  }
  test(
    'offline upload remains unknown with no automatic resend on reopen or reset',
    () async {
      final f = Fixture()..offline = true;
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        await f.capture.upload(generation: api.sessionGeneration);
        expect(f.capture.phase, GuidedCapturePhase.uncertain);
        f.capture.begin(api.sessionGeneration);
        f.capture.reset(generation: api.sessionGeneration);
        expect(f.capture.phase, GuidedCapturePhase.uncertain);
        expect(f.posts, 1);
        await f.done();
      }, () => o.isolated(f.transport));
    },
  );
  test(
    'malformed 201 can reconcile only exact server ID and image fingerprint via GET',
    () async {
      final f = Fixture()..broken = true;
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        await f.capture.upload(generation: api.sessionGeneration);
        expect(f.capture.phase, GuidedCapturePhase.uncertain);
        expect(f.capture.canReconcile, true);
        expect(
          await f.capture.reconcile(generation: api.sessionGeneration),
          true,
        );
        expect(f.capture.record!.readback, true);
        expect(f.posts, 1);
        await f.capture.refreshMeasurement(generation: api.sessionGeneration);
        expect(f.capture.measurement, isNotNull);
        expect(f.posts, 1);
        await f.done();
      }, () => o.isolated(f.transport));
    },
  );
  test('readback of different photo cannot confirm original upload', () async {
    final f = Fixture()..broken = true;
    f.readback = receipt(
      photo: preparePhotoSync(pngBytes(width: 30, height: 45)),
      inline: false,
    );
    await http.runWithClient(() async {
      await f.login();
      f.choose();
      await f.capture.upload(generation: api.sessionGeneration);
      expect(
        await f.capture.reconcile(generation: api.sessionGeneration),
        false,
      );
      expect(f.capture.phase, GuidedCapturePhase.uncertain);
      expect(f.posts, 1);
      await f.done();
    }, () => o.isolated(f.transport));
  });
  for (final end in ['logout', 'switch', 'old401', 'expiry']) {
    testWidgets(
      'late upload $end never displays or invalidates a newer account',
      (t) async {
        final f = Fixture()..pending = Completer();
        if (end == 'expiry') f.ttl = 1;
        await http.runWithClient(() async {
          await f.login();
          f.choose();
          final original = api.sessionGeneration;
          final waiting = f.capture.upload(generation: original);
          await t.pump();
          expect(f.posts, 1);
          if (end == 'switch' || end == 'old401') {
            f.owner = 'b';
            await f.login();
          } else if (end == 'expiry') {
            await t.pump(const Duration(seconds: 2));
          } else {
            await api.init();
          }
          f.pending!.complete(
            o.jsonResponse(receipt(owner: 'a'), end == 'old401' ? 401 : 201),
          );
          expect(await waiting, false);
          expect(f.capture.record, isNull);
          expect(f.capture.photo, isNull);
          if (end == 'switch' || end == 'old401') {
            expect(api.isAuthenticated, true);
            expect(api.observationOwner, 'b');
          }
          await f.done(t);
        }, () => o.isolated(f.transport));
      },
    );
  }
  testWidgets(
    'upload timeout, duplicate taps, late result and unknown state are honest',
    (t) async {
      final f = Fixture()..pending = Completer();
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        final waiting = f.capture.upload(generation: api.sessionGeneration);
        await t.pump();
        expect(
          await f.capture.upload(generation: api.sessionGeneration),
          false,
        );
        expect(f.posts, 1);
        await t.pump(const Duration(seconds: 61));
        expect(await waiting, false);
        expect(f.capture.phase, GuidedCapturePhase.uncertain);
        f.pending!.complete(o.jsonResponse(receipt()));
        await t.pump();
        expect(f.capture.record, isNull);
        expect(f.posts, 1);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'guided camera enters preview, reviews without upload, retakes and cancels',
    (t) async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.login();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('startLiveCamera')));
        await t.tap(find.byKey(const Key('startLiveCamera')));
        await t.pumpAndSettle();
        await reveal(t, find.byKey(const Key('cameraFramingGuide')));
        expect(find.text('Synthetic camera frame'), findsOneWidget);
        await reveal(t, find.byKey(const Key('takeGuidedPhoto')));
        await t.tap(find.byKey(const Key('takeGuidedPhoto')));
        await t.pumpAndSettle();
        expect(f.posts, 0);
        await reveal(t, find.byKey(const Key('localPhotoPreview')));
        expect(find.byKey(const Key('confirmCaptureUpload')), findsOneWidget);
        expect(
          t.getRect(find.text(guidedPhotoDisclosure)).bottom,
          lessThanOrEqualTo(
            t.getRect(find.byKey(const Key('confirmCaptureUpload'))).top,
          ),
        );
        await reveal(t, find.byKey(const Key('retakeCapture')));
        await t.tap(find.byKey(const Key('retakeCapture')));
        await t.pumpAndSettle();
        expect(f.camera.starts, 2);
        expect(f.capture.photo, isNull);
        expect(f.posts, 0);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets('permanent denial offers settings and honest gallery fallback', (
    t,
  ) async {
    final f = Fixture();
    f.camera.problem = CameraProblem.permanentlyDenied;
    await http.runWithClient(() async {
      await f.login();
      await mount(t, f);
      await reveal(t, find.byKey(const Key('startLiveCamera')));
      await t.tap(find.byKey(const Key('startLiveCamera')));
      await t.pumpAndSettle();
      await reveal(t, find.byKey(const Key('cameraSettings')));
      await t.tap(find.byKey(const Key('cameraSettings')));
      await t.pumpAndSettle();
      expect(f.camera.settingsCalls, 1);
      await reveal(t, find.byKey(const Key('chooseGuidedPhoto')));
      await t.tap(find.byKey(const Key('chooseGuidedPhoto')));
      await t.pumpAndSettle();
      expect(f.capture.photo, isNotNull);
      expect(f.posts, 0);
      await f.done(t);
    }, () => o.isolated(f.transport));
  });
  for (final stored in [true, false]) {
    testWidgets(
      'result stored=$stored retains urgent safety and actual nonclinical proxies',
      (t) async {
        final f = Fixture();
        await http.runWithClient(
          () async {
            await f.login();
            f.choose();
            await f.capture.upload(generation: api.sessionGeneration);
            await mount(t, f);
            expect(
              find.text('Urgent medical assessment recommended'),
              findsOneWidget,
            );
            await reveal(t, find.text('Server-confirmed capture result'));
            expect(
              find.text('Received by server: 2026-10-12 14:00:00 UTC'),
              findsOneWidget,
            );
            await reveal(t, find.text('Nonclinical image estimates'));
            expect(
              find.text('0.351 · fraction_0_to_1 · Limited image proxy'),
              findsOneWidget,
            );
            expect(find.textContaining('diagnosis complete'), findsNothing);
            expect(f.state.todayCheckedIn, false);
            await f.done(t);
          },
          () => o.isolated((r) async {
            if (r.url.path.endsWith('/captures') && r.method == 'POST') {
              f.posts++;
              return o.jsonResponse(receipt(stored: stored), 201);
            }
            return f.transport(r);
          }),
        );
      },
    );
  }

  test('16 megapixel header is rejected before any decompression', () {
    final bytes = Uint8List.fromList(pngBytes(width: 1, height: 1));
    final header = ByteData.sublistView(bytes);
    header.setUint32(16, 4001);
    header.setUint32(20, 4000);
    header.setUint32(29, _crc32(bytes.sublist(12, 29)));
    expect(
      () => preparePhotoSync(bytes),
      throwsA(
        isA<PhotoPreparationException>().having(
          (e) => e.message,
          'message',
          contains('16 megapixels'),
        ),
      ),
    );
  });
  test('PNG EXIF orientation is applied before metadata is removed', () {
    final bytes = pngBytes(width: 50, height: 40);
    final tiff = Uint8List.fromList([
      73,
      73,
      42,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
      18,
      1,
      3,
      0,
      1,
      0,
      0,
      0,
      6,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
    final body = Uint8List.fromList([...ascii.encode('eXif'), ...tiff]);
    final chunk = ByteData(12 + tiff.length)
      ..setUint32(0, tiff.length)
      ..setUint32(8 + tiff.length, _crc32(body));
    chunk.buffer.asUint8List().setRange(4, 8 + tiff.length, body);
    final withExif = Uint8List.fromList([
      ...bytes.sublist(0, 33),
      ...chunk.buffer.asUint8List(),
      ...bytes.sublist(33),
    ]);
    final prepared = preparePhotoSync(withExif);
    expect(prepared.width, 40);
    expect(prepared.height, 50);
    expect(latin1.decode(prepared.bytes), isNot(contains('eXif')));
  });
  test(
    'preparation isolate returns the same immutable compatible photo',
    () async {
      final photo = await preparePhoto(pngBytes());
      expect(photo.bytes, sample().bytes);
      expect(() => photo.bytes[0] = 0, throwsUnsupportedError);
    },
  );
  test(
    'malformed TIFF is rejected rather than silently inventing orientation',
    () {
      final pixels = img.Image(width: 40, height: 50)
        ..exif.imageIfd.orientation = 6;
      final bytes = Uint8List.fromList(img.encodeJpg(pixels));
      final index = latin1.decode(bytes).indexOf('Exif');
      expect(index, greaterThan(0));
      bytes[index + 6] = 0;
      expect(
        () => preparePhotoSync(bytes),
        throwsA(isA<PhotoPreparationException>()),
      );
    },
  );
  for (final invalid in ['fingerprint', 'time']) {
    test(
      'optional proxy $invalid mismatch stays unavailable with capture confirmed',
      () {
        final data = receipt();
        final m = data['measurement'] as Map;
        if (invalid == 'fingerprint') {
          (m['capture_quality'] as Map)['request_fingerprint'] = 'f' * 64;
        } else {
          ((m['metrics'] as Map)['red_chromaticity_proxy']
                  as Map)['measured_at'] =
              '2026-10-12T15:00:00Z';
        }
        final record = GuidedCaptureRecord.fromApi(data, owner: 'a');
        expect(record.state, 'accepted');
        expect(record.measurement, isNull);
        expect(record.measurementUnavailable, true);
      },
    );
  }
  test(
    'current upload 401 ends the session and clears private photo/result',
    () async {
      final f = Fixture()..status = 401;
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        expect(
          await f.capture.upload(generation: api.sessionGeneration),
          false,
        );
        expect(api.isAuthenticated, false);
        expect(f.capture.photo, isNull);
        expect(f.capture.record, isNull);
        expect(f.capture.phase, GuidedCapturePhase.ended);
        await f.done();
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'initialization timeout releases requested camera and gallery does not await hung disposal',
    (t) async {
      final port = FakePort()
        ..initialization = Completer()
        ..closing = Completer();
      var photos = 0;
      final camera = CameraSession(
        port,
        allowed: () => true,
        onPhoto: (p, s) => photos++,
        prepare: (b) async => preparePhotoSync(b),
      );
      final starting = camera.start();
      await t.pump(const Duration(seconds: 21));
      await starting;
      expect(camera.phase, CameraSessionPhase.failed);
      await camera.pick();
      expect(photos, 1);
      expect(port.closes, greaterThan(0));
      port.initialization!.complete();
      port.closing!.complete();
      camera.dispose();
      await t.pump();
    },
  );
  testWidgets('photo preparation timeout cannot yield a late preview', (
    t,
  ) async {
    final prepared = Completer<PreparedPhoto>();
    var photos = 0;
    final camera = CameraSession(
      FakePort(),
      allowed: () => true,
      onPhoto: (p, s) => photos++,
      prepare: (b) => prepared.future,
    );
    final picking = camera.pick();
    await t.pump();
    expect(camera.phase, CameraSessionPhase.preparing);
    await t.pump(const Duration(seconds: 31));
    await picking;
    expect(camera.phase, CameraSessionPhase.failed);
    prepared.complete(sample());
    await t.pump();
    expect(photos, 0);
    camera.dispose();
  });
  testWidgets(
    'record readback timeout preserves uncertainty and retries only GET',
    (t) async {
      final f = Fixture()..broken = true;
      final pending = Completer<http.Response>();
      var hold = true;
      await http.runWithClient(
        () async {
          await f.login();
          f.choose();
          await f.capture.upload(generation: api.sessionGeneration);
          final reading = f.capture.reconcile(
            generation: api.sessionGeneration,
          );
          await t.pump(const Duration(seconds: 21));
          expect(await reading, false);
          expect(f.capture.phase, GuidedCapturePhase.uncertain);
          expect(f.posts, 1);
          hold = false;
          expect(
            await f.capture.reconcile(generation: api.sessionGeneration),
            true,
          );
          pending.complete(o.jsonResponse(receipt()));
          await t.pump();
          expect(f.posts, 1);
          await f.done(t);
        },
        () => o.isolated((r) async {
          if (hold && r.url.path.endsWith('/captures/capture-id')) {
            return pending.future;
          }
          return f.transport(r);
        }),
      );
    },
  );
  testWidgets(
    'old readback after switch cannot reveal a previous account record',
    (t) async {
      final f = Fixture()..broken = true;
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await f.login();
          f.choose();
          await f.capture.upload(generation: api.sessionGeneration);
          final reading = f.capture.reconcile(
            generation: api.sessionGeneration,
          );
          await t.pump();
          f.owner = 'b';
          await f.login();
          pending.complete(o.jsonResponse(receipt(owner: 'a')));
          expect(await reading, false);
          expect(f.capture.record, isNull);
          expect(f.capture.photo, isNull);
          expect(api.observationOwner, 'b');
          await f.done(t);
        },
        () => o.isolated((r) async {
          if (r.url.path.endsWith('/captures/capture-id')) {
            return pending.future;
          }
          return f.transport(r);
        }),
      );
    },
  );
  testWidgets(
    'unknown outcome needs explicit separate-attempt acknowledgement; no automatic upload',
    (t) async {
      final f = Fixture()..offline = true;
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        await f.capture.upload(generation: api.sessionGeneration);
        await mount(t, f);
        await reveal(t, find.byKey(const Key('anotherCapture')));
        await t.tap(find.byKey(const Key('anotherCapture')));
        await t.pumpAndSettle();
        expect(find.text('Start a separate capture?'), findsOneWidget);
        await t.tap(find.text('Keep current attempt'));
        await t.pumpAndSettle();
        expect(f.capture.phase, GuidedCapturePhase.uncertain);
        expect(f.posts, 1);
        await reveal(t, find.byKey(const Key('anotherCapture')));
        await t.tap(find.byKey(const Key('anotherCapture')));
        await t.pumpAndSettle();
        await t.tap(find.text('Start separate capture'));
        await t.pumpAndSettle();
        expect(f.capture.phase, GuidedCapturePhase.ready);
        expect(f.posts, 1);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets('discarding a local preview never transmits a photo', (t) async {
    final f = Fixture();
    await http.runWithClient(() async {
      await f.login();
      f.choose();
      await mount(t, f);
      await reveal(t, find.byKey(const Key('cancelPhoto')));
      await t.tap(find.byKey(const Key('cancelPhoto')));
      await t.pumpAndSettle();
      expect(f.capture.photo, isNull);
      expect(f.posts, 0);
      expect(f.capture.phase, GuidedCapturePhase.ready);
      await f.done(t);
    }, () => o.isolated(f.transport));
  });
  testWidgets(
    'real official observation entry reaches guided flow and returns without upload',
    (t) async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.login();
        await t.pumpWidget(MaterialApp(home: CameraScreen(state: f.state)));
        await t.pumpAndSettle();
        await reveal(t, find.text('Photo quality check — separate'));
        await t.tap(find.text('Photo quality check — separate'));
        await t.pumpAndSettle();
        await reveal(t, find.byKey(const Key('openGuidedCamera')));
        await t.tap(find.byKey(const Key('openGuidedCamera')));
        await t.pumpAndSettle();
        expect(find.byType(GuidedCameraScreen), findsOneWidget);
        await reveal(t, find.byKey(const Key('captureCancelBack')));
        await t.tap(find.byKey(const Key('captureCancelBack')));
        await t.pumpAndSettle();
        expect(find.byType(CameraScreen), findsOneWidget);
        expect(f.posts, 0);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'reopening during in-flight upload preserves one attempt and exposes eventual receipt',
    (t) async {
      final f = Fixture()..pending = Completer();
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        final waiting = f.capture.upload(generation: api.sessionGeneration);
        await t.pump();
        f.capture.releasePreview(generation: api.sessionGeneration);
        f.capture.begin(api.sessionGeneration);
        expect(f.capture.photo, isNull);
        expect(f.capture.phase, GuidedCapturePhase.uploading);
        expect(
          await f.capture.upload(generation: api.sessionGeneration),
          false,
        );
        f.pending!.complete(o.jsonResponse(receipt(), 201));
        expect(await waiting, true);
        expect(f.capture.record!.id, 'capture-id');
        expect(f.posts, 1);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'camera background/resume reopens only after an explicit camera request',
    (t) async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.login();
        await mount(t, f);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(f.camera.starts, 0);
        await reveal(t, find.byKey(const Key('startLiveCamera')));
        await t.tap(find.byKey(const Key('startLiveCamera')));
        await t.pumpAndSettle();
        expect(f.camera.starts, 1);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(f.camera.starts, 2);
        expect(f.camera.closes, greaterThan(0));
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'retained upload callback cannot send after logout or reveal previous preview',
    (t) async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('confirmCaptureUpload')));
        final callback = t
            .widget<FilledButton>(find.byKey(const Key('confirmCaptureUpload')))
            .onPressed!;
        await api.init();
        callback();
        await t.pumpAndSettle();
        expect(f.posts, 0);
        expect(find.byKey(const Key('localPhotoPreview')), findsNothing);
        expect(f.capture.record, isNull);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  test(
    'request fingerprint matches the independently computed backend capture-v1 encoding',
    () {
      final photo = PreparedPhoto(
        Uint8List.fromList([1, 2, 3]),
        'image/jpeg',
        1,
        1,
      );
      expect(
        photo.requestFingerprint('camera'),
        '7b7c4cf3133a8257b352cf040dd32999e58512c7897aa1c6d5e0e05afb46bbc9',
      );
    },
  );
  testWidgets(
    'actual upload UI waits for 201 before showing a result and releases preview memory',
    (t) async {
      final f = Fixture()..pending = Completer();
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('confirmCaptureUpload')));
        await t.tap(find.byKey(const Key('confirmCaptureUpload')));
        await t.pump();
        expect(f.posts, 1);
        expect(find.text('Server-confirmed capture result'), findsNothing);
        expect(f.capture.phase, GuidedCapturePhase.uploading);
        f.pending!.complete(o.jsonResponse(receipt(), 201));
        await t.pumpAndSettle();
        await reveal(t, find.text('Server-confirmed capture result'));
        expect(f.capture.phase, GuidedCapturePhase.confirmed);
        expect(f.capture.photo, isNull);
        expect(f.posts, 1);
        expect(f.state.baseline.completedDays, isNull);
        expect(f.state.observations.rows, isNull);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'leaving during upload is honest and never marks the request cancelled',
    (t) async {
      final f = Fixture()..pending = Completer();
      await http.runWithClient(() async {
        await f.login();
        f.choose();
        final request = f.capture.upload(generation: api.sessionGeneration);
        await t.pump();
        await mount(t, f, reduced: true);
        await reveal(t, find.byKey(const Key('captureCancelBack')));
        await t.tap(find.byKey(const Key('captureCancelBack')));
        await t.pumpAndSettle();
        expect(find.text('Leave while uploading?'), findsOneWidget);
        expect(
          find.textContaining('Leaving does not cancel it'),
          findsOneWidget,
        );
        await t.tap(find.text('Stay'));
        await t.pumpAndSettle();
        expect(f.capture.phase, GuidedCapturePhase.uploading);
        expect(f.posts, 1);
        f.pending!.complete(o.jsonResponse(receipt(), 201));
        expect(await request, true);
        await t.pumpAndSettle();
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'full-screen Android picker survives pause/resume with review and no upload',
    (t) async {
      final f = Fixture();
      f.camera.picking = Completer();
      await http.runWithClient(() async {
        await f.login();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('chooseGuidedPhoto')));
        await t.tap(find.byKey(const Key('chooseGuidedPhoto')));
        await t.pump();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        f.camera.picking!.complete(pngBytes());
        await t.pumpAndSettle();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(f.capture.phase, GuidedCapturePhase.review);
        expect(f.capture.photo, isNotNull);
        expect(f.camera.starts, 0);
        expect(f.posts, 0);
        await f.done(t);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'server-revoked acceptance closes camera and clears its photo/result',
    (t) async {
      final f = Fixture();
      var accepted = true;
      await http.runWithClient(
        () async {
          await f.login();
          f.choose();
          await mount(t, f);
          accepted = false;
          expect(await f.state.account.hydrate(reuseConsent: false), false);
          await t.pumpAndSettle();
          expect(api.hasConfirmedSafetyAcceptance, false);
          expect(f.capture.photo, isNull);
          expect(f.capture.record, isNull);
          expect(f.camera.closes, greaterThan(0));
          expect(find.byKey(const Key('localPhotoPreview')), findsNothing);
          expect(f.posts, 0);
          await f.done(t);
        },
        () => o.isolated((r) async {
          if (r.url.path.endsWith('/users/me')) {
            return o.jsonResponse({
              ...jsonDecode(o.user(f.owner).body) as Map<String, dynamic>,
              'safety_accepted': accepted,
            });
          }
          return f.transport(r);
        }),
      );
    },
  );
  for (final dark in [false, true]) {
    for (final reduced in [false, true]) {
      testWidgets(
        'confirmed result dark=$dark reduced=$reduced at 200 percent remains readable',
        (t) async {
          t.view.physicalSize = const Size(320, 800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final f = Fixture();
          await http.runWithClient(() async {
            await f.login();
            f.choose();
            await f.capture.upload(generation: api.sessionGeneration);
            await mount(t, f, dark: dark, reduced: reduced, scale: 2);
            await reveal(t, find.text('View individual quality checks'));
            await t.tap(find.text('View individual quality checks'));
            await t.pumpAndSettle();
            await reveal(t, find.textContaining('yaw: unknown'));
            expect(t.takeException(), isNull);
            await reveal(t, find.text('Nonclinical image estimates'));
            expect(
              find.text('0.351 · fraction_0_to_1 · Limited image proxy'),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
            await f.done(t);
          }, () => o.isolated(f.transport));
        },
      );
    }
  }
  for (final dark in [false, true]) {
    for (final reduced in [false, true]) {
      for (final large in [false, true]) {
        testWidgets(
          'guided capture dark=$dark reduced=$reduced large=$large accessible English',
          (t) async {
            t.view.physicalSize = const Size(320, 800);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            final f = Fixture();
            await http.runWithClient(() async {
              await f.login();
              f.choose();
              await mount(
                t,
                f,
                dark: dark,
                reduced: reduced,
                scale: large ? 2 : 1,
              );
              final semantics = t.ensureSemantics();
              await reveal(t, find.byKey(const Key('confirmCaptureUpload')));
              expect(
                t
                    .getSemantics(find.byKey(const Key('confirmCaptureUpload')))
                    .getSemanticsData()
                    .label,
                contains('Confirm photo & upload'),
              );
              expect(t.takeException(), isNull);
              expect(find.textContaining('Language'), findsNothing);
              expect(f.posts, 0);
              semantics.dispose();
              await f.done(t);
            }, () => o.isolated(f.transport));
          },
        );
      }
    }
  }
}

Uint8List _animated() {
  final image = img.Image(width: 16, height: 20, numChannels: 3);
  image.addFrame(img.Image(width: 16, height: 20, numChannels: 3));
  return img.encodePng(image);
}

// Synthetic PNG fixture checksum, not an application image-transform test stub.
int _crc32(List<int> bytes) {
  var value = 0xffffffff;
  for (final byte in bytes) {
    value ^= byte;
    for (var i = 0; i < 8; i++) {
      value = (value & 1) != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1;
    }
  }
  return value ^ 0xffffffff;
}
