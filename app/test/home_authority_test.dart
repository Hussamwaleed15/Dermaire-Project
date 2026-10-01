import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dermaire_app/home_controller.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/app_shell.dart';

Map<String, dynamic> snapshot() => {
  'as_of': DateTime.now().toUtc().toIso8601String(),
  'date': DateTime.now().toUtc().toIso8601String().split('T').first,
  'today_checked_in': true,
  'experiment': {'id': 'server-exp', 'status': 'paused', 'current_day': 4,
    'target_days': 14, 'primary_concern': 'redness', 'product_name': 'Server product',
    'redness_delta_percent': -50, 'texture_delta_percent': 25, 'hydration_delta_percent': null},
  'journal': [{'id': 'server-checkin', 'created_at': '2026-01-01T12:00:00',
    'time_of_day': 'Evening', 'measurement_source': 'manual',
    'hydration_score': 80, 'texture_score': 75, 'redness_score': 10}],
};

class Repository implements HomeRepository {
  Map<String, dynamic> data = snapshot();
  bool fail = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> read() async {
    if (pending != null) return pending!.future;
    if (fail) throw Exception('offline');
    return data;
  }
}

void main() {
  test('refresh, restart, failures and empty state follow server only', () async {
    final repo = Repository();
    final home = HomeController(repo);
    expect(await home.refresh(), true);
    expect(home.current!['experiment']['current_day'], 4);
    home.current!['experiment']['current_day'] = 99;
    expect(home.current!['experiment']['current_day'], 4);
    repo.pending = Completer();
    final refresh = home.refresh();
    expect(home.current, isNull);
    repo.pending!.completeError(Exception('offline'));
    expect(await refresh, false);
    expect(home.current, isNull);
    repo.pending = null;
    repo.data = {...snapshot(), 'experiment': null, 'journal': [], 'today_checked_in': false};
    expect(await home.refresh(), true);
    expect(home.current!['experiment'], isNull);
    home.dispose();
    final restarted = HomeController(repo);
    expect(restarted.current, isNull);
    expect(await restarted.refresh(), true);
    expect(restarted.current!['journal'], isEmpty);
    restarted.dispose();
  });

  test('malformed or stale data never confirms Home', () async {
    final repo = Repository();
    final home = HomeController(repo);
    for (final bad in [
      {...snapshot(), 'experiment': {'id': 'fake'}},
      {...snapshot(), 'journal': [{'id': 'seed'}]},
      {...snapshot(), 'date': '2000-01-01'},
      {...snapshot(), 'today_checked_in': null},
      {...snapshot(), 'experiment': {...snapshot()['experiment'], 'texture_delta_percent': double.nan}},
    ]) {
      repo.data = bad;
      expect(await home.refresh(), false);
      expect(home.current, isNull);
    }
    home.dispose();
  });

  test('logout and newer refresh invalidate in-flight responses', () async {
    final repo = Repository()..pending = Completer();
    final state = DermaireState(homeRepository: repo);
    final old = state.home.refresh();
    state.clearAccountData();
    repo.pending!.complete(snapshot());
    expect(await old, false);
    expect(state.home.current, isNull);
    final pending = Completer<Map<String, dynamic>>();
    repo.pending = pending;
    final older = state.home.refresh();
    repo.pending = null;
    repo.data = {...snapshot(), 'experiment': null};
    expect(await state.home.refresh(), true);
    pending.complete(snapshot());
    expect(await older, false);
    expect(state.home.current!['experiment'], isNull);
    state.dispose();
  });

  test('HTTP server failures throw instead of returning empty success', () async {
    var status = 200;
    await http.runWithClient(() async {
      final repo = RemoteHomeRepository();
      expect((await repo.read())['today_checked_in'], true);
      for (final code in [401, 403, 500, 503]) {
        status = code;
        await expectLater(repo.read(), throwsException);
      }
    }, () => MockClient((request) async {
      expect(request.url.path, '/api/v1/home');
      return http.Response(jsonEncode(snapshot()), status);
    }));
  });

  testWidgets('Home displays server facts and removes stale facts on failure', (tester) async {
    final repo = Repository();
    final state = DermaireState(homeRepository: repo);
    state.experimentDay = 99;
    state.journal.add(const JournalEntry('Today', 'Morning', 'Fake private values'));
    await state.home.refresh();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnimatedBuilder(
      animation: state, builder: (_, _) => HomeTab(state: state)))));
    expect(find.text('Day 4 of 14'), findsOneWidget);
    expect(find.text('Testing: Server product · redness'), findsOneWidget);
    expect(find.text('-50.0%'), findsOneWidget);
    expect(find.text('Completed'), findsOneWidget);
    expect(find.textContaining('Fake private'), findsNothing);
    repo.fail = true;
    await tester.tap(find.text('Refresh Home'));
    await tester.pumpAndSettle();
    expect(find.text('Day 4 of 14'), findsNothing);
    expect(find.text('-50.0%'), findsNothing);
    expect(find.text('Completed'), findsNothing);
    expect(find.text('Progress unconfirmed'), findsOneWidget);
    expect(find.textContaining('Home unavailable'), findsOneWidget);
    repo.fail = false;
    repo.data = {...snapshot(), 'experiment': null, 'journal': [], 'today_checked_in': false};
    await state.home.refresh();
    await tester.pump();
    expect(find.text('No current experiment'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No confirmed journal entries'), 200);
    expect(find.text('No confirmed journal entries'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
