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
  'id': id, 'created_at': '2026-10-01T12:00:00',
  'ai_vision_analysis': {'measurement_source': 'none'},
  'observation': {'schema_version': 1, 'user_reported': {
    'overall_change': 'same', 'symptoms': [], 'routine_status': null},
    'daily_context_date': '2026-10-01', 'daily_context_id': null,
    'provenance': {'report': 'user_reported'}},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('report-only confirmation and history preserve server order without optional links', () async {
    await http.runWithClient(() async {
      final saved = await ApiService.instance.submitCheckIn(timeOfDay: 'Morning',
          report: {'overall_change': 'same', 'symptoms': []});
      expect(saved['id'], 'new');
      expect(saved['hydration_score'], isNull);
      expect((await ApiService.instance.getCheckIns()).map((e) => e['id']), ['new', 'old']);
    }, () => MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.body, contains('overall_change'));
        expect(request.body, isNot(contains('hydration_score')));
        return http.Response(jsonEncode(event('new')), 201);
      }
      return http.Response(jsonEncode([event('new'), event('old')]), 200);
    }));
  });

  test('HTTP failure and missing report confirmation never succeed', () async {
    for (final status in [503, 201]) {
      await http.runWithClient(() async {
        await expectLater(ApiService.instance.submitCheckIn(timeOfDay: 'Morning',
          report: {'overall_change': 'same', 'symptoms': []}), throwsA(isA<ApiException>()));
        await expectLater(ApiService.instance.getCheckIns(), throwsA(isA<ApiException>()));
      }, () => MockClient((_) async => http.Response('{}', status)));
    }
  });

  testWidgets('history shows empty, error, retry and server events honestly', (tester) async {
    var status = 200;
    var rows = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      final state = DermaireState();
      await tester.pumpWidget(MaterialApp(home: TimelineScreen(state: state)));
      await tester.pumpAndSettle();
      expect(find.textContaining('No check-ins yet'), findsOneWidget);
      status = 503;
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Skin history unavailable'), findsOneWidget);
      expect(find.textContaining('No check-ins yet'), findsNothing);
      status = 200;
      rows = [event('real')];
      await tester.tap(find.text('Refresh history'));
      await tester.pumpAndSettle();
      expect(find.text('User reported: same'), findsOneWidget);
      expect(find.textContaining('not linked at submission'), findsOneWidget);
      expect(find.textContaining('Demo timeline'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    }, () => MockClient((_) async => http.Response(jsonEncode(rows), status)));
  });

  testWidgets('pending history displays loading without empty success', (tester) async {
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      final state = DermaireState();
      await tester.pumpWidget(MaterialApp(home: TimelineScreen(state: state)));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('No check-ins yet'), findsNothing);
      pending.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    }, () => MockClient((_) => pending.future));
  });

  test('server must confirm all submitted report fields', () async {
    await http.runWithClient(() async {
      await expectLater(ApiService.instance.submitCheckIn(timeOfDay: 'Morning',
          report: {'overall_change': 'same', 'symptoms': ['dryness'], 'routine_status': 'followed'}),
          throwsA(isA<ApiException>()));
    }, () => MockClient((_) async => http.Response(jsonEncode(event('incomplete')), 201)));
  });

  testWidgets('structured form failure never opens completion screen', (tester) async {
    await http.runWithClient(() async {
      final state = DermaireState();
      await tester.pumpWidget(MaterialApp(home: CameraScreen(state: state)));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('same').last);
      await tester.pumpAndSettle();
      final pageScroll = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.text('Save check-in'), 300, scrollable: pageScroll);
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.textContaining('Could not confirm this check-in'), -150, scrollable: pageScroll);
      expect(find.textContaining('Could not confirm this check-in'), findsOneWidget);
      expect(find.text('Check-in complete'), findsNothing);
      await tester.scrollUntilVisible(find.text('Save check-in'), 150, scrollable: pageScroll);
      expect(find.text('Save check-in'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
    }, () => MockClient((request) async {
      expect(request.body, contains('overall_change'));
      expect(request.body, isNot(contains('hydration_score')));
      return http.Response('{"message":"Unavailable"}', 503);
    }));
  });
}
