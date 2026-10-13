import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/products/product.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_authority_test.dart' as f;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final field in [
    'id',
    'name',
    'user_id',
    'status',
    'category',
    'time_of_use',
    'frequency_per_week',
    'tags',
    'created_at',
  ]) {
    test('reject malformed product $field without defaults', () {
      final row = f.row('Synthetic serum')..[field] = null;
      expect(() => Product.fromApi(row), throwsA(isA<FormatException>()));
    });
  }
  for (final status in [401, 403, 404, 503]) {
    test(
      'failed product GET $status is not an empty authoritative library',
      () async {
        await http.runWithClient(
          () async {
            await f.login();
            final c = ProductsController(RemoteProductRepository());
            await c.load();
            if (status == 401) {
              expect(ApiService.instance.authToken, isNull);
              expect(c.all, isEmpty);
            } else {
              expect(c.isStale, true);
              expect(c.errorMessage, isNotNull);
            }
            c.dispose();
          },
          () => MockClient((r) async {
            if (r.url.path.endsWith('/auth/login')) return f.auth();
            if (r.url.path.endsWith('/users/me')) {
              return http.Response(
                '{"id":"patient-1","role":"patient","safety_accepted":true}',
                200,
              );
            }
            return http.Response('{}', status);
          }),
        );
      },
    );
  }
  for (final scenario in [
    'foreign owner',
    'stale edit',
    'unconfirmed delete',
    'uncertain create',
    'late logout',
  ]) {
    test(scenario, () async {
      var posts = 0;
      var version = '2026-10-01T01:00:00';
      final delayed = Completer<http.Response>();
      var wait = false;
      await http.runWithClient(
        () async {
          await f.login();
          final c = ProductsController(RemoteProductRepository());
          await c.load();
          if (scenario == 'foreign owner') {
            expect(c.all, isEmpty);
            expect(c.isStale, true);
          }
          if (scenario == 'stale edit') {
            final original = c.all.single;
            version = '2026-10-02T01:00:00';
            expect(
              (await c.update(original.copyWith(notes: 'new'))).success,
              false,
            );
            expect(posts, 0);
          }
          if (scenario == 'unconfirmed delete') {
            expect((await c.delete('server-id')).success, false);
            expect(c.all.single.id, 'server-id');
          }
          if (scenario == 'uncertain create') {
            expect(
              (await c.add(Product.fromApi(f.row('Different name')))).success,
              false,
            );
            await c.load();
            expect(
              (await c.add(Product.fromApi(f.row('Different name')))).success,
              false,
            );
            expect(posts, 1);
          }
          if (scenario == 'late logout') {
            wait = true;
            final pending = c.load();
            await Future<void>.delayed(Duration.zero);
            await ApiService.instance.init();
            delayed.complete(http.Response(jsonEncode([f.row('Late')]), 200));
            await pending;
            expect(c.all, isEmpty);
          }
          c.dispose();
        },
        () => MockClient((r) async {
          if (r.url.path.endsWith('/auth/login')) return f.auth();
          if (r.url.path.endsWith('/users/me')) {
            return http.Response(
              '{"id":"patient-1","role":"patient","safety_accepted":true}',
              200,
            );
          }
          if (r.method == 'POST' || r.method == 'PATCH') {
            posts++;
            throw TimeoutException('synthetic timeout');
          }
          if (r.method == 'DELETE') return http.Response('', 204);
          if (wait) return delayed.future;
          final row = f.row('Original')..['updated_at'] = version;
          if (scenario == 'foreign owner') row['user_id'] = 'patient-other';
          return http.Response(
            jsonEncode(r.url.path.endsWith('/products') ? [row] : row),
            200,
          );
        }),
      );
    });
  }
}
