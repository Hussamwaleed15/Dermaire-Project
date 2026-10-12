import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dermaire_app/capture/capture_history_controller.dart';
import 'package:dermaire_app/capture/capture_history_models.dart';
import 'package:dermaire_app/capture/capture_history_screen.dart';
import 'package:dermaire_app/capture/guided_capture_models.dart';
import 'package:dermaire_app/capture/guided_camera_screen.dart';
import 'package:dermaire_app/capture/private_capture_image.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'dart:ui' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'guided_capture_test.dart' as g;
import 'observation_test.dart' as o;
import 'clinical_status_test.dart' as c;

final api = ApiService.instance;

class Fixture {
  String owner = 'a';
  Object? list;
  int uploadCode = 201, ttl = 3600;
  int listCode = 200, imageCode = 200, detailCode = 200, metricCode = 200;
  bool offline = false, mismatch = false, noConsent = false;
  Uint8List? bytes;
  String mime = 'image/png';
  Completer<http.Response>? pendingList,
      pendingImage,
      pendingDetail,
      pendingMetric;
  final requests = <http.Request>[];
  late final state = DermaireState();
  late final images = PrivateCaptureImages(api);
  Future<void> login([String? account]) async {
    owner = account ?? owner;
    await o.login(owner);
    await state.account.hydrate();
  }

  Future<http.Response> transport(http.Request r) async {
    requests.add(r);
    final path = r.url.path;
    if (path.endsWith('/auth/login')) return o.auth(owner, ttl: ttl);
    if (path.endsWith('/users/me')) {
      if (noConsent) {
        return o.jsonResponse({
          ...jsonDecode(o.user(owner).body) as Map,
          'safety_accepted': false,
        });
      }
      return o.user(owner);
    }
    if (path.endsWith('/auth/logout')) return o.jsonResponse({});
    if (path.endsWith('/captures') && r.method == 'POST') {
      return o.jsonResponse(g.receipt(owner: owner), uploadCode);
    }
    expectSync(r.method, 'GET');
    expectSync(r.headers['Authorization'], 'Bearer reused-synthetic-token');
    expectSync(r.url.query, isNot(contains('token')));
    if (path.endsWith('/safety')) {
      return o.jsonResponse(c.safety(status: 'urgent'));
    }
    if (path.endsWith('/doctor/review-status')) {
      return o.jsonResponse(c.review(owner: owner));
    }
    if (path.endsWith('/captures')) {
      expectSync(r.url.queryParameters, {'limit': '100'});
      if (offline) throw http.ClientException('Synthetic offline');
      if (pendingList != null) return pendingList!.future;
      return o.jsonResponse(
        list ?? [g.receipt(owner: owner, inline: false)],
        listCode,
      );
    }
    if (path.endsWith('/image')) {
      if (offline) throw http.ClientException('Synthetic offline');
      if (pendingImage != null) return pendingImage!.future;
      return http.Response.bytes(
        bytes ?? g.pngBytes(),
        imageCode,
        headers: {'content-type': mime, 'cache-control': 'no-store'},
      );
    }
    if (path.contains('/measurements/')) {
      if (pendingMetric != null) return pendingMetric!.future;
      final data = g.measurement(id: r.url.pathSegments.last);
      if (mismatch) {
        data['capture_quality'] = {
          ...data['capture_quality'] as Map,
          'request_fingerprint': 'f' * 64,
        };
      }
      return o.jsonResponse(data, metricCode);
    }
    if (path.contains('/captures/')) {
      if (pendingDetail != null) return pendingDetail!.future;
      return o.jsonResponse(
        g.receipt(owner: owner, id: path.split('/').last, inline: false),
        detailCode,
      );
    }
    throw StateError('Unexpected fixture request');
  }

  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(body, () => o.isolated(transport));
  Future<void> done([WidgetTester? t]) async {
    if (t != null) await t.pumpWidget(const SizedBox());
    images.dispose();
    state.dispose();
    await api.init();
  }
}

class FakeHistory implements CaptureHistoryRepository {
  Future<List<GuidedCaptureRecord>> Function()? onHistory;
  Future<GuidedCaptureRecord> Function()? onRecord;
  Future<CaptureMeasurement> Function()? onMeasurement;
  int reads = 0;
  @override
  Future<List<GuidedCaptureRecord>> history(int generation) {
    reads++;
    return onHistory!();
  }

  @override
  Future<GuidedCaptureRecord> record(String id, int generation) => onRecord!();
  @override
  Future<CaptureMeasurement> measurement(String id, int generation) =>
      onMeasurement!();
}

Future<void> mount(
  WidgetTester t,
  Fixture f,
  Widget child, {
  bool dark = false,
  bool reduced = false,
  double scale = 1,
  double width = 390,
}) async {
  t.view.physicalSize = Size(width, 850);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? DermaireTheme.dark : DermaireTheme.light,
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, 850),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: child!,
      ),
      home: child,
    ),
  );
  await t.pump();
}

Future<void> settleImage(WidgetTester t) async {
  await t.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() async {
    await api.init();
  });

  test('history maps real IDs, UTC receipt and server secondary order', () {
    final rows = parseCaptureHistory([
      g.receipt(id: 'a'),
      {...g.receipt(id: 'z'), 'received_at': '2026-10-12T16:00:00+02:00'},
      {...g.receipt(id: 'new'), 'received_at': '2026-10-13T00:01:00Z'},
    ], 'a');
    expect(rows.map((r) => r.id), ['new', 'z', 'a']);
    expect(rows[1].receivedAt, DateTime.utc(2026, 10, 12, 14));
    expect(captureDate(rows.first.receivedAt), '2026-10-13');
    expect(captureTime(rows[1].receivedAt), contains('server receipt, UTC'));
    expect(rows.first.readback, true);
  });
  for (final kind in [
    'duplicate',
    'object',
    'too many',
    'invalid time',
    'wrong owner ref',
    'public ref',
    'unsupported source',
    'missing timestamp provenance',
  ]) {
    test('history rejects $kind without partial fake history', () {
      final row = g.receipt();
      Object? value = [row];
      switch (kind) {
        case 'duplicate':
          value = [row, row];
        case 'object':
          value = {
            'items': [row],
          };
        case 'too many':
          value = List.generate(101, (i) => g.receipt(id: 'id-$i'));
        case 'invalid time':
          row['received_at'] = '2026-10-12T14:00:00';
        case 'wrong owner ref':
          row['image_reference'] = 'skin_photos/b/b_photo.png';
        case 'public ref':
          row['image_reference'] = 'https://example.invalid/image?token=x';
        case 'unsupported source':
          row['source'] = 'guessed';
        case 'missing timestamp provenance':
          row['provenance'] = {};
      }
      expect(() => parseCaptureHistory(value, 'a'), throwsA(anything));
    });
  }
  test(
    'supported 100-item set includes rejected metadata, is immutable and never invents pages',
    () {
      final rows = parseCaptureHistory(
        List.generate(
          100,
          (i) => g.receipt(
            id: 'id-$i',
            state: i.isEven ? 'accepted' : 'rejected',
            inline: false,
          ),
        ),
        'a',
      );
      expect(rows.length, 100);
      expect(rows.where((r) => !r.stored).length, 50);
      expect(() => rows.clear(), throwsUnsupportedError);
    },
  );
  test(
    'history initial loading, successful read, replacement refresh with no duplication',
    () async {
      final f = Fixture()..pendingList = Completer();
      await f.run(() async {
        await f.login();
        final h = CaptureHistoryController(api);
        final loading = h.refresh();
        expect(h.loading, true);
        expect(h.confirmed, false);
        expect(h.records, isEmpty);
        f.pendingList!.complete(o.jsonResponse([g.receipt(inline: false)]));
        await loading;
        expect(h.records.single.id, 'capture-id');
        expect(h.confirmed, true);
        f.pendingList = null;
        await h.refresh();
        expect(h.records.length, 1);
        h.dispose();
        await f.done();
      });
    },
  );
  test('only successful empty response confirms empty history', () async {
    final f = Fixture()..list = [];
    await f.run(() async {
      await f.login();
      final h = CaptureHistoryController(api);
      await h.refresh();
      expect(h.confirmed, true);
      expect(h.records, isEmpty);
      expect(h.error, isNull);
      h.dispose();
      await f.done();
    });
  });
  for (final code in [403, 404, 422, 500, 503]) {
    test('history $code stays failed and safe GET retry can recover', () async {
      final f = Fixture()..listCode = code;
      await f.run(() async {
        await f.login();
        final h = CaptureHistoryController(api);
        await h.refresh();
        expect(h.confirmed, false);
        expect(h.error, isNotNull);
        expect(h.records, isEmpty);
        f.listCode = 200;
        await h.refresh();
        expect(h.confirmed, true);
        expect(h.records.length, 1);
        expect(
          f.requests
              .where((r) => r.url.path.endsWith('/captures'))
              .every((r) => r.method == 'GET'),
          true,
        );
        h.dispose();
        await f.done();
      });
    });
  }
  test('history offline is not empty confirmed history', () async {
    final f = Fixture()..offline = true;
    await f.run(() async {
      await f.login();
      final h = CaptureHistoryController(api);
      await h.refresh();
      expect(h.error, contains('connection'));
      expect(h.confirmed, false);
      h.dispose();
      await f.done();
    });
  });
  test(
    'history malformed payload does not present successful records',
    () async {
      final f = Fixture()..list = {'fake': true};
      await f.run(() async {
        await f.login();
        final h = CaptureHistoryController(api);
        await h.refresh();
        expect(h.confirmed, false);
        expect(h.error, contains('unsupported'));
        h.dispose();
        await f.done();
      });
    },
  );
  test(
    'history timeout and late completion cannot override a successful retry',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<List<GuidedCaptureRecord>>();
        final repo = FakeHistory()..onHistory = () => pending.future;
        final h = CaptureHistoryController(
          api,
          repository: repo,
          timeout: const Duration(milliseconds: 5),
        );
        await h.refresh();
        expect(h.error, contains('timed out'));
        expect(h.confirmed, false);
        repo.onHistory = () async =>
            parseCaptureHistory([g.receipt(id: 'current')], 'a');
        await h.refresh();
        pending.complete(parseCaptureHistory([g.receipt(id: 'old')], 'a'));
        await Future<void>.delayed(Duration.zero);
        expect(h.records.single.id, 'current');
        h.dispose();
        await f.done();
      });
    },
  );
  test('concurrent GET refresh only newest request publishes', () async {
    final f = Fixture();
    await f.run(() async {
      await f.login();
      final a = Completer<List<GuidedCaptureRecord>>(),
          b = Completer<List<GuidedCaptureRecord>>();
      int calls = 0;
      final repo = FakeHistory()
        ..onHistory = () => calls++ == 0 ? a.future : b.future;
      final h = CaptureHistoryController(api, repository: repo);
      final first = h.refresh(), second = h.refresh();
      b.complete(parseCaptureHistory([g.receipt(id: 'new')], 'a'));
      await second;
      a.complete(parseCaptureHistory([g.receipt(id: 'old')], 'a'));
      await first;
      expect(h.records.single.id, 'new');
      h.dispose();
      await f.done();
    });
  });
  for (final action in [
    'logout',
    'switch account',
    'consent revoked',
    'dispose',
  ]) {
    test('$action prevents late history and metadata access', () async {
      final f = Fixture()..pendingList = Completer();
      await f.run(() async {
        await f.login();
        final h = CaptureHistoryController(api);
        final pending = h.refresh();
        await Future<void>.delayed(Duration.zero);
        if (action == 'logout') {
          await api.logout();
        } else if (action == 'switch account') {
          await f.login('b');
        } else if (action == 'consent revoked') {
          f.noConsent = true;
          await api.readSafetyAcceptance();
        } else {
          h.dispose();
        }
        f.pendingList!.complete(
          o.jsonResponse([g.receipt(owner: 'a', inline: false)]),
        );
        await pending;
        expect(h.records, isEmpty);
        expect(h.current, false);
        if (action != 'dispose') h.dispose();
        await f.done();
      });
    });
  }
  for (final resource in ['history', 'image', 'detail', 'measurement']) {
    test('old $resource 401 cannot invalidate B with a reused token', () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final response = Completer<http.Response>();
        final generation = api.sessionGeneration;
        late Future<Object?> pending;
        if (resource == 'history') {
          f.pendingList = response;
          pending = api.readPrivateCaptureHistory(generation);
        } else if (resource == 'image') {
          f.pendingImage = response;
          pending = api.readPrivateCaptureImage('capture-id', generation);
        } else if (resource == 'detail') {
          f.pendingDetail = response;
          pending = api.readGuidedCapture(
            id: 'capture-id',
            generation: generation,
          );
        } else {
          f.pendingMetric = response;
          pending = api.readCaptureMeasurement(
            id: 'capture-id',
            generation: generation,
          );
        }
        final rejected = expectLater(pending, throwsA(isA<ApiException>()));
        await Future<void>.delayed(Duration.zero);
        await f.login('b');
        response.complete(o.jsonResponse({}, 401));
        await rejected;
        expect(api.observationOwner, 'b');
        expect(api.hasConfirmedSafetyAcceptance, true);
        await f.done();
      });
    });
  }
  for (final resource in ['history', 'image']) {
    test('current $resource 401 immediately expires private session', () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final generation = api.sessionGeneration;
        if (resource == 'history') {
          f.listCode = 401;
          await expectLater(
            api.readPrivateCaptureHistory(generation),
            throwsA(isA<ApiException>()),
          );
        } else {
          f.imageCode = 401;
          await expectLater(
            api.readPrivateCaptureImage('capture-id', generation),
            throwsA(isA<ApiException>()),
          );
        }
        expect(api.isAuthenticated, false);
        expect(api.canReadPatientClinicalStatus, false);
        await f.done();
      });
    });
  }
  test(
    'protected image route uses header auth, no SAS/public refs/query or POST',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final image = await api.readPrivateCaptureImage(
          'capture-id',
          api.sessionGeneration,
        );
        expect(image.bytes, g.pngBytes());
        expect(image.mime, 'image/png');
        final r = f.requests.last;
        expect(r.url.path, '/api/v1/captures/capture-id/image');
        expect(r.url.query, isEmpty);
        await f.done();
      });
    },
  );
  test('unsafe image identity never reaches transport', () async {
    final f = Fixture();
    await f.run(() async {
      await f.login();
      final n = f.requests.length;
      await expectLater(
        api.readPrivateCaptureImage('../b?token=x', api.sessionGeneration),
        throwsArgumentError,
      );
      expect(f.requests.length, n);
      await f.done();
    });
  });
  test('local-only/unconfirmed consent cannot read history or image', () async {
    final f = Fixture()..noConsent = true;
    await f.run(() async {
      await f.login();
      final n = f.requests.length;
      await expectLater(
        api.readPrivateCaptureHistory(api.sessionGeneration),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.readPrivateCaptureImage('capture-id', api.sessionGeneration),
        throwsA(isA<ApiException>()),
      );
      expect(f.requests.length, n);
      await f.done();
    });
  });
  for (final kind in [
    'empty',
    'html',
    'corrupt png',
    'wrong mime',
    'unsupported mime',
  ]) {
    test('private decode rejects $kind without cache insert', () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        f.bytes = kind == 'empty'
            ? Uint8List(0)
            : kind == 'html'
            ? Uint8List.fromList(utf8.encode('<html>'))
            : kind == 'corrupt png'
            ? g.pngBytes().sublist(0, 20)
            : g.pngBytes();
        if (kind == 'wrong mime') f.mime = 'image/jpeg';
        if (kind == 'unsupported mime') f.mime = 'image/webp';
        await expectLater(
          f.images.load(
            'capture-id',
            api.sessionGeneration,
            256,
            active: () => true,
          ),
          throwsA(anything),
        );
        expect(f.images.decodedPixels, 0);
        await f.done();
      });
    });
  }
  for (final code in [403, 404, 500, 503]) {
    test('image $code is unavailable with truthful retry', () async {
      final f = Fixture()..imageCode = code;
      await f.run(() async {
        await f.login();
        await expectLater(
          f.images.load(
            'capture-id',
            api.sessionGeneration,
            256,
            active: () => true,
          ),
          throwsA(
            isA<PrivateCaptureException>().having(
              (e) => e.status,
              'status',
              code,
            ),
          ),
        );
        expect(f.images.decodedPixels, 0);
        f.imageCode = 200;
        final lease = await f.images.load(
          'capture-id',
          api.sessionGeneration,
          256,
          active: () => true,
        );
        expect(lease.image, isNotNull);
        lease.dispose();
        await f.done();
      });
    });
  }
  test(
    'thumbnails decode within 256px; no global image-cache entry; disposal releases memory',
    () async {
      final f = Fixture()..bytes = g.pngBytes(width: 640, height: 800);
      await f.run(() async {
        await f.login();
        final before = PaintingBinding.instance.imageCache.currentSize;
        final lease = await f.images.load(
          'capture-id',
          api.sessionGeneration,
          256,
          active: () => true,
        );
        expect(lease.image!.width, 204);
        expect(lease.image!.height, 256);
        expect(f.images.decodedPixels, 204 * 256);
        expect(PaintingBinding.instance.imageCache.currentSize, before);
        lease.dispose();
        expect(f.images.decodedPixels, 0);
        await f.done();
      });
    },
  );
  test(
    'queue bounds active downloads across routes and skips disposed requests',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final first = Completer<PrivateImageBytes>();
        int reads = 0, active = 0, peak = 0;
        bool secondActive = true;
        final images = PrivateCaptureImages(
          api,
          reader: (id, generation) async {
            reads++;
            active++;
            if (active > peak) peak = active;
            final value = await first.future;
            active--;
            return value;
          },
        );
        final a = images.load(
          'a',
          api.sessionGeneration,
          256,
          active: () => true,
        );
        final b = images.load(
          'b',
          api.sessionGeneration,
          256,
          active: () => secondActive,
        );
        final rejected = expectLater(b, throwsA(isA<FormatException>()));
        await Future<void>.delayed(Duration.zero);
        expect(reads, 1);
        secondActive = false;
        first.complete(PrivateImageBytes(g.pngBytes(), 'image/png'));
        final lease = await a;
        await rejected;
        expect(peak, 1);
        expect(reads, 1);
        lease.dispose();
        images.dispose();
        await f.done();
      });
    },
  );
  for (final action in ['logout', 'switch account', 'consent revoked']) {
    test(
      '$action disposes already decoded pixels and denies stale lease reuse',
      () async {
        final f = Fixture();
        await f.run(() async {
          await f.login();
          final lease = await f.images.load(
            'capture-id',
            api.sessionGeneration,
            256,
            active: () => true,
          );
          final old = api.sessionGeneration;
          if (action == 'logout') {
            await api.logout();
          } else if (action == 'switch account') {
            await f.login('b');
          } else {
            f.noConsent = true;
            await f.state.account.hydrate(reuseConsent: false);
          }
          expect(lease.image, isNull);
          expect(f.images.decodedPixels, 0);
          await expectLater(
            f.images.load('capture-id', old, 256, active: () => true),
            throwsA(anything),
          );
          await f.done();
        });
      },
    );
  }
  test('late decoded response after logout never becomes a lease', () async {
    final f = Fixture();
    await f.run(() async {
      await f.login();
      final result = Completer<PrivateImageBytes>();
      final images = PrivateCaptureImages(api, reader: (_, _) => result.future);
      final pending = images.load(
        'capture-id',
        api.sessionGeneration,
        256,
        active: () => true,
      );
      final rejected = expectLater(pending, throwsA(anything));
      await Future<void>.delayed(Duration.zero);
      await api.logout();
      result.complete(PrivateImageBytes(g.pngBytes(), 'image/png'));
      await rejected;
      expect(images.decodedPixels, 0);
      images.dispose();
      await f.done();
    });
  });
  test(
    'detail reads owned metadata and bound nonclinical estimates via GET',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final d = CaptureDetailController(api, 'capture-id');
        await d.refresh();
        expect(d.record!.id, 'capture-id');
        expect(d.measurement!.metrics['red_chromaticity_proxy']!.value, 0.351);
        expect(
          d.measurement!.metrics['texture_contrast_proxy']!.unit,
          'fraction_0_to_1',
        );
        expect(d.error, isNull);
        d.dispose();
        await f.done();
      });
    },
  );
  for (final code in [404, 409, 403, 500]) {
    test(
      'measurement $code does not fabricate values or lose valid capture receipt',
      () async {
        final f = Fixture()..metricCode = code;
        await f.run(() async {
          await f.login();
          final d = CaptureDetailController(api, 'capture-id');
          await d.refresh();
          expect(d.record, isNotNull);
          expect(d.measurement, isNull);
          expect(d.measurementError, isNotNull);
          d.dispose();
          await f.done();
        });
      },
    );
  }
  test(
    'mismatched quality fingerprint refuses estimates for otherwise valid capture',
    () async {
      final f = Fixture()..mismatch = true;
      await f.run(() async {
        await f.login();
        final d = CaptureDetailController(api, 'capture-id');
        await d.refresh();
        expect(d.measurement, isNull);
        expect(d.measurementError, isNotNull);
        d.dispose();
        await f.done();
      });
    },
  );
  test('detail and pending measurements clear on account switch', () async {
    final f = Fixture()..pendingMetric = Completer();
    await f.run(() async {
      await f.login();
      final d = CaptureDetailController(api, 'capture-id');
      final pending = d.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(d.record, isNotNull);
      await f.login('b');
      f.pendingMetric!.complete(o.jsonResponse(g.measurement()));
      await pending;
      expect(d.record, isNull);
      expect(d.measurement, isNull);
      expect(d.current, false);
      d.dispose();
      await f.done();
    });
  });
  for (final theme in ['light', 'dark', 'reduced', 'large']) {
    testWidgets(
      'history $theme uses honest list and accessible lazy thumbnails',
      (t) async {
        final f = Fixture()
          ..list = List.generate(
            100,
            (i) => g.receipt(
              id: 'id-${i.toString().padLeft(3, '0')}',
              inline: false,
            ),
          );
        await f.run(() async {
          await f.login();
          await mount(
            t,
            f,
            CaptureHistoryScreen(state: f.state, images: f.images),
            dark: theme == 'dark',
            reduced: theme == 'reduced',
            scale: theme == 'large' ? 2 : 1,
            width: theme == 'large' ? 320 : 390,
          );
          await t.pumpAndSettle();
          expect(find.text('Image history'), findsOneWidget);
          expect(find.textContaining('Most recent 100'), findsOneWidget);
          expect(
            f.requests.where((r) => r.url.path.endsWith('/image')).length,
            lessThan(5),
          );
          await t.scrollUntilVisible(
            find.byKey(const ValueKey('captureDetails:id-099')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await settleImage(t);
          expect(find.text('Open capture details'), findsWidgets);
          expect(
            f.images.decodedPixels,
            lessThanOrEqualTo(maxPrivateDecodedPixels),
          );
          expect(t.takeException(), isNull);
          expect(find.textContaining('Before/After'), findsNothing);
          expect(find.text('Delete photo'), findsNothing);
          await f.done(t);
          expect(f.images.decodedPixels, 0);
        });
      },
    );
  }
  testWidgets('history failure has retry and never claims empty history', (
    t,
  ) async {
    final f = Fixture()..listCode = 503;
    await f.run(() async {
      await f.login();
      await mount(t, f, CaptureHistoryScreen(state: f.state, images: f.images));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.textContaining('temporarily unavailable'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.textContaining('temporarily unavailable'), findsOneWidget);
      expect(find.textContaining('No captures returned'), findsNothing);
      f.list = [];
      f.listCode = 200;
      await t.scrollUntilVisible(
        find.byKey(const Key('refreshCaptureHistory')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('refreshCaptureHistory')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('refreshCaptureHistory')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.textContaining('No captures returned'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('No captures returned'), findsOneWidget);
      await f.done(t);
    });
  });
  testWidgets(
    'viewer has pinch/pan, semantic zoom buttons and no global image cache',
    (t) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final before = PaintingBinding.instance.imageCache.currentSize;
        await mount(
          t,
          f,
          Scaffold(
            body: PrivateCaptureImage(
              id: 'capture-id',
              generation: api.sessionGeneration,
              stored: true,
              viewer: true,
              images: f.images,
            ),
          ),
        );
        await settleImage(t);
        expect(find.byType(RawImage), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        final interactive = t.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        await t.tap(find.text('Zoom in'));
        await t.pump();
        expect(
          interactive.transformationController!.value.getMaxScaleOnAxis(),
          1.5,
        );
        await t.tap(find.text('Zoom out'));
        await t.pump();
        expect(
          interactive.transformationController!.value.getMaxScaleOnAxis(),
          1,
        );
        await t.tap(find.text('Zoom in'));
        await t.tap(find.text('Reset image zoom'));
        await t.pump();
        expect(
          interactive.transformationController!.value.getMaxScaleOnAxis(),
          1,
        );
        expect(PaintingBinding.instance.imageCache.currentSize, before);
        expect(interactive.panEnabled, true);
        expect(interactive.scaleEnabled, true);
        final semantics = t.ensureSemantics();
        await t.pump();
        final node = t.getSemantics(find.text('Zoom in'));
        expect(node.label, 'Zoom in');
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), true);
        semantics.dispose();
        await f.done(t);
      });
    },
  );
  testWidgets('metadata remains truthful when private image is missing', (
    t,
  ) async {
    final f = Fixture()..imageCode = 404;
    await f.run(() async {
      await f.login();
      await mount(
        t,
        f,
        CaptureDetailScreen(state: f.state, id: 'capture-id', images: f.images),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.textContaining('Metadata does not guarantee'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Metadata does not guarantee'),
        findsOneWidget,
      );
      expect(find.byType(RawImage), findsNothing);
      await t.scrollUntilVisible(
        find.text('Image quality'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('Image quality'), findsOneWidget);
      expect(find.text('Server quality decision: accepted'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Nonclinical image estimates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.textContaining('0.351 · fraction_0_to_1'), findsOneWidget);
      expect(find.textContaining('0.041 · fraction_0_to_1'), findsOneWidget);
      expect(find.textContaining('not diagnoses'), findsOneWidget);
      expect(find.text('Skin health score'), findsNothing);
      expect(find.textContaining('improvement'), findsNothing);
      await f.done(t);
    });
  });
  testWidgets('pending image loading is cleared immediately by logout', (
    t,
  ) async {
    final f = Fixture()..pendingImage = Completer();
    await f.run(() async {
      await f.login();
      await mount(
        t,
        f,
        Scaffold(
          body: PrivateCaptureImage(
            id: 'capture-id',
            generation: api.sessionGeneration,
            stored: true,
            images: f.images,
          ),
        ),
      );
      await t.pump();
      expect(find.text('Loading private image…'), findsOneWidget);
      await api.logout();
      await t.pump();
      expect(
        find.text('Private image cleared. Session ended.'),
        findsOneWidget,
      );
      expect(find.byType(RawImage), findsNothing);
      f.pendingImage!.complete(
        http.Response.bytes(
          g.pngBytes(),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await settleImage(t);
      expect(find.byType(RawImage), findsNothing);
      expect(f.images.decodedPixels, 0);
      await f.done(t);
    });
  });
  testWidgets('stale detail route cannot reveal A metadata or pixels to B', (
    t,
  ) async {
    final f = Fixture();
    await f.run(() async {
      await f.login();
      await mount(
        t,
        f,
        CaptureDetailScreen(state: f.state, id: 'capture-id', images: f.images),
      );
      await t.scrollUntilVisible(
        find.byType(PrivateCaptureImage),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settleImage(t);
      expect(find.byType(RawImage), findsOneWidget);
      await f.login('b');
      await t.pumpAndSettle();
      expect(find.text('Session ended'), findsOneWidget);
      expect(find.byType(RawImage), findsNothing);
      expect(find.textContaining('capture-id'), findsNothing);
      expect(f.images.decodedPixels, 0);
      await f.done(t);
    });
  });
  testWidgets('not-stored record never downloads private image', (t) async {
    final f = Fixture();
    await f.run(() async {
      await f.login();
      await mount(
        t,
        f,
        Scaffold(
          body: PrivateCaptureImage(
            id: 'capture-id',
            generation: api.sessionGeneration,
            stored: false,
            images: f.images,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text('No image was stored for this capture.'),
        findsOneWidget,
      );
      expect(f.requests.where((r) => r.url.path.endsWith('/image')), isEmpty);
      await f.done(t);
    });
  });
  testWidgets(
    'entry opens distinct image history without observation/Home changes',
    (t) async {
      final f = Fixture()..list = [];
      await f.run(() async {
        await f.login();
        await mount(t, f, Scaffold(body: GuidedCaptureEntry(state: f.state)));
        await t.tap(find.byKey(const Key('openPrivateCaptureHistory')));
        await t.pumpAndSettle();
        expect(find.text('Image history'), findsOneWidget);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/captures')).length,
          1,
        );
        await f.done(t);
      });
    },
  );
  for (final code in [403, 404, 503]) {
    testWidgets(
      'detail metadata $code has retry without showing a private image',
      (t) async {
        final f = Fixture()..detailCode = code;
        await f.run(() async {
          await f.login();
          await mount(
            t,
            f,
            CaptureDetailScreen(
              state: f.state,
              id: 'capture-id',
              images: f.images,
            ),
          );
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.text('Retry capture read'),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.byType(PrivateCaptureImage), findsNothing);
          expect(
            f.requests.where((r) => r.url.path.endsWith('/image')),
            isEmpty,
          );
          f.detailCode = 200;
          await t.ensureVisible(find.text('Retry capture read'));
          await t.pumpAndSettle();
          await t.tap(find.text('Retry capture read'));
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byType(PrivateCaptureImage),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await settleImage(t);
          expect(find.byType(RawImage), findsOneWidget);
          await f.done(t);
        });
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets(
      'detail large text and reduced motion dark=$dark preserves safety and controls',
      (t) async {
        final f = Fixture();
        await f.run(() async {
          await f.login();
          await mount(
            t,
            f,
            CaptureDetailScreen(
              state: f.state,
              id: 'capture-id',
              images: f.images,
            ),
            dark: dark,
            reduced: true,
            scale: 2,
            width: 320,
          );
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byType(PrivateCaptureImage),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await settleImage(t);
          await t.scrollUntilVisible(
            find.text('Reset image zoom'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          expect(find.text('Reset image zoom'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.scrollUntilVisible(
            find.text('Nonclinical image estimates'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.textContaining('not diagnoses'), findsOneWidget);
          await f.done(t);
        });
      },
    );
  }
  testWidgets(
    'idle session expiry clears pending private image without retry',
    (t) async {
      final f = Fixture()
        ..ttl = 1
        ..pendingImage = Completer();
      await f.run(() async {
        await f.login();
        await mount(
          t,
          f,
          Scaffold(
            body: PrivateCaptureImage(
              id: 'capture-id',
              generation: api.sessionGeneration,
              stored: true,
              images: f.images,
            ),
          ),
        );
        await t.pump();
        expect(find.text('Loading private image…'), findsOneWidget);
        await t.pump(const Duration(seconds: 2));
        await t.pump();
        expect(
          find.text('Private image cleared. Session ended.'),
          findsOneWidget,
        );
        expect(f.images.decodedPixels, 0);
        f.pendingImage!.complete(
          http.Response.bytes(
            g.pngBytes(),
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await settleImage(t);
        expect(find.byType(RawImage), findsNothing);
        await f.done(t);
      });
    },
  );
  testWidgets(
    'camera closes on history navigation and does not restart behind it on app resume',
    (t) async {
      final f = Fixture()..list = [];
      final port = g.FakePort();
      await f.run(() async {
        await f.login();
        await mount(t, f, GuidedCameraScreen(state: f.state, cameraPort: port));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byKey(const Key('startLiveCamera')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.ensureVisible(find.byKey(const Key('startLiveCamera')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('startLiveCamera')));
        await t.pumpAndSettle();
        expect(port.starts, 1);
        await t.ensureVisible(find.byKey(const Key('captureOpenHistory')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('captureOpenHistory')));
        await t.pumpAndSettle();
        expect(find.text('Image history'), findsOneWidget);
        expect(port.closes, greaterThan(0));
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await t.pump();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(port.starts, 1);
        await f.done(t);
      });
    },
  );
  for (final uploadCode in [201, 503]) {
    testWidgets(
      'camera return uses confirmed GET history, no optimistic insertion or POST repeat ($uploadCode)',
      (t) async {
        final f = Fixture()
          ..list = []
          ..uploadCode = uploadCode;
        await f.run(() async {
          await f.login();
          final capture = f.state.guidedCapture;
          capture.begin(api.sessionGeneration);
          capture.select(
            g.sample(),
            'camera',
            generation: api.sessionGeneration,
          );
          // A synthetic 503 leaves an uncertain upload that history must not replay.
          await capture.upload(generation: api.sessionGeneration);
          expect(capture.record != null, uploadCode == 201);
          final posts = f.requests
              .where(
                (r) => r.method == 'POST' && r.url.path.endsWith('/captures'),
              )
              .length;
          await mount(
            t,
            f,
            CaptureHistoryScreen(state: f.state, images: f.images),
          );
          await t.pumpAndSettle();
          final reads = f.requests
              .where(
                (r) => r.method == 'GET' && r.url.path.endsWith('/captures'),
              )
              .length;
          await t.scrollUntilVisible(
            find.byKey(const Key('historyOpenCamera')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          await t.ensureVisible(find.byKey(const Key('historyOpenCamera')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('historyOpenCamera')));
          await t.pumpAndSettle();
          expect(find.textContaining('previous upload may'), findsNothing);
          await t.pageBack();
          await t.pumpAndSettle();
          expect(
            f.requests
                .where(
                  (r) => r.method == 'GET' && r.url.path.endsWith('/captures'),
                )
                .length,
            reads + 1,
          );
          expect(
            f.requests
                .where(
                  (r) => r.method == 'POST' && r.url.path.endsWith('/captures'),
                )
                .length,
            posts,
          );
          await f.done(t);
        });
      },
    );
  }
}
