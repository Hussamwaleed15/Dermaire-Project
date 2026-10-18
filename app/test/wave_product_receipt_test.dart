import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/products/product.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/products/products_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_authority_test.dart' as f;

Map<String, dynamic> row([int revision = 7]) => {
  ...f.row('Existing serum'),
  'revision': revision,
  'revision_protected': true,
};

class Wire {
  Map<String, dynamic>? current = row();
  Map<String, dynamic>? committed;
  String? key, originalBody, originalMatch;
  String kind = 'patch', loss = 'after';
  int writes = 0, lookupStatus = 200;
  bool lose = true;
  Map<String, dynamic> Function(Map<String, dynamic>)? changeReceipt;
  Completer<http.Response>? pendingLookup;
  final lookupSent = Completer<void>();
  final requests = <http.Request>[];
  Map<String, dynamic> receipt() {
    final result = committed;
    return {
      'schema_version': 1,
      'attempt_id': 'original-attempt',
      'owner_id': 'patient-1',
      'actor_id': 'patient-1',
      'operation': 'product_$kind',
      'status': result == null ? 'unknown' : 'committed',
      'result_availability': result == null ? 'unknown' : 'retained',
      if (result != null) ...{
        'resource_id': 'server-id',
        'resource_revision': result['revision'],
        'recorded_at': '2026-10-18T01:00:00Z',
        'expires_at': '2026-11-17T01:00:00Z',
      },
      'result': result,
    };
  }

  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    requests.add(r);
    if (r.url.path.endsWith('/auth/login')) return f.auth();
    if (r.url.path.endsWith('/users/me')) {
      return http.Response(
        '{"id":"patient-1","role":"patient","safety_accepted":true}',
        200,
      );
    }
    if (r.url.path.contains('/attempts/') ||
        r.url.path.contains('/operation-attempts/')) {
      expect(r.method, 'GET');
      expect(r.url.path.endsWith('/$key'), true);
      if (!lookupSent.isCompleted) lookupSent.complete();
      if (pendingLookup != null) return pendingLookup!.future;
      final value = receipt();
      return http.Response(
        jsonEncode(changeReceipt?.call(value) ?? value),
        lookupStatus,
      );
    }
    if (r.method != 'GET') {
      writes++;
      final sentKey = r.headers['Idempotency-Key'];
      expect(sentKey, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
      if (key == null) {
        key = sentKey;
        originalBody = r.body;
        originalMatch = r.headers['If-Match'];
      } else {
        expect(sentKey, key);
        expect(r.body, originalBody);
        expect(r.headers['If-Match'], originalMatch);
      }
      if (loss == 'before' && lose) throw TimeoutException('synthetic');
      if (committed == null) {
        if (kind == 'create') {
          expect(r.headers['If-Match'], isNull);
          current = {...row(1), ...jsonDecode(r.body) as Map<String, dynamic>};
          committed = Map.of(current!);
        } else if (kind == 'patch') {
          expect(r.headers['If-Match'], '"7"');
          current = {...row(9), ...jsonDecode(r.body) as Map<String, dynamic>};
          committed = Map.of(current!);
        } else {
          expect(r.headers['If-Match'], '"7"');
          expect(r.body, isEmpty);
          committed = {'deleted': true, 'id': 'server-id', 'revision': 8};
          current = null;
        }
      }
      if (lose) throw TimeoutException('synthetic');
      return kind == 'delete'
          ? http.Response('', 204)
          : http.Response(jsonEncode(committed), kind == 'create' ? 201 : 200);
    }
    if (r.url.path.endsWith('/products')) {
      return http.Response(jsonEncode(current == null ? [] : [current]), 200);
    }
    return http.Response(
      jsonEncode(current ?? {}),
      current == null ? 404 : 200,
    );
  }

  Future<bool> submit(ProductsController c) async {
    final result = kind == 'create'
        ? await c.add(Product.fromApi(row()).copyWith(name: 'New serum'))
        : kind == 'patch'
        ? await c.update(c.all.single.copyWith(notes: 'Exact original note'))
        : await c.delete(c.all.single.id);
    return result.success;
  }

  Future<void> run(Future<void> Function(ProductsController c) body) =>
      http.runWithClient(() async {
        await f.login();
        final c = ProductsController(RemoteProductRepository());
        await c.load();
        try {
          await body(c);
        } finally {
          c.dispose();
        }
      }, () => MockClient(call));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final kind in ['create', 'patch', 'delete']) {
    for (final loss in ['before', 'after']) {
      test(
        '$kind $loss response loss reconciles original operation without new key',
        () async {
          final w = Wire()
            ..kind = kind
            ..loss = loss;
          await w.run((c) async {
            expect(await w.submit(c), false);
            expect(c.pendingOperation, isNotNull);
            final body = c.pendingOperation!.body;
            // A different new operation is blocked even after a current-list refresh.
            await c.load();
            expect(
              (await c.update(
                Product.fromApi(row()).copyWith(notes: 'Other'),
              )).success,
              false,
            );
            expect(w.writes, 1);
            if (loss == 'before') {
              expect((await c.recoverProductOperation()).success, false);
              expect(c.pendingOperation!.lookupStatus, 'unknown');
              expect(
                (await c.recoverProductOperation(
                  finishUnavailableReview: true,
                )).success,
                false,
              );
              expect(c.pendingOperation, isNotNull);
              expect(c.pendingOperation!.body, body);
              expect(w.writes, 1);
              w.lose = false;
              expect(
                (await c.recoverProductOperation(retryOriginal: true)).success,
                true,
              );
              expect(w.writes, 2);
            } else {
              // Even explicit retry reconciles an existing commitment before POST.
              expect(
                (await c.recoverProductOperation(retryOriginal: true)).success,
                true,
              );
              expect(w.writes, 1);
            }
            expect(c.pendingOperation, isNull);
            expect(c.all.length, kind == 'delete' ? 0 : 1);
          });
        },
      );
    }
  }
  test(
    'old committed receipt never overwrites newer current product',
    () async {
      final w = Wire();
      await w.run((c) async {
        expect(await w.submit(c), false);
        w.current = {...row(17), 'notes': 'Changed on another device'};
        expect((await c.recoverProductOperation()).success, true);
        expect(c.all.single.serverRevision, 17);
        expect(c.all.single.notes, 'Changed on another device');
        expect(w.writes, 1);
      });
    },
  );
  test(
    'controller recreation retains exact session intent without claiming process restart',
    () async {
      final w = Wire();
      await http.runWithClient(() async {
        await f.login();
        final c = ProductsController(RemoteProductRepository());
        await c.load();
        expect(await w.submit(c), false);
        final key = c.pendingOperation!.key;
        c.dispose();
        final rebuilt = ProductsController(RemoteProductRepository());
        await rebuilt.load();
        expect(rebuilt.pendingOperation!.key, key);
        expect((await rebuilt.recoverProductOperation()).success, true);
        rebuilt.dispose();
      }, () => MockClient(w.call));
    },
  );
  for (final scenario in [
    'foreign owner',
    'wrong operation',
    'wrong resource',
    'wrong original revision',
    'invalid tombstone',
    'unknown with result',
  ]) {
    test('reject $scenario receipt without resolving uncertainty', () async {
      final w = Wire();
      if (scenario == 'invalid tombstone') w.kind = 'delete';
      w.changeReceipt = (v) {
        if (scenario == 'foreign owner') v['owner_id'] = 'another';
        if (scenario == 'wrong operation') v['operation'] = 'product_delete';
        if (scenario == 'wrong resource') v['resource_id'] = 'foreign';
        if (scenario == 'wrong original revision') v['resource_revision'] = 7;
        if (scenario == 'invalid tombstone') {
          v['result'] = {'deleted': false, 'id': 'server-id', 'revision': 8};
        }
        if (scenario == 'unknown with result') v['status'] = 'unknown';
        return v;
      };
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect((await c.recoverProductOperation()).success, false);
        expect(c.pendingOperation, isNotNull);
        expect(w.writes, 1);
      });
    });
  }
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    test(
      'receipt lookup $status cannot resolve or automatically replay',
      () async {
        final w = Wire()..lookupStatus = status;
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(
            (await c.recoverProductOperation(retryOriginal: true)).success,
            false,
          );
          expect(w.writes, 1);
          if (status == 401) {
            expect(c.all, isEmpty);
            expect(c.pendingOperation, isNull);
          } else {
            expect(c.pendingOperation, isNotNull);
          }
        });
      },
    );
  }
  for (final availability in ['expired', 'erased']) {
    test(
      '$availability original content is not fabricated or replayed',
      () async {
        final w = Wire()
          ..changeReceipt = (v) => {
            ...v,
            'status': availability == 'expired' ? 'expired' : 'committed',
            'result_availability': availability,
            'result': null,
          };
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(
            (await c.recoverProductOperation(retryOriginal: true)).success,
            false,
          );
          expect(c.pendingOperation, isNotNull);
          expect(w.writes, 1);
          expect(c.errorMessage, contains('expired or erased'));
          expect(
            (await c.recoverProductOperation(
              finishUnavailableReview: true,
            )).success,
            true,
          );
          expect(c.pendingOperation, isNull);
          expect(c.errorMessage, contains('No original request was repeated'));
          expect(w.writes, 1);
        });
      },
    );
  }
  test('delete503 plus current404 is not proof of SQL deletion', () async {
    final w = Wire()
      ..kind = 'delete'
      ..loss = 'before';
    await w.run((c) async {
      expect(await w.submit(c), false);
      w.current = null;
      expect((await c.recoverProductOperation()).success, false);
      expect(c.pendingOperation!.lookupStatus, 'unknown');
      expect(w.writes, 1);
    });
  });
  for (final next in ['logout', 'switch account']) {
    test(
      'late receipt after $next cannot repopulate or resolve another session',
      () async {
        final w = Wire()..pendingLookup = Completer<http.Response>();
        await w.run((c) async {
          expect(await w.submit(c), false);
          final resolution = c.recoverProductOperation();
          await w.lookupSent.future;
          await ApiService.instance.init();
          if (next == 'switch account') await f.login();
          w.pendingLookup!.complete(
            http.Response(jsonEncode(w.receipt()), 200),
          );
          expect((await resolution).success, false);
          expect(c.all, isEmpty);
          expect(c.pendingOperation, isNull);
        });
      },
    );
  }
  testWidgets(
    'real product recovery UI checks receipt and shows current library',
    (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final w = Wire();
      await http.runWithClient(() async {
        await f.login();
        final state = DermaireState();
        final c = state.productController;
        await c.load();
        expect(await w.submit(c), false);
        await t.pumpWidget(
          MaterialApp(
            theme: DermaireTheme.light,
            home: Scaffold(body: ProductsFeatureTab(state: state)),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Check original request'));
        await t.tap(find.text('Check original request'));
        await t.pumpAndSettle();
        expect(c.pendingOperation, isNull);
        expect(c.all.single.notes, 'Exact original note');
        expect(find.text('Retry original request'), findsNothing);
        expect(w.writes, 1);
        await t.pumpWidget(const SizedBox());
        state.dispose();
        await ApiService.instance.init();
      }, () => MockClient(w.call));
    },
  );
}
