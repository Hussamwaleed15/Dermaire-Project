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

Map<String, dynamic> row([int revision = 7, bool protected = true]) => {
  ...f.row('Original serum'),
  'revision': revision,
  'revision_protected': protected,
};
http.Response json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status);
Future<http.Response?> auth(http.Request r) async {
  expect(r.url.host, 'flutter-tests.invalid');
  if (r.url.path.endsWith('/auth/login')) return f.auth();
  if (r.url.path.endsWith('/users/me')) {
    return json({
      'id': 'patient-1',
      'role': 'patient',
      'safety_accepted': true,
    });
  }
  return null;
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final invalid in [null, 0, -1, 2147483648, '7', 7.0, true]) {
    test('reject product revision $invalid (${invalid.runtimeType})', () {
      expect(
        () => Product.fromApi(row()..['revision'] = invalid),
        throwsFormatException,
      );
    });
  }
  for (final field in ['revision', 'revision_protected']) {
    test('partial protection metadata without $field fails closed', () {
      expect(
        () => Product.fromApi(row()..remove(field)),
        throwsFormatException,
      );
    });
  }
  test('invalid protection type fails closed', () {
    expect(
      () => Product.fromApi(row()..['revision_protected'] = 'true'),
      throwsFormatException,
    );
  });
  test('original metadata survives edits and stays out of writable fields', () {
    final p = Product.fromApi(
      row(),
    ).copyWith(notes: 'Edit', updatedAt: DateTime.now());
    expect(p.serverRevision, 7);
    expect(p.revisionProtected, true);
    expect(p.owner, 'patient-1');
    expect(p.toApi().keys, isNot(contains('revision')));
    expect(p.toApi().keys, isNot(contains('revision_protected')));
    expect(p.toJson().keys, isNot(contains('serverRevision')));
    final legacy = Product.fromApi(f.row('Legacy'));
    expect(legacy.serverRevision, isNull);
    expect(legacy.revisionProtected, isNull);
  });
  for (final protected in [false, true]) {
    test(
      'update sends quoted original revision; previously protected=$protected',
      () async {
        var current = row(7, protected), writes = 0;
        await http.runWithClient(
          () async {
            await f.login();
            final c = ProductsController(RemoteProductRepository());
            await c.load();
            expect(
              (await c.update(
                c.all.single.copyWith(notes: 'New note'),
              )).success,
              true,
            );
            expect(c.all.single.serverRevision, 11); // Do not assume +1.
            expect(c.all.single.revisionProtected, true);
            expect(writes, 1);
            c.dispose();
          },
          () => MockClient((r) async {
            final a = await auth(r);
            if (a != null) return a;
            if (r.method == 'PATCH') {
              writes++;
              expect(r.headers['If-Match'], '"7"');
              expect(jsonDecode(r.body), {'notes': 'New note'});
              current = {...row(11), 'notes': 'New note'};
              return json(current);
            }
            return json(r.url.path.endsWith('/products') ? [current] : current);
          }),
        );
      },
    );
  }
  for (final status in [401, 403, 409, 410, 412, 422, 428, 503]) {
    test('mutation $status never claims success', () async {
      var writes = 0;
      await http.runWithClient(
        () async {
          await f.login();
          final c = ProductsController(RemoteProductRepository());
          await c.load();
          final result = await c.update(c.all.single.copyWith(notes: 'New'));
          expect(result.success, false);
          if (status == 401) {
            expect(c.all, isEmpty);
          } else {
            expect(c.all.single.serverRevision, 7);
            expect(c.isStale, true);
            if (status == 412) {
              expect(result.message, contains('reopen the editor'));
            }
            if (status == 428) {
              expect(result.message, contains('revision is required'));
            }
          }
          expect(writes, 1);
          c.dispose();
        },
        () => MockClient((r) async {
          final a = await auth(r);
          if (a != null) return a;
          if (r.method == 'PATCH') {
            writes++;
            return json({}, status);
          }
          return json(r.url.path.endsWith('/products') ? [row()] : row());
        }),
      );
    });
  }
  for (final operation in ['update', 'delete']) {
    test(
      '$operation rejects revision change even if timestamps match',
      () async {
        var version = 7, writes = 0;
        await http.runWithClient(
          () async {
            await f.login();
            final c = ProductsController(RemoteProductRepository());
            await c.load();
            final old = c.all.single;
            version = 8;
            final result = operation == 'update'
                ? await c.update(old.copyWith(notes: 'Stale'))
                : await c.delete(old.id);
            expect(result.success, false);
            expect(writes, 0);
            c.dispose();
          },
          () => MockClient((r) async {
            final a = await auth(r);
            if (a != null) return a;
            if (r.method != 'GET') writes++;
            return json(
              r.url.path.endsWith('/products') ? [row(version)] : row(version),
            );
          }),
        );
      },
    );
  }
  test(
    'race after preflight uses original revision with no silent rebase/retry',
    () async {
      var gets = 0, writes = 0;
      await http.runWithClient(
        () async {
          await f.login();
          final c = ProductsController(RemoteProductRepository());
          await c.load();
          expect(
            (await c.update(c.all.single.copyWith(notes: 'Stale'))).success,
            false,
          );
          expect(gets, 1);
          expect(writes, 1);
          c.dispose();
        },
        () => MockClient((r) async {
          final a = await auth(r);
          if (a != null) return a;
          if (r.method == 'PATCH') {
            writes++;
            expect(r.headers['If-Match'], '"7"');
            return json({}, 412);
          }
          if (!r.url.path.endsWith('/products')) gets++;
          return json(r.url.path.endsWith('/products') ? [row()] : row());
        }),
      );
    },
  );
  test(
    'delete carries reviewed original revision and confirms absent readback',
    () async {
      var deleted = false;
      await http.runWithClient(
        () async {
          await f.login();
          final c = ProductsController(RemoteProductRepository());
          await c.load();
          expect((await c.delete(c.all.single.id)).success, true);
          expect(c.all, isEmpty);
          c.dispose();
        },
        () => MockClient((r) async {
          final a = await auth(r);
          if (a != null) return a;
          if (r.method == 'DELETE') {
            expect(r.headers['If-Match'], '"7"');
            deleted = true;
            return http.Response('', 204);
          }
          if (deleted) return json({}, 404);
          return json(r.url.path.endsWith('/products') ? [row()] : row());
        }),
      );
    },
  );
  test('late mutation after logout cannot restore data or success', () async {
    final reply = Completer<http.Response>(), sent = Completer<void>();
    await http.runWithClient(
      () async {
        await f.login();
        final c = ProductsController(RemoteProductRepository());
        await c.load();
        final saving = c.update(c.all.single.copyWith(notes: 'New'));
        await sent.future;
        await ApiService.instance.init();
        reply.complete(json({...row(8), 'notes': 'New'}));
        expect((await saving).success, false);
        expect(c.all, isEmpty);
        c.dispose();
      },
      () => MockClient((r) async {
        final a = await auth(r);
        if (a != null) return a;
        if (r.method == 'PATCH') {
          sent.complete();
          return reply.future;
        }
        return json(r.url.path.endsWith('/products') ? [row()] : row());
      }),
    );
  });
  for (final saveStatus in [200, 412]) {
    testWidgets(
      'real editor preserves original identity and handles save $saveStatus',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var current = row(), writes = 0;
        await http.runWithClient(
          () async {
            await f.login();
            final state = DermaireState();
            await state.productController.load();
            await tester.pumpWidget(
              MaterialApp(
                theme: DermaireTheme.light,
                home: ProductEditorScreen(
                  state: state,
                  product: state.productController.all.single,
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.enterText(
              find.byKey(const Key('productName')),
              'Edited serum',
            );
            await tester.ensureVisible(find.byKey(const Key('saveProduct')));
            await tester.tap(find.byKey(const Key('saveProduct')));
            await tester.pumpAndSettle();
            expect(writes, 1);
            if (saveStatus == 200) {
              expect(state.productController.all.single.name, 'Edited serum');
            } else {
              expect(state.productController.all.single.name, 'Original serum');
              expect(find.textContaining('reopen the editor'), findsOneWidget);
            }
            await tester.pumpWidget(const SizedBox());
            state.dispose();
            await ApiService.instance.init();
          },
          () => MockClient((r) async {
            final a = await auth(r);
            if (a != null) return a;
            if (r.method == 'PATCH') {
              writes++;
              expect(r.headers['If-Match'], '"7"');
              if (saveStatus != 200) return json({}, saveStatus);
              current = {
                ...current,
                ...jsonDecode(r.body) as Map<String, dynamic>,
                'revision': 8,
              };
              return json(current);
            }
            return json(r.url.path.endsWith('/products') ? [current] : current);
          }),
        );
      },
    );
  }
}
