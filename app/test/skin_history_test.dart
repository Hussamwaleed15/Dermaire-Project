import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';

Map<String, dynamic> event(String id) => {
  'id': id,
  'user_id': 'patient-1',
  'time_of_day': 'Morning',
  'created_at': '2026-10-01T12:00:00',
  'ai_vision_analysis': {'measurement_source': 'none'},
  'observation': {
    'schema_version': 1,
    'user_reported': {
      'overall_change': 'same',
      'symptoms': [],
      'routine_status': null,
    },
    'daily_context_date': '2026-10-01',
    'daily_context_id': null,
    'provenance': {'report': 'user_reported'},
  },
};

Future<void> patientLogin() async {
  await ApiService.instance.login(
    email: 'synthetic@example.invalid',
    password: 'Synthetic123!',
  );
  await ApiService.instance.readSafetyAcceptance();
}

MockClient uiTransport(
  Future<http.Response> Function(http.Request) action,
) => MockClient((request) {
  expectSync(request.url.host, 'flutter-tests.invalid');
  if (request.url.path.endsWith('/auth/login')) {
    return Future.value(
      http.Response(
        '{"access_token":"synthetic-token","expires_in":3600,"user_id":"patient-1","role":"patient"}',
        200,
      ),
    );
  }
  if (request.url.path.endsWith('/users/me')) {
    return Future.value(
      http.Response('{"id":"patient-1","safety_accepted":true}', 200),
    );
  }
  return action(request);
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'report-only confirmation and history preserve server order without optional links',
    () async {
      await http.runWithClient(
        () async {
          final saved = await ApiService.instance.submitCheckIn(
            timeOfDay: 'Morning',
            report: {'overall_change': 'same', 'symptoms': []},
          );
          expect(saved['id'], 'new');
          expect(saved['hydration_score'], isNull);
          expect(
            (await ApiService.instance.getCheckIns()).map((e) => e['id']),
            ['new', 'old'],
          );
        },
        () => MockClient((request) async {
          if (request.method == 'POST') {
            expect(request.body, contains('overall_change'));
            expect(request.body, isNot(contains('hydration_score')));
            return http.Response(jsonEncode(event('new')), 201);
          }
          return http.Response(jsonEncode([event('new'), event('old')]), 200);
        }),
      );
    },
  );

  test('HTTP failure and missing report confirmation never succeed', () async {
    for (final status in [503, 201]) {
      await http.runWithClient(() async {
        await expectLater(
          ApiService.instance.submitCheckIn(
            timeOfDay: 'Morning',
            report: {'overall_change': 'same', 'symptoms': []},
          ),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          ApiService.instance.getCheckIns(),
          throwsA(isA<ApiException>()),
        );
      }, () => MockClient((_) async => http.Response('{}', status)));
    }
  });

  testWidgets('history shows empty, error, retry and server events honestly', (
    tester,
  ) async {
    var status = 200;
    var rows = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await patientLogin();
      final state = DermaireState();
      await tester.pumpWidget(MaterialApp(home: TimelineScreen(state: state)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No saved observations yet'), findsOneWidget);
      status = 503;
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Skin history unavailable'), findsOneWidget);
      expect(find.textContaining('No saved observations yet'), findsNothing);
      status = 200;
      rows = [event('real')];
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.text('User reported: same'), findsOneWidget);
      expect(find.textContaining('not linked at submission'), findsOneWidget);
      expect(find.textContaining('Demo timeline'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await ApiService.instance.init();
    }, () => uiTransport((_) async => http.Response(jsonEncode(rows), status)));
  });

  testWidgets('pending history displays loading without empty success', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await patientLogin();
      final state = DermaireState();
      await tester.pumpWidget(MaterialApp(home: TimelineScreen(state: state)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('No saved observations yet'), findsNothing);
      pending.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      await ApiService.instance.init();
    }, () => uiTransport((_) => pending.future));
  });

  test('server must confirm all submitted report fields', () async {
    await http.runWithClient(
      () async {
        await expectLater(
          ApiService.instance.submitCheckIn(
            timeOfDay: 'Morning',
            report: {
              'overall_change': 'same',
              'symptoms': ['dryness'],
              'routine_status': 'followed',
            },
          ),
          throwsA(isA<ApiException>()),
        );
      },
      () => uiTransport(
        (_) async => http.Response(jsonEncode(event('incomplete')), 201),
      ),
    );
  });

  testWidgets('structured form failure never opens completion screen', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await patientLogin();
        final state = DermaireState();
        await tester.pumpWidget(MaterialApp(home: CameraScreen(state: state)));
        final pageScroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.byKey(const Key('change_same')),
          150,
          scrollable: pageScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('change_same')));
        await tester.tap(find.byKey(const Key('moment_Morning')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('reviewObservation')),
          200,
          scrollable: pageScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reviewObservation')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('submitObservation')),
          200,
          scrollable: pageScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('submitObservation')));
        await tester.pumpAndSettle();
        expect(find.text('Save outcome uncertain'), findsOneWidget);
        expect(find.text('Observation saved'), findsNothing);
        expect(find.byKey(const Key('submitObservation')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        state.dispose();
        await ApiService.instance.init();
      },
      () => uiTransport((request) async {
        if (request.method != 'POST') return http.Response('{}', 503);
        expect(request.body, contains('overall_change'));
        expect(request.body, isNot(contains('hydration_score')));
        return http.Response('{"message":"Unavailable"}', 503);
      }),
    );
  });
}
