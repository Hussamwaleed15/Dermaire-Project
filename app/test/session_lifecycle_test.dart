import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/main.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> login({int ttl = 3600}) => ApiService.instance
    .login(email: 'test@example.com', password: 'test')
    .then((_) {});

http.Response authResponse({int ttl = 3600, String token = 'session-token'}) =>
    http.Response(
      jsonEncode({
        'access_token': token,
        'expires_in': ttl,
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

  test('legacy stale session is never restored', () async {
    SharedPreferences.setMockInitialValues({
      'dermaire_jwt_token': 'expired-or-invalid',
      'dermaire_user_data': '{malformed',
      'dermaire_products_v2': 'private',
      'dermaire_safety_accepted': true,
    });
    await ApiService.instance.init();
    expect(ApiService.instance.isAuthenticated, isFalse);
    expect(ApiService.instance.currentUser, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  for (final operation in ['profile', 'products', 'upload']) {
    test('401 clears session and health state for $operation', () async {
      final state = DermaireState(
        productRepository: MemoryProductRepository([]),
      );
      await http.runWithClient(
        () async {
          await login();
          state.journal.add(const JournalEntry('today', 'morning', 'private'));
          expect(ApiService.instance.isAuthenticated, isTrue);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.containsKey('dermaire_jwt_token'), isFalse);
          expect(prefs.containsKey('dermaire_user_data'), isFalse);
          final Future<Object?> request = switch (operation) {
            'products' => ApiService.instance.getProducts(),
            'upload' => ApiService.instance.submitCheckIn(
              timeOfDay: 'morning',
              hydration: 1,
              texture: 1,
              redness: 1,
              photoBytes: [1, 2],
            ),
            _ => ApiService.instance.getCurrentUser(),
          };
          await expectLater(request, throwsA(isA<ApiException>()));
          expect(ApiService.instance.isAuthenticated, isFalse);
          expect(ApiService.instance.currentUser, isNull);
          expect(state.userEmail, isEmpty);
          expect(state.journal, isEmpty);
        },
        () => MockClient(
          (req) async => req.url.path.endsWith('/auth/login')
              ? authResponse()
              : http.Response('not even JSON', 401),
        ),
      );
      state.dispose();
    });
  }

  for (final status in [200, 403, 500]) {
    test('profile response $status keeps valid session', () async {
      await http.runWithClient(
        () async {
          await login();
          final profile = await ApiService.instance.getCurrentUser();
          expect(profile, status == 200 ? isNotNull : isNull);
          expect(ApiService.instance.isAuthenticated, isTrue);
          await ApiService.instance.init();
        },
        () => MockClient(
          (req) async => req.url.path.endsWith('/auth/login')
              ? authResponse()
              : http.Response('{"email":"test@example.com"}', status),
        ),
      );
    });
  }

  test('logout clears locally and sends server revocation', () async {
    var revoked = false;
    await http.runWithClient(
      () async {
        await login();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('dermaire_products_v2', 'private');
        await prefs.setBool('dermaire_safety_accepted', true);
        await ApiService.instance.logout();
        expect(revoked, isTrue);
        expect(ApiService.instance.authToken, isNull);
        expect(ApiService.instance.currentUser, isNull);
        expect(prefs.getKeys(), isEmpty);
      },
      () => MockClient((req) async {
        if (req.url.path.endsWith('/auth/login')) {
          return authResponse();
        }
        expect(req.url.path, endsWith('/auth/logout'));
        expect(req.headers['Authorization'], 'Bearer session-token');
        expect(ApiService.instance.isAuthenticated, isFalse);
        revoked = true;
        return http.Response('', 204);
      }),
    );
  });

  test('successful password reset clears local session', () async {
    await http.runWithClient(
      () async {
        await login();
        await ApiService.instance.resetPassword(
          email: 'test@example.com',
          token: 'test-code',
          newPassword: 'new-test-password',
        );
        expect(ApiService.instance.isAuthenticated, isFalse);
        expect(ApiService.instance.currentUser, isNull);
      },
      () => MockClient(
        (req) async => req.url.path.endsWith('/auth/login')
            ? authResponse()
            : http.Response('{}', 200),
      ),
    );
  });

  test('offline logout clears local session', () async {
    await http.runWithClient(
      () async {
        await login();
        await ApiService.instance.logout();
        expect(ApiService.instance.isAuthenticated, isFalse);
      },
      () => MockClient((req) async {
        if (req.url.path.endsWith('/auth/login')) {
          return authResponse();
        }
        throw http.ClientException('offline');
      }),
    );
  });

  test('late responses cannot repopulate a logged out profile', () async {
    final pending = Completer<http.Response>();
    await http.runWithClient(
      () async {
        await login();
        final profile = ApiService.instance.getCurrentUser();
        final rejected = expectLater(profile, throwsA(isA<ApiException>()));
        await ApiService.instance.logout();
        pending.complete(http.Response('{"email":"private@example.com"}', 200));
        await rejected;
        expect(ApiService.instance.currentUser, isNull);
      },
      () => MockClient((req) async {
        if (req.url.path.endsWith('/auth/login')) {
          return authResponse();
        }
        if (req.url.path.endsWith('/auth/logout')) {
          return http.Response('', 204);
        }
        return pending.future;
      }),
    );
  });

  testWidgets('idle expiry clears UI routes and private state', (tester) async {
    await http.runWithClient(() async {
      await tester.pumpWidget(const DermaireApp());
      await tester.pumpAndSettle();
      await login();
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Private session page')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Private session page'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(ApiService.instance.isAuthenticated, isFalse);
      expect(find.text('Private session page'), findsNothing);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => MockClient((_) async => authResponse(ttl: 2)));
  });
}
