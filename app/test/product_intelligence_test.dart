import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/products/product_intelligence_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> response({
  bool facts = false,
  bool complete = false,
  bool warning = false,
}) => {
  'product_id': 'p',
  'state': facts ? 'facts_available' : 'unknown',
  'data_completeness': complete ? 'complete' : 'incomplete',
  'facts': {
    'region': facts ? {'value': 'EG', 'source_id': 'label'} : null,
    'sources': [
      {
        'id': 'label',
        'type': 'manufacturer_label',
        'verification': 'verified',
        'confidence': 'high',
        'reference': 'Reviewed label',
      },
    ],
  },
  'ingredients': facts
      ? [
          {
            'name': 'Niacinamide',
            'source_id': 'label',
            'strength': {'value': '5%', 'source_id': 'label'},
          },
          {'name': 'Aqua', 'source_id': 'label', 'strength': null},
        ]
      : [],
  'warnings': warning
      ? [
          {
            'severity': 'info',
            'explanation':
                'Two routine products report the same active ingredient.',
            'confidence': 'low',
            'data_completeness': 'incomplete',
          },
        ]
      : [],
  'unknowns': complete ? [] : ['complete_ingredient_list'],
  'limitations': ['No warning does not establish safety.'],
};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });

  testWidgets('loading and unknown/incomplete states render server data', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductIntelligencePanel(
            productId: 'p',
            load: () => pending.future,
          ),
        ),
      ),
    );
    expect(find.text('Loading product intelligence…'), findsOneWidget);
    pending.complete(response());
    await tester.pumpAndSettle();
    expect(find.text('Ingredient intelligence is unknown.'), findsOneWidget);
    expect(
      find.textContaining('ingredient information is incomplete'),
      findsOneWidget,
    );
    expect(
      find.textContaining('No warning does not establish safety'),
      findsOneWidget,
    );
  });

  testWidgets(
    'facts, explicit strengths and provenance render without invented facts',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductIntelligencePanel(
              productId: 'p',
              load: () async => response(facts: true, complete: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Niacinamide · 5%'), findsOneWidget);
      expect(find.textContaining('Aqua · Strength unknown'), findsOneWidget);
      expect(
        find.textContaining('manufacturer_label · verified · high'),
        findsOneWidget,
      );
      expect(find.textContaining('region: EG'), findsOneWidget);
      expect(
        find.textContaining('ingredient information is incomplete'),
        findsNothing,
      );
    },
  );

  testWidgets('warnings display exactly as received', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductIntelligencePanel(
            productId: 'p',
            load: () async => response(facts: true, warning: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Two routine products report the same active'),
      findsOneWidget,
    );
    expect(find.textContaining('Evidence confidence: low'), findsOneWidget);
  });

  testWidgets('failure and retry have no fabricated intelligence', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProductIntelligencePanel(
            productId: 'p',
            load: () async {
              if (++calls == 1) throw StateError('Offline');
              return response();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Product intelligence unavailable.'), findsOneWidget);
    expect(find.textContaining('Niacinamide'), findsNothing);
    await tester.tap(find.text('Retry intelligence'));
    await tester.pumpAndSettle();
    expect(find.text('Ingredient intelligence is unknown.'), findsOneWidget);
  });

  test(
    'API uses authenticated server evidence and only relevant routine warnings',
    () async {
      await http.runWithClient(
        () async {
          await ApiService.instance.login(
            email: 'test@example.com',
            password: 'test',
          );
          final result = await ApiService.instance.getProductIntelligence('p');
          expect(result['warnings'], isEmpty);
          expect((result['routine_warnings'] as List).length, 1);
          expect(result['ingredients'], isEmpty);
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            return http.Response(
              jsonEncode({
                'access_token': 'test-session',
                'expires_in': 3600,
                'user_id': 'u',
                'role': 'patient',
              }),
              200,
            );
          }
          expect(request.headers['Authorization'], 'Bearer test-session');
          if (request.url.path.endsWith('/products/p/intelligence')) {
            return http.Response(jsonEncode(response()), 200);
          }
          if (request.url.path.endsWith('/routine/intelligence')) {
            return http.Response(
              jsonEncode({
                'warnings': [
                  {
                    'key': 'server_warning',
                    'evidence': [
                      {'product_id': 'p'},
                    ],
                  },
                  {
                    'key': 'other_product',
                    'evidence': [
                      {'product_id': 'other'},
                    ],
                  },
                ],
              }),
              200,
            );
          }
          throw StateError('Unexpected request');
        }),
      );
      await ApiService.instance.init();
    },
  );

  test('API rejects unavailable and foreign product responses', () async {
    for (final status in [404, 503, 200]) {
      await http.runWithClient(
        () async {
          await expectLater(
            ApiService.instance.getProductIntelligence('foreign'),
            throwsA(isA<ApiException>()),
          );
        },
        () => MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path.endsWith('/routine/intelligence')
                  ? {'warnings': []}
                  : response(),
            ),
            status,
          ),
        ),
      );
    }
  });

  test('API discards intelligence received after session changes', () async {
    final pending = Completer<http.Response>();
    await http.runWithClient(
      () async {
        await ApiService.instance.login(
          email: 'test@example.com',
          password: 'test',
        );
        final request = ApiService.instance.getProductIntelligence('p');
        final rejected = expectLater(request, throwsA(isA<ApiException>()));
        await ApiService.instance.init();
        pending.complete(http.Response(jsonEncode(response()), 200));
        await rejected;
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'test-session',
              'expires_in': 3600,
              'user_id': 'u',
              'role': 'patient',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/routine/intelligence')) {
          return http.Response(jsonEncode({'warnings': []}), 200);
        }
        return pending.future;
      }),
    );
  });
}
