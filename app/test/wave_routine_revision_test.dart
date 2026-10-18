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
import 'product_authority_test.dart' as p;
import 'routine_authority_test.dart' as f;

class Wire {
  Map<String, dynamic> row = {
    ...f.entry(),
    'revision': 7,
    'revision_protected': true,
  };
  int writes = 0, status = 200;
  bool timeout = false;
  String? expectedHeader = '"7"';
  Completer<http.Response>? pending;
  final sent = Completer<void>();
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/auth/login')) return p.auth();
    if (r.url.path.endsWith('/users/me')) {
      return http.Response(
        '{"id":"patient-1","role":"patient","safety_accepted":true}',
        200,
      );
    }
    if (r.method == 'PATCH') {
      writes++;
      expect(r.headers['If-Match'], expectedHeader);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      expect(body.keys, isNot(contains('revision')));
      expect(body.keys, isNot(contains('revision_protected')));
      if (!sent.isCompleted) sent.complete();
      if (pending != null) return pending!.future;
      if (timeout) throw TimeoutException('synthetic');
      if (status != 200) return http.Response('{}', status);
      row = {...row, ...body, 'revision': 12};
      return http.Response(jsonEncode(row), 200);
    }
    return http.Response(
      jsonEncode(
        r.url.path.endsWith('/entries')
            ? [row]
            : r.url.path.endsWith('/entries/entry')
            ? row
            : [],
      ),
      200,
    );
  }

  Future<void> run(Future<void> Function(RoutineController c) body) =>
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

Future<bool> write(
  RoutineController c,
  Map<String, dynamic> original, [
  Map<String, dynamic> payload = const {'instructions': 'Changed'},
]) => c.write(
  'entries/entry',
  payload,
  method: 'PATCH',
  expectedUpdatedAt: original['updated_at'] as String?,
  expectedRevision: original['revision'] as int?,
);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final invalid in [null, 0, -1, 2147483648, '7', 7.0]) {
    test(
      'routine rejects malformed revision $invalid (${invalid.runtimeType})',
      () {
        final row = Wire().row..['revision'] = invalid;
        expect(RoutineController.validRow(row, 'user_configured'), false);
      },
    );
  }
  for (final field in ['revision', 'revision_protected']) {
    test('routine rejects partial metadata missing $field', () {
      expect(
        RoutineController.validRow(
          Wire().row..remove(field),
          'user_configured',
        ),
        false,
      );
    });
  }
  for (final payload in [
    const {'instructions': 'Changed'},
    const {'active': false},
  ]) {
    test('protected edit/stop sends reviewed revision $payload', () async {
      final wire = Wire();
      await wire.run((c) async {
        final old = Map<String, dynamic>.of(c.entries!.single);
        expect(await write(c, old, payload), true);
        expect(c.entries!.single['revision'], 12);
        expect(wire.writes, 1);
      });
    });
  }
  test(
    'unprotected row does not opt in before linked experiment writer is upgraded',
    () async {
      final wire = Wire()..expectedHeader = null;
      wire.row['revision_protected'] = false;
      await wire.run((c) async {
        expect(await write(c, c.entries!.single), true);
      });
    },
  );
  test(
    'same-timestamp changed revision stops before dispatch and permits refresh',
    () async {
      final wire = Wire();
      await wire.run((c) async {
        final old = Map<String, dynamic>.of(c.entries!.single);
        wire.row = {...wire.row, 'revision': 8};
        expect(await write(c, old), false);
        expect(wire.writes, 0);
        expect(c.uncertain, isEmpty);
        expect(c.error, contains('reopen the editor'));
        await c.refresh();
        wire.expectedHeader = '"8"';
        expect(await write(c, c.entries!.single), true);
      });
    },
  );
  test(
    'missing original revision on versioned row never fetches a new write authority',
    () async {
      final wire = Wire();
      await wire.run((c) async {
        expect(
          await c.write(
            'entries/entry',
            {'active': false},
            method: 'PATCH',
            expectedUpdatedAt: c.entries!.single['updated_at'] as String,
          ),
          false,
        );
        expect(wire.writes, 0);
      });
    },
  );
  for (final status in [401, 403, 409, 412, 422, 428, 503]) {
    test('routine $status has no fake successful save', () async {
      final wire = Wire()..status = status;
      await wire.run((c) async {
        expect(await write(c, c.entries!.single), false);
        expect(wire.writes, 1);
        if (status == 401) {
          expect(c.entries, isNull);
        } else {
          expect(c.entries!.single['revision'], 7);
          expect(c.stale, true);
        }
        if ([409, 412, 422, 428].contains(status)) expect(c.uncertain, isEmpty);
        if (status == 503) expect(c.uncertain, contains('entries/entry'));
      });
    });
  }
  test(
    'timeout remains uncertain even after refresh and cannot double submit',
    () async {
      final wire = Wire()..timeout = true;
      await wire.run((c) async {
        expect(await write(c, c.entries!.single), false);
        await c.refresh();
        expect(await write(c, c.entries!.single), false);
        expect(wire.writes, 1);
      });
    },
  );
  test('late save cannot restore a logged-out routine', () async {
    final wire = Wire()..pending = Completer<http.Response>();
    await wire.run((c) async {
      final saving = write(c, c.entries!.single);
      await wire.sent.future;
      await ApiService.instance.init();
      wire.pending!.complete(
        http.Response(
          jsonEncode({...wire.row, 'instructions': 'Changed'}),
          200,
        ),
      );
      expect(await saving, false);
      expect(c.entries, isNull);
    });
  });
  for (final status in [200, 412]) {
    testWidgets(
      'actual routine editor sends reviewed revision and handles $status',
      (t) async {
        await t.binding.setSurfaceSize(const Size(800, 1400));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final wire = Wire()..status = status;
        await http.runWithClient(() async {
          await p.login();
          await t.pumpWidget(const MaterialApp(home: RoutineScreen()));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Edit'));
          await t.tap(find.text('Edit'));
          await t.pumpAndSettle();
          await t.enterText(
            find.widgetWithText(TextFormField, 'Your instructions / notes'),
            'Changed',
          );
          await t.tap(find.text('Save on server'));
          await t.pumpAndSettle();
          expect(wire.writes, 1);
          if (status == 200) {
            expect(find.text('Saved on server'), findsOneWidget);
          } else {
            expect(find.textContaining('reopen the editor'), findsWidgets);
          }
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(milliseconds: 400));
          await ApiService.instance.init();
        }, () => MockClient(wire.call));
      },
    );
  }
}
