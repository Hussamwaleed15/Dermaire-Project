import 'dart:async';
import 'dart:typed_data';
import 'package:dermaire_app/capture/capture_history_models.dart';
import 'package:dermaire_app/capture/private_capture_image.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'guided_capture_test.dart' as g;
import 'observation_test.dart' as o;
import 'private_capture_history_test.dart' as h;

final api = ApiService.instance;
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() async {
    await api.init();
  });
  for (final mode in [
    'declared length',
    'chunked length',
    'error body',
    'redirect',
  ]) {
    test('private transport bounds $mode without unsafe fallback', () async {
      int consumed = 0;
      final client = MockClient.streaming((r, body) async {
        expectSync(r.url.host, 'flutter-tests.invalid');
        if (r.url.path.endsWith('/auth/login')) {
          return http.StreamedResponse(
            Stream.value(o.auth('a').bodyBytes),
            200,
          );
        }
        if (r.url.path.endsWith('/users/me')) {
          return http.StreamedResponse(
            Stream.value(o.user('a').bodyBytes),
            200,
          );
        }
        expectSync(r.url.path, '/api/v1/captures/capture-id/image');
        expectSync(r.method, 'GET');
        expectSync(r.followRedirects, false);
        expectSync(r.url.query, isEmpty);
        expectSync(r.headers['Authorization'], 'Bearer reused-synthetic-token');
        Stream<List<int>> bytes() async* {
          final chunk = Uint8List(1024 * 1024);
          for (int i = 0; i < 70; i++) {
            consumed++;
            yield chunk;
          }
        }

        return http.StreamedResponse(
          bytes(),
          mode == 'error body'
              ? 401
              : mode == 'redirect'
              ? 302
              : 200,
          contentLength: mode == 'declared length'
              ? maxPrivateImageBytes + 1
              : null,
          headers: {
            'content-type': 'image/png',
            if (mode == 'redirect')
              'location': 'https://untrusted.invalid/photo',
          },
        );
      });
      await http.runWithClient(() async {
        await o.login('a');
        await expectLater(
          api.readPrivateCaptureImage('capture-id', api.sessionGeneration),
          throwsA(
            mode == 'error body'
                ? isA<ApiException>()
                : mode == 'redirect'
                ? isA<PrivateCaptureException>()
                : isA<FormatException>(),
          ),
        );
        expect(consumed, mode == 'chunked length' ? 65 : 0);
        if (mode == 'error body') expect(api.isAuthenticated, false);
      }, () => client);
    });
  }
  test(
    'viewer decode is capped and aggregate leases reject memory beyond budget',
    () async {
      final f = h.Fixture()..bytes = g.pngBytes(width: 2000, height: 2000);
      await f.run(() async {
        await f.login();
        final leases = <PrivateImageLease>[];
        for (int i = 0; i < 4; i++) {
          final lease = await f.images.load(
            'id-$i',
            api.sessionGeneration,
            privateViewerEdge,
            active: () => true,
          );
          expect(lease.image!.width, 1600);
          expect(lease.image!.height, 1600);
          leases.add(lease);
        }
        expect(f.images.decodedPixels, 10240000);
        await expectLater(
          f.images.load(
            'overflow',
            api.sessionGeneration,
            1600,
            active: () => true,
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          f.images.decodedPixels,
          lessThanOrEqualTo(maxPrivateDecodedPixels),
        );
        leases.first.dispose();
        final retry = await f.images.load(
          'overflow',
          api.sessionGeneration,
          1600,
          active: () => true,
        );
        retry.dispose();
        for (final lease in leases) {
          lease.dispose();
        }
        expect(f.images.decodedPixels, 0);
        await f.done();
      });
    },
  );
  test(
    'oversized encoded fixture is rejected before allocation of codec',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final data = Uint8List(maxPrivateImageBytes + 1)
          ..setRange(0, 8, g.pngBytes().take(8));
        final images = PrivateCaptureImages(
          api,
          reader: (_, _) async => PrivateImageBytes(data, 'image/png'),
        );
        await expectLater(
          images.load('id', api.sessionGeneration, 256, active: () => true),
          throwsA(isA<FormatException>()),
        );
        expect(images.decodedPixels, 0);
        images.dispose();
        await f.done();
      });
    },
  );
  test(
    'oversized source pixel header is rejected before full image decoding',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final bytes = Uint8List.fromList(g.pngBytes());
        final data = ByteData.sublistView(bytes);
        data.setUint32(16, 5000);
        data.setUint32(20, 5000);
        var crc = 0xffffffff;
        for (final byte in bytes.sublist(12, 29)) {
          crc ^= byte;
          for (int i = 0; i < 8; i++) {
            crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
          }
        }
        data.setUint32(29, crc ^ 0xffffffff);
        f.bytes = bytes;
        await expectLater(
          f.images.load(
            'capture-id',
            api.sessionGeneration,
            256,
            active: () => true,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'reason',
              contains('memory limit'),
            ),
          ),
        );
        expect(f.images.decodedPixels, 0);
        await f.done();
      });
    },
  );
  test(
    'transport timeout is retryable and never publishes decoded pixels',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final images = PrivateCaptureImages(
          api,
          reader: (_, _) async => throw TimeoutException('Synthetic timeout'),
        );
        await expectLater(
          images.load('id', api.sessionGeneration, 256, active: () => true),
          throwsA(isA<TimeoutException>()),
        );
        expect(images.decodedPixels, 0);
        images.dispose();
        await f.done();
      });
    },
  );
}
