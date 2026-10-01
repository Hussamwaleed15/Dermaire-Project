import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/baseline/baseline_controller.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> snapshot(int days) => {
  'completed_days': days, 'required_days': 5,
  'status': days == 5 ? 'ready' : 'collecting',
  'today_checked_in': days > 0,
  'metrics': days == 5 ? {
    for (final name in ['hydration', 'redness', 'texture'])
      name: {'mean': 50, 'standard_deviation': 1},
  } : <String, dynamic>{},
};

class FakeBaseline implements BaselineRepository {
  Map<String, dynamic> data = snapshot(0);
  bool fail = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> read() async {
    if (fail) throw ApiException('Offline');
    return pending?.future ?? data;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('only server refresh advances baseline; restart re-reads it', () async {
    final repo = FakeBaseline();
    final controller = BaselineController(repo);
    expect(controller.completedDays, isNull);
    await controller.refresh();
    expect(controller.completedDays, 0);
    repo.data = snapshot(3);
    expect(controller.completedDays, 0);
    await controller.refresh();
    expect(controller.completedDays, 3);
    final restart = BaselineController(repo);
    expect(restart.completedDays, isNull);
    await restart.refresh();
    expect(restart.completedDays, 3);
    repo.data = snapshot(0);
    await controller.refresh();
    expect(controller.completedDays, 0);
    expect(controller.todayCheckedIn, false);
    controller.dispose();
    restart.dispose();
  });

  test('failed or pending refresh never promotes stale snapshot', () async {
    final repo = FakeBaseline()..data = snapshot(5);
    final controller = BaselineController(repo);
    await controller.refresh();
    expect(controller.ready, true);
    repo.fail = true;
    expect(await controller.refresh(), false);
    expect(controller.completedDays, isNull);
    expect(controller.metrics, isEmpty);
    expect(controller.ready, false);
    expect(controller.error, isNotNull);
    repo.fail = false;
    repo.pending = Completer();
    final refresh = controller.refresh();
    expect(controller.available, false);
    controller.clear();
    repo.pending!.complete(snapshot(5));
    expect(await refresh, false);
    expect(controller.completedDays, isNull);
    controller.dispose();
  });

  test('malformed ready response is never a success', () async {
    final repo = FakeBaseline()..data = {...snapshot(5), 'metrics': {}};
    final controller = BaselineController(repo);
    expect(await controller.refresh(), false);
    expect(controller.ready, false);
    controller.dispose();
  });

  test('state refresh never counts local completion or journal entries', () async {
    final repo = FakeBaseline()..data = snapshot(2);
    final state = DermaireState(baselineRepository: repo);
    await state.markTodayCheckedIn();
    expect(state.baselineCheckIns, 2);
    state.addJournalEntry();
    await state.markTodayCheckedIn();
    expect(state.baselineCheckIns, 2);
    repo.fail = true;
    await state.markTodayCheckedIn();
    expect(state.baselineCheckIns, isNull);
    state.clearAccountData();
    expect(state.baselineCheckIns, isNull);
    state.dispose();
  });

  test('HTTP failures throw and photo writes send no hardcoded scores', () async {
    var fail = false;
    await http.runWithClient(() async {
      await ApiService.instance.login(email: 'test@example.com', password: 'test');
      final repo = RemoteBaselineRepository();
      expect((await repo.read())['completed_days'], 0);
      fail = true;
      expect(repo.read(), throwsA(isA<ApiException>()));
      expect(ApiService.instance.submitCheckIn(timeOfDay: 'Morning',
          photoBytes: [1, 2], photoFilename: 'skin.jpg'), throwsA(isA<ApiException>()));
      await ApiService.instance.logout();
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return http.Response(jsonEncode({'access_token': 'baseline-test',
          'expires_in': 3600, 'user_id': 'patient', 'role': 'patient'}), 200);
      }
      if (request.url.path.endsWith('/checkins')) {
        expect(request.body, isNot(contains('hydration_score')));
        expect(request.body, isNot(contains('texture_score')));
        expect(request.body, isNot(contains('redness_score')));
        return http.Response('{"message":"Measurement unavailable"}', 503);
      }
      return http.Response(jsonEncode(fail ? {'message': 'Unavailable'} : snapshot(0)), fail ? 503 : 200);
    }));
  });

  test('malformed HTTP write confirmation cannot complete a check-in', () async {
    await http.runWithClient(() async {
      expect(ApiService.instance.submitCheckIn(timeOfDay: 'Morning',
          hydration: 80, texture: 60, redness: 20), throwsA(isA<ApiException>()));
    }, () => MockClient((_) async => http.Response('{}', 201)));
  });

  testWidgets('stale baseline screen shows unknown and lets user retry', (tester) async {
    final repo = FakeBaseline()..data = snapshot(3);
    final state = DermaireState(baselineRepository: repo);
    await state.baseline.refresh();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnimatedBuilder(
      animation: state, builder: (_, _) => ExperimentTab(state: state),
    ))));
    expect(find.text('3 of 5 days'), findsOneWidget);
    repo.fail = true;
    await tester.tap(find.text('Refresh baseline'));
    await tester.pump();
    expect(find.text('Unknown of 5 days'), findsOneWidget);
    expect(find.text('3 of 5 days'), findsNothing);
    expect(find.textContaining('Baseline unavailable'), findsOneWidget);
    repo.fail = false;
    repo.data = snapshot(4);
    await tester.tap(find.text('Refresh baseline'));
    await tester.pump();
    expect(find.text('4 of 5 days'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
