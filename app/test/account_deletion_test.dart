import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'dart:convert';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> signIn() async {
  await http.runWithClient(
    () => ApiService.instance.login(email: 'private@example.com', password: 'test'),
    () => MockClient((_) async => http.Response(jsonEncode({
      'access_token': 'original-token', 'expires_in': 3600,
      'user_id': 'original-user', 'role': 'patient',
    }), 200)),
  );
}

void main() {
  tearDown(() => ApiService.instance.init());
  for (final status in [204, 503]) {
    testWidgets('Delete UI response $status', (tester) async {
      SharedPreferences.setMockInitialValues({
        'dermaire_jwt_token': 'token',
        'dermaire_user_data': '{}',
      });
      await ApiService.instance.init();
      await signIn();
      final state = DermaireState(productRepository: MemoryProductRepository([]));
      state.userEmail = 'private@example.com';
      final pending = Completer<http.Response>();
      await http.runWithClient(() async {
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: ProfileTab(state: state))));
        await tester.scrollUntilVisible(find.text('Delete account'), 300);
        await tester.tap(find.text('Delete account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete permanently'));
        await tester.pump();
        expect(ApiService.instance.isAuthenticated, isTrue);
        pending.complete(http.Response('', status));
        await tester.pumpAndSettle();
        expect(find.byType(WelcomeScreen), status == 204 ? findsOneWidget : findsNothing);
        expect(ApiService.instance.isAuthenticated, status != 204 && status != 401);
        expect(state.userEmail, status == 204 ? isEmpty : 'private@example.com');
      }, () => MockClient((_) => pending.future));
      await tester.pumpWidget(const SizedBox());
      await ApiService.instance.init();
      state.dispose();
    });
  }

  for (final status in [204, 200, 202, 401, 503, -1]) {
    test('Deletion response $status preserves auth unless confirmed', () async {
      SharedPreferences.setMockInitialValues({
        'dermaire_jwt_token': 'original-token',
        'dermaire_user_data': jsonEncode({'user_id': 'original-user'}),
        'dermaire_products_v2': '[]',
        'dermaire_safety_accepted': true,
      });
      await ApiService.instance.init();
      await signIn();
      final cached = await SharedPreferences.getInstance();
      await cached.setString('dermaire_products_v2', '[]');
      await cached.setBool('dermaire_safety_accepted', true);
      final deleted = await http.runWithClient(
        () => ApiService.instance.deleteAccount(),
        () => MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, endsWith('/users/me'));
          expect(request.headers['Authorization'], 'Bearer original-token');
          if (status == -1) throw http.ClientException('Offline');
          return http.Response('', status);
        }),
      );
      expect(deleted, status == 204);
      expect(ApiService.instance.isAuthenticated, status != 204 && status != 401);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('dermaire_jwt_token'), isFalse);
      expect(prefs.containsKey('dermaire_products_v2'), status != 204 && status != 401);
      expect(prefs.containsKey('dermaire_safety_accepted'), status != 204 && status != 401);
    });
  }
  test('Clears account data held in memory', () async {
    final state = DermaireState(productRepository: MemoryProductRepository());
    await state.productController.load();
    state.userEmail = 'private@example.com';
    state.tokens = 20;
    state.journal.add(const JournalEntry('today', 'morning', 'Private'));
    state.clearAccountData();
    expect(state.userEmail, isEmpty);
    expect(state.tokens, 0);
    expect(state.journal, isEmpty);
    expect(state.productController.all, isEmpty);
    state.dispose();
  });
}
