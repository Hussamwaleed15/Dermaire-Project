import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/products/products_ui.dart';
import 'wave_product_receipt_test.dart' as product;
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/services/request_failure.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_recovery_projection_test.dart' as f;
import 'product_authority_test.dart' as auth;

bool populated(String domain, dynamic c) => switch (domain) {
  'product' => c.all.isNotEmpty as bool,
  'routine' => c.entries != null,
  _ => c.rows != null,
};
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final domain in ['product', 'routine', 'experiment']) {
    for (final status in [401, 403, 503]) {
      test(
        '$domain read$status hides denied records and permits fresh recovery',
        () async {
          final dynamic w = f.wireFor(domain);
          var failure = 200;
          await http.runWithClient(
            () async {
              await auth.login();
              final dynamic c = f.controllerFor(domain, (_) async {});
              try {
                await f.load(domain, c);
                expect(populated(domain, c), true);
                expect(c.lastConfirmedAt, isNotNull);
                failure = status;
                await f.load(domain, c);
                expect(populated(domain, c), status == 503);
                if (status != 503) expect(c.lastConfirmedAt, isNull);
                if (domain == 'routine' && status != 503) {
                  expect(c.history, isNull);
                  expect(c.historyHasMore, false);
                }
                if (status == 401) {
                  expect(ApiService.instance.isAuthenticated, false);
                  await auth.login();
                } else {
                  expect(
                    c.readFailure.kind,
                    status == 403
                        ? RequestFailureKind.denied
                        : RequestFailureKind.server,
                  );
                }
                failure = 200;
                await f.load(domain, c);
                expect(populated(domain, c), true);
                expect(c.lastConfirmedAt, isNotNull);
                expect(c.readFailure, isNull);
              } finally {
                c.dispose();
              }
            },
            () => MockClient((r) async {
              expect(r.url.host, 'flutter-tests.invalid');
              if (r.method == 'GET' &&
                  !r.url.path.endsWith('/users/me') &&
                  failure != 200) {
                return http.Response('{}', failure);
              }
              return await w.call(r) as http.Response;
            }),
          );
        },
      );
    }
    test(
      '$domain denied read never destroys or replaces an uncertain write',
      () async {
        final dynamic w = f.wireFor(domain);
        var denied = false;
        await http.runWithClient(
          () async {
            await auth.login();
            final dynamic c = f.controllerFor(domain, (_) async {});
            try {
              await f.load(domain, c);
              expect(await w.submit(c), false);
              final original = Map.of(ApiService.instance.integrationIntents);
              expect(original, isNotEmpty);
              denied = true;
              await f.load(domain, c);
              expect(populated(domain, c), false);
              expect(ApiService.instance.integrationIntents, original);
              denied = false;
              await f.load(domain, c);
              expect(populated(domain, c), true);
              expect(f.hasPending(domain, c), true);
              expect(await w.submit(c), false);
              expect(ApiService.instance.integrationIntents, original);
            } finally {
              c.dispose();
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.method == 'GET' &&
                !r.url.path.endsWith('/users/me') &&
                denied) {
              return http.Response('{}', 403);
            }
            return await w.call(r) as http.Response;
          }),
        );
      },
    );
    test(
      '$domain late successful refresh cannot restore logged-out records',
      () async {
        final dynamic w = f.wireFor(domain);
        final sent = Completer<void>(), release = Completer<http.Response>();
        var delay = false;
        await http.runWithClient(
          () async {
            await auth.login();
            final dynamic c = f.controllerFor(domain, (_) async {});
            try {
              await f.load(domain, c);
              delay = true;
              final read = f.load(domain, c);
              await sent.future;
              await ApiService.instance.init();
              release.complete(http.Response('[]', 200));
              await read;
              expect(populated(domain, c), false);
              expect(c.lastConfirmedAt, isNull);
            } finally {
              c.dispose();
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.method == 'GET' &&
                !r.url.path.endsWith('/users/me') &&
                delay) {
              if (!sent.isCompleted) sent.complete();
              return release.future;
            }
            return await w.call(r) as http.Response;
          }),
        );
      },
    );
  }
  for (final domain in ['routine', 'experiment']) {
    test(
      '$domain denied next page clears the existing private collection',
      () async {
        final dynamic w = f.wireFor(domain);
        var denied = false;
        await http.runWithClient(
          () async {
            await auth.login();
            final dynamic c = f.controllerFor(domain, (_) async {});
            try {
              await f.load(domain, c);
              expect(populated(domain, c), true);
              // Simulate an already offered next-page control with a nonempty cache.
              if (domain == 'routine') {
                c.historyHasMore = true;
              } else {
                c.hasMore = true;
              }
              denied = true;
              if (domain == 'routine') {
                await c.loadMoreHistory();
              } else {
                await c.loadMore();
              }
              expect(populated(domain, c), false);
              expect(c.lastConfirmedAt, isNull);
              expect(c.loadingMore, false);
              expect(c.readFailure.kind, RequestFailureKind.denied);
            } finally {
              c.dispose();
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.method == 'GET' &&
                !r.url.path.endsWith('/users/me') &&
                denied) {
              return http.Response('{}', 403);
            }
            return await w.call(r) as http.Response;
          }),
        );
      },
    );
  }
  testWidgets(
    'real product library removes previously visible records after403',
    (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final w = product.Wire();
      final state = DermaireState();
      var denied = false;
      await http.runWithClient(
        () async {
          await auth.login();
          await state.productController.load();
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(body: ProductsFeatureTab(state: state)),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Existing serum'), findsWidgets);
          denied = true;
          await state.productController.load();
          await t.pumpAndSettle();
          expect(find.text('Existing serum'), findsNothing);
          expect(
            find.textContaining('Product access unavailable.'),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          state.dispose();
          await ApiService.instance.init();
        },
        () => MockClient((r) async {
          expect(r.url.host, 'flutter-tests.invalid');
          if (r.url.path.contains('/products') && denied) {
            return http.Response('{}', 403);
          }
          return w.call(r);
        }),
      );
    },
  );
}
