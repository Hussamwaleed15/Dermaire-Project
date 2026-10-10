import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/products/product.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row(String name) => {
  'id': 'server-id',
  'name': name,
  'category': 'serum',
  'active_ingredients': ['Niacinamide'],
  'skin_concerns': ['Dryness'],
  'usage_instructions': 'Apply',
  'frequency_per_week': 3,
  'time_of_use': 'both',
  'in_routine': false,
  'in_experiment': false,
  'created_at': '2026-10-01T00:00:00',
  'updated_at': '2026-10-01T01:00:00',
  'start_date': '2026-10-01T00:00:00',
  'tags': ['barrier'],
};
Future<void> login() async {
  await ApiService.instance.login(email: 'test@example.com', password: 'test');
}

http.Response auth() => http.Response(
  jsonEncode({
    'access_token': 'test-session',
    'expires_in': 3600,
    'user_id': 'patient-1',
    'role': 'patient',
  }),
  200,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());

  testWidgets(
    'sign-in loads authoritative products and stale warning keeps list readable',
    (tester) async {
      final state = DermaireState();
      var fail = false;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(home: SignInScreen(state: state)),
          );
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('signInEmail')),
            'test@example.com',
          );
          await tester.enterText(
            find.byKey(const Key('signInPassword')),
            'Password123!',
          );
          await tester.tap(find.byKey(const Key('signInButton')));
          await tester.pumpAndSettle();
          expect(find.byType(AppShell), findsOneWidget);
          expect(state.productController.all.single.name, 'Backend serum');
          state.selectTab(2);
          await tester.pumpAndSettle();
          fail = true;
          await state.productController.load();
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Displayed data may be stale'),
            findsOneWidget,
          );
          expect(find.text('Backend serum'), findsOneWidget);
          expect(find.text('Retry refresh'), findsOneWidget);
          fail = false;
          await tester.tap(find.text('Retry refresh'));
          await tester.pumpAndSettle();
          expect(state.productController.isStale, isFalse);
          await ApiService.instance.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('/auth/login')) return auth();
          if (req.url.path.endsWith('/users/me')) {
            return http.Response(
              '{"id":"patient-1","safety_accepted":true}',
              200,
            );
          }
          return http.Response(
            fail ? 'unavailable' : jsonEncode([row('Backend serum')]),
            fail ? 503 : 200,
          );
        }),
      );
      state.dispose();
    },
  );

  test('server IDs and fields drive create patch refresh and delete', () async {
    var rows = <Map<String, dynamic>>[];
    await http.runWithClient(
      () async {
        await login();
        final controller = ProductsController(RemoteProductRepository());
        await controller.load();
        expect(controller.all, isEmpty);
        final draft = Product.fromApi(row('Draft')).copyWith(id: 'local-id');
        expect((await controller.add(draft)).success, isTrue);
        expect(controller.all.single.id, 'server-id');
        expect(controller.all.single.name, 'Server accepted');
        expect(controller.all.single.activeIngredients, ['Niacinamide']);
        expect(controller.all.single.timeOfUse, UsageTime.both);
        expect(controller.all.single.inRoutine, isFalse);
        expect(
          (await controller.update(
            controller.all.single.copyWith(notes: 'Edited'),
          )).success,
          isTrue,
        );
        expect(controller.all.single.name, 'Patched by server');
        final rebuilt = ProductsController(RemoteProductRepository());
        await rebuilt.load();
        expect(rebuilt.all.single.name, 'Patched by server');
        expect((await controller.delete('server-id')).success, isTrue);
        await rebuilt.load();
        expect(rebuilt.all, isEmpty);
      },
      () => MockClient((req) async {
        if (req.url.path.endsWith('/auth/login')) return auth();
        expect(req.headers['Authorization'], 'Bearer test-session');
        if (req.method == 'POST' || req.method == 'PATCH') {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          expect(body['active_ingredients'], ['Niacinamide']);
          expect(body.containsKey('createdAt'), isFalse);
          expect(body.containsKey('id'), isFalse);
          rows = [
            row(req.method == 'POST' ? 'Server accepted' : 'Patched by server'),
          ];
          return http.Response(
            jsonEncode(rows.single),
            req.method == 'POST' ? 201 : 200,
          );
        }
        if (req.method == 'DELETE') {
          rows = [];
          return http.Response('', 204);
        }
        return http.Response(jsonEncode(rows), 200);
      }),
    );
  });

  test(
    'server failure keeps explicit stale cache and never reports fake success',
    () async {
      var fail = false;
      var empty = false;
      await http.runWithClient(
        () async {
          await login();
          final controller = ProductsController(RemoteProductRepository());
          await controller.load();
          fail = true;
          expect(
            (await controller.add(Product.fromApi(row('New')))).success,
            isFalse,
          );
          expect(controller.all.single.name, 'Cached');
          expect(controller.isStale, isTrue);
          await controller.load();
          expect(controller.all.single.name, 'Cached');
          expect(controller.errorMessage, isNotNull);
          expect((await controller.delete('server-id')).success, isFalse);
          final restarted = ProductsController(RemoteProductRepository());
          await restarted.load();
          expect(restarted.all, isEmpty);
          expect(restarted.errorMessage, isNotNull);
          fail = false;
          empty = true;
          await controller.load();
          expect(controller.all, isEmpty);
          expect(controller.isStale, isFalse);
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('/auth/login')) return auth();
          if (fail) return http.Response('server failed', 503);
          return http.Response(jsonEncode(empty ? [] : [row('Cached')]), 200);
        }),
      );
    },
  );

  test(
    'late product read cannot repopulate logged out state; restart clears legacy data',
    () async {
      final pending = Completer<http.Response>();
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login();
          final load = state.productController.load();
          await ApiService.instance.logout();
          pending.complete(http.Response(jsonEncode([row('Private')]), 200));
          await load;
          expect(state.productController.all, isEmpty);
          expect(state.productController.errorMessage, isNull);
          SharedPreferences.setMockInitialValues({
            'dermaire_products_v2': '[demo]',
          });
          await ApiService.instance.init();
          expect(ApiService.instance.isAuthenticated, isFalse);
          expect(
            (await SharedPreferences.getInstance()).containsKey(
              'dermaire_products_v2',
            ),
            isFalse,
          );
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('/auth/login')) return auth();
          if (req.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }
          return pending.future;
        }),
      );
      state.dispose();
    },
  );
}
