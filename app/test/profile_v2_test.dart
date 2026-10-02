import 'dart:convert';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  test(
    'partial fields and explicit null survive request; server is authoritative',
    () async {
      await http.runWithClient(
        () async {
          final result = await ApiService.instance.updateSkinProfile(
            fields: {
              'profile_context': {'sex': 'prefer_not_to_say', 'age_band': null},
            },
          );
          expect(result['skin_concerns'], ['Legacy']);
          expect(ApiService.instance.currentUser, result);
        },
        () => MockClient((req) async {
          expect(jsonDecode(req.body), {
            'profile_context': {'sex': 'prefer_not_to_say', 'age_band': null},
          });
          return http.Response(
            '{"skin_concerns":["Legacy"],"profile_context":{"sex":"prefer_not_to_say"}}',
            200,
          );
        }),
      );
    },
  );
  test(
    'fake success is rejected and does not replace server profile',
    () async {
      for (final status in [200, 202, 503]) {
        await http.runWithClient(() async {
          await expectLater(
            ApiService.instance.updateSkinProfile(
              fields: {
                'profile_context': {'sex': 'prefer_not_to_say'},
              },
            ),
            throwsA(isA<ApiException>()),
          );
          expect(ApiService.instance.currentUser, isNull);
        }, () => MockClient((req) async => http.Response('{}', status)));
      }
    },
  );
  testWidgets('failed save stays on profile and reports error', (tester) async {
    final state = DermaireState();
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(home: SkinProfileScreen(state: state)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('saveProfile')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.byKey(const Key('saveProfile')));
        await tester.tap(find.byKey(const Key('saveProfile')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('profileError')),
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(
            'Save was not confirmed. Your draft is still here. Please retry.',
          ),
          findsOneWidget,
        );
        expect(find.byType(SkinProfileScreen), findsOneWidget);
        expect(state.skinConcerns, isEmpty);
      },
      () => MockClient(
        (req) async => req.method == 'GET'
            ? http.Response('{"skin_concerns":[],"profile_context":null}', 200)
            : http.Response('unavailable', 503),
      ),
    );
    state.dispose();
  });
  testWidgets('failed read shows retry without editable defaults', (
    tester,
  ) async {
    final state = DermaireState();
    await http.runWithClient(() async {
      await tester.pumpWidget(
        MaterialApp(home: SkinProfileScreen(state: state)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byKey(const Key('saveProfile')), findsNothing);
    }, () => MockClient((req) async => http.Response('{}', 500)));
    state.dispose();
  });
}
