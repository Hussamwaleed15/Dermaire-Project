import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dermaire_app/context_controller.dart';

class Repository implements ContextRepository {
  Map<String, dynamic>? stored;
  bool fail = false;
  bool fake = false;
  Completer<Map<String, dynamic>>? pending;
  Map<String, dynamic> value(String day) => {
    'date': day, 'source': 'user_reported', 'recorded': stored != null,
    'updated_at': stored == null ? null : '2026-10-01T12:00:00',
    'cycle_day': stored?['cycle_day'], 'unusual_conditions': stored?['unusual_conditions'],
  };
  @override
  Future<Map<String, dynamic>> read(String day) async {
    if (pending != null) return pending!.future;
    if (fail) throw Exception('offline');
    return value(day);
  }
  @override
  Future<Map<String, dynamic>> write(String day, bool? unusual, int? cycle) async {
    if (fail) throw Exception('offline');
    if (!fake) stored = {'cycle_day': cycle, 'unusual_conditions': unusual};
    return value(day);
  }
}
void main() {
  testWidgets('failed save preserves editor draft and never announces success', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = Repository();
    final state = DermaireState(contextRepository: repo);
    await tester.pumpWidget(MaterialApp(home: ContextScreen(state: state)));
    await tester.pumpAndSettle();
    expect(find.text('No context recorded for today'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '14');
    repo.fail = true;
    await tester.ensureVisible(find.text('Save context'));
    await tester.tap(find.text('Save context'));
    await tester.pumpAndSettle();
    expect(find.text('14'), findsOneWidget);
    expect(find.text('Context saved on server'), findsNothing);
    expect(find.text('Save unconfirmed. Your draft is still here. Refresh before retrying.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  test('HTTP failure is not an empty read or successful write', () async {
    SharedPreferences.setMockInitialValues({});
    await http.runWithClient(() async {
      final repository = RemoteContextRepository();
      expect(repository.read('2026-10-01'), throwsA(isA<ApiException>()));
      expect(repository.write('2026-10-01', true, 12), throwsA(isA<ApiException>()));
    }, () => MockClient((request) async => http.Response(jsonEncode({'message': 'unavailable'}), 503)));
  });
  test('server reads and writes survive controller restart; absent fields stay unknown', () async {
    final repo = Repository();
    final first = ContextController(repo);
    expect(await first.refresh(), true);
    expect(first.current!['cycle_day'], null);
    expect(await first.save(true, 14), true);
    final restarted = ContextController(repo);
    expect(restarted.current, null);
    expect(await restarted.refresh(), true);
    expect(restarted.current!['cycle_day'], 14);
    expect(await restarted.save(null, null), true);
    expect(restarted.current!['cycle_day'], null);
  });
  test('offline hides stale truth and never confirms a write', () async {
    final repo = Repository();
    final controller = ContextController(repo);
    await controller.save(false, 12);
    repo.fail = true;
    expect(await controller.refresh(), false);
    expect(controller.current, null);
    expect(await controller.save(true, 13), false);
    expect(repo.stored!['cycle_day'], 12);
    repo.fail = false;
    expect(await controller.refresh(), true);
    expect(controller.current!['cycle_day'], 12);
  });
  test('fake success and malformed confirmation rejected', () async {
    final repo = Repository()..fake = true;
    final controller = ContextController(repo);
    expect(await controller.save(true, 13), false);
    repo.fake = false;
    expect(await controller.save(true, 99), false);
    expect(controller.current, null);
  });
  test('account clear invalidates in-flight health data', () async {
    final repo = Repository()..pending = Completer<Map<String, dynamic>>();
    final controller = ContextController(repo);
    final response = controller.refresh();
    controller.clear();
    repo.pending!.complete(repo.value(controller.today));
    expect(await response, false);
    expect(controller.current, null);
  });
}
