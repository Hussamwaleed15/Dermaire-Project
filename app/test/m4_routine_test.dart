import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'routine_authority_test.dart' as r;
import 'product_authority_test.dart' as p;

class Wire {
  Map<String, dynamic> entry = r.entry();
  int writes = 0;
  bool failReadback = false, failPost = false;
  Completer<http.Response>? pending;
  Future<http.Response> call(http.Request request) async {
    expect(request.url.host, 'flutter-tests.invalid');
    final path = request.url.path;
    if (path.endsWith('/auth/login')) return p.auth();
    if (path.endsWith('/users/me')) {
      return http.Response(
        '{"id":"patient-1","role":"patient","safety_accepted":true}',
        200,
      );
    }
    if (request.method == 'POST' || request.method == 'PATCH') {
      writes++;
      if (failPost) throw TimeoutException('synthetic');
      entry = {...entry, ...jsonDecode(request.body) as Map<String, dynamic>};
      return http.Response(
        jsonEncode(entry),
        request.method == 'POST' ? 201 : 200,
      );
    }
    if (pending != null) return pending!.future;
    if (path.endsWith('/entries/entry')) {
      return http.Response(jsonEncode(entry), failReadback ? 503 : 200);
    }
    return http.Response(
      jsonEncode(path.endsWith('/entries') ? [entry] : []),
      200,
    );
  }

  Future<void> run(Future<void> Function(RoutineController) body) =>
      http.runWithClient(() async {
        await p.login();
        final c = RoutineController(RemoteRoutineRepository());
        await c.refresh();
        try {
          await body(c);
        } finally {
          c.dispose();
        }
      }, () => MockClient(call));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final field in [
    'schedule',
    'frequency',
    'active',
    'am_order',
    'pm_order',
    'source',
    'product_id',
    'created_at',
  ]) {
    test('routine fails closed for $field', () {
      final row = r.entry()..[field] = null;
      expect(RoutineController.validRow(row, 'user_configured'), false);
    });
  }
  for (final scenario in [
    'confirmed patch',
    'stale revision',
    'failed readback',
    'unknown POST',
    'logout',
    'duplicate submit',
  ]) {
    test('routine $scenario', () async {
      final wire = Wire();
      await wire.run((c) async {
        final stamp = c.entries!.single['updated_at'] as String;
        if (scenario == 'confirmed patch') {
          expect(
            await c.write(
              'entries/entry',
              {'instructions': 'changed'},
              method: 'PATCH',
              expectedUpdatedAt: stamp,
            ),
            true,
          );
          expect(c.entries!.single['instructions'], 'changed');
        }
        if (scenario == 'stale revision') {
          wire.entry['updated_at'] = '2026-10-03T10:00:00';
          expect(
            await c.write(
              'entries/entry',
              {'instructions': 'changed'},
              method: 'PATCH',
              expectedUpdatedAt: stamp,
            ),
            false,
          );
          expect(wire.writes, 0);
        }
        if (scenario == 'failed readback') {
          wire.failReadback = true;
          expect(await c.write('entries', {'schedule': 'AM'}), false);
          expect(c.entries!.single['id'], 'entry');
          expect(c.uncertain, contains('entries'));
        }
        if (scenario == 'unknown POST') {
          wire.failPost = true;
          expect(await c.write('entries', {'schedule': 'AM'}), false);
          await c.refresh();
          expect(await c.write('entries', {'schedule': 'AM'}), false);
          expect(wire.writes, 1);
        }
        if (scenario == 'logout') {
          wire.pending = Completer();
          final read = c.refresh();
          await Future<void>.delayed(Duration.zero);
          await ApiService.instance.init();
          wire.pending!.complete(http.Response(jsonEncode([wire.entry]), 200));
          await read;
          expect(c.entries, isNull);
        }
        if (scenario == 'duplicate submit') {
          wire.pending = Completer();
          final save = c.write('entries', {'schedule': 'AM'});
          await Future<void>.delayed(Duration.zero);
          expect(await c.write('entries', {'schedule': 'AM'}), false);
          wire.pending!.complete(http.Response(jsonEncode(wire.entry), 200));
          wire.pending = null;
          await save;
          expect(wire.writes, 1);
        }
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets('routine grouping and stopped history dark=$dark', (t) async {
      final repo = r.Repository()
        ..entries = [
          {...r.entry(), 'schedule': 'BOTH'},
          {
            ...r.entry(),
            'id': 'stopped',
            'active': false,
            'product_name': 'Previous',
          },
        ];
      await t.pumpWidget(
        MaterialApp(
          theme: dark ? ThemeData.dark() : ThemeData.light(),
          home: RoutineScreen(repository: repo),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Morning'), findsOneWidget);
      expect(
        find.textContaining('clinician-directed treatment'),
        findsOneWidget,
      );
      await t.scrollUntilVisible(find.text('Evening'), 150);
      expect(find.text('Evening'), findsOneWidget);
      expect(find.text('Inventory · BOTH · daily'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
