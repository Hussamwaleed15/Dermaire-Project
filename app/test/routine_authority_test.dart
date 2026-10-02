import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> entry() => {
  'id': 'entry',
  'product_id': 'product',
  'product_name': 'Inventory',
  'schedule': 'AM',
  'frequency': 'daily',
  'start_date': '2026-10-02',
  'end_date': null,
  'active': true,
  'instructions': 'User note',
  'am_order': 0,
  'pm_order': 0,
  'source': 'user_configured',
  'created_at': '2026-10-02T10:00:00',
  'updated_at': '2026-10-02T10:00:00',
};

class Repository implements RoutineRepository {
  List<Map<String, dynamic>> entries = [];
  List<Map<String, dynamic>> history = [];
  bool fail = false;
  bool fake = false;
  Completer<List<Map<String, dynamic>>>? pending;
  Completer<Map<String, dynamic>>? pendingWrite;
  @override
  Future<List<Map<String, dynamic>>> read(String resource) async {
    if (pending != null) return pending!.future;
    if (fail) throw Exception('offline');
    return resource == 'entries' ? entries : history;
  }

  @override
  Future<Map<String, dynamic>> write(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    if (pendingWrite != null) return pendingWrite!.future;
    if (fail) throw Exception('offline');
    if (fake) return {'success': true};
    final confirmed = {...entry(), ...payload};
    entries = [confirmed];
    return confirmed;
  }
}

void main() {
  testWidgets('loading empty success and failure use remote state', (
    tester,
  ) async {
    final repository = Repository()..pending = Completer();
    await tester.pumpWidget(
      MaterialApp(home: RoutineScreen(repository: repository)),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    repository.pending!.complete([]);
    repository.pending = null;
    await tester.pumpAndSettle();
    expect(find.text('No routine configured'), findsOneWidget);
    expect(find.text('No adherence reported'), findsOneWidget);
    repository.entries = [entry()];
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(find.text('Inventory · AM · daily'), findsOneWidget);
    repository.fail = true;
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();
    expect(
      find.text('Routine unavailable. Refresh to try again.'),
      findsOneWidget,
    );
    expect(find.text('Inventory · AM · daily'), findsNothing);
  });
  testWidgets('stop waits for confirmation and never reports fake success', (
    tester,
  ) async {
    final repository = Repository()
      ..entries = [entry()]
      ..pendingWrite = Completer();
    await tester.pumpWidget(
      MaterialApp(home: RoutineScreen(repository: repository)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pump();
    expect(find.text('Saved on server'), findsNothing);
    repository.pendingWrite!.complete({
      ...entry(),
      'active': false,
      'end_date': '2026-10-02',
    });
    repository.entries = [
      {...entry(), 'active': false},
    ];
    repository.pendingWrite = null;
    await tester.pumpAndSettle();
    expect(find.text('Saved on server'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final bad = Repository()
      ..entries = [entry()]
      ..fake = true;
    await tester.pumpWidget(MaterialApp(home: RoutineScreen(repository: bad)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(find.text('Saved on server'), findsNothing);
    expect(
      find.text('Save unconfirmed. Refresh before retrying.'),
      findsOneWidget,
    );
  });
  test(
    'writes require matching server fields, history survives refresh',
    () async {
      final repository = Repository();
      final controller = RoutineController(repository);
      expect(
        await controller.write('entries', {
          'product_id': 'product',
          'product_name': 'Inventory',
          'schedule': 'AM',
          'frequency': 'daily',
          'start_date': '2026-10-02',
        }),
        true,
      );
      final restarted = RoutineController(repository);
      await restarted.refresh();
      expect(restarted.entries!.single['id'], 'entry');
      repository.fake = true;
      expect(
        await controller.write('entries/entry', {
          'active': false,
        }, method: 'PATCH'),
        false,
      );
      expect(repository.entries.single['active'], true);
      repository.fail = true;
      await restarted.refresh();
      expect(restarted.entries, null);
      expect(await controller.write('entries', {'schedule': 'PM'}), false);
      controller.dispose();
      restarted.dispose();
    },
  );
  test('clear rejects in-flight reads and writes across accounts', () async {
    final repository = Repository()..pending = Completer();
    final controller = RoutineController(repository);
    final read = controller.refresh();
    controller.clear();
    repository.pending!.complete([entry()]);
    await read;
    expect(controller.entries, null);
    repository.pending = null;
    repository.pendingWrite = Completer();
    final write = controller.write('entries', {'schedule': 'AM'});
    controller.clear();
    repository.pendingWrite!.complete(entry());
    expect(await write, false);
    expect(controller.entries, null);
    controller.dispose();
  });
  test('HTTP failures and malformed confirmations are not success', () async {
    await http.runWithClient(() async {
      final repository = RemoteRoutineRepository();
      expect(repository.read('entries'), throwsA(isA<ApiException>()));
      expect(
        repository.write('entries', {'schedule': 'AM'}),
        throwsA(isA<ApiException>()),
      );
    }, () => MockClient((_) async => http.Response('{}', 503)));
    await http.runWithClient(
      () async {
        final controller = RoutineController(RemoteRoutineRepository());
        expect(await controller.write('entries', {'schedule': 'AM'}), false);
        expect(controller.entries, null);
        controller.dispose();
      },
      () => MockClient(
        (_) async => http.Response(jsonEncode({'success': true}), 201),
      ),
    );
  });
  test('malformed reads do not become canonical routine state', () async {
    final repository = Repository()
      ..entries = [
        {
          'id': 'entry',
          'source': 'user_configured',
          'created_at': '2026-10-02',
        },
      ];
    final controller = RoutineController(repository);
    await controller.refresh();
    expect(controller.entries, null);
    expect(controller.error, isNotNull);
    controller.dispose();
  });
  test('account clear during post-write refresh suppresses success', () async {
    final repository = Repository()..pendingWrite = Completer();
    final controller = RoutineController(repository);
    final write = controller.write('entries', {'schedule': 'AM'});
    repository.pending = Completer();
    repository.pendingWrite!.complete(entry());
    await Future<void>.delayed(Duration.zero);
    controller.clear();
    repository.pending!.complete([entry()]);
    expect(await write, false);
    expect(controller.entries, null);
    controller.dispose();
  });
}
