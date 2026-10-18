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
import 'routine_authority_test.dart' as f;
import 'product_authority_test.dart' as p;

Map<String, dynamic> row([int revision = 7]) => {
  ...f.entry(),
  'revision': revision,
  'revision_protected': true,
};

class RoutineWire {
  Map<String, dynamic>? current = row(), original;
  String operation = 'edit', loss = 'after';
  String? key, originalBody, match;
  bool lose = true;
  int writes = 0, lookupStatus = 200;
  Map<String, dynamic> Function(Map<String, dynamic>)? change;
  Completer<http.Response>? delayed;
  final lookupSent = Completer<void>();
  Map<String, dynamic> receipt() => {
    'schema_version': 1,
    'attempt_id': 'original-config-attempt',
    'owner_id': 'patient-1',
    'actor_id': 'patient-1',
    'domain': 'routine',
    'operation': operation == 'create' ? 'create' : 'update',
    'status': original == null ? 'unknown' : 'committed',
    'result': original,
    if (original != null) ...{
      'resource_id': 'entry',
      'resource_revision': original!['revision'],
      'result_kind': 'routine',
      'result_availability': 'retained',
      'snapshot_basis': 'original_committed_not_current',
      'recorded_at': '2026-10-18T01:00:00Z',
      'expires_at': '2026-11-17T01:00:00Z',
    },
  };
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/auth/login')) return p.auth();
    if (r.url.path.endsWith('/users/me')) {
      return http.Response(
        '{"id":"patient-1","role":"patient","safety_accepted":true}',
        200,
      );
    }
    if (r.url.path.contains('/configuration-attempts/')) {
      expect(r.method, 'GET');
      expect(r.url.path.endsWith('/$key'), true);
      expect(
        r.url.queryParameters['resource_id'],
        operation == 'create' ? null : 'entry',
      );
      if (!lookupSent.isCompleted) lookupSent.complete();
      if (delayed != null) return delayed!.future;
      final value = receipt();
      return http.Response(
        jsonEncode(change?.call(value) ?? value),
        lookupStatus,
      );
    }
    if (r.method != 'GET') {
      writes++;
      expect(
        r.headers['Idempotency-Key'],
        matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')),
      );
      if (key == null) {
        key = r.headers['Idempotency-Key'];
        originalBody = r.body;
        match = r.headers['If-Match'];
      } else {
        expect(r.headers['Idempotency-Key'], key);
        expect(r.body, originalBody);
        expect(r.headers['If-Match'], match);
      }
      expect(match, operation == 'create' ? null : '"7"');
      if (loss == 'before' && lose) throw TimeoutException('synthetic');
      if (original == null) {
        original = {
          ...row(operation == 'create' ? 1 : 9),
          ...jsonDecode(r.body) as Map<String, dynamic>,
        };
        current = Map.of(original!);
      }
      if (lose) throw TimeoutException('synthetic');
      return http.Response(
        jsonEncode(original),
        operation == 'create' ? 201 : 200,
      );
    }
    if (r.url.path.endsWith('/entries/entry')) {
      return http.Response(
        jsonEncode(current ?? {}),
        current == null ? 404 : 200,
      );
    }
    return http.Response(
      jsonEncode(
        r.url.path.endsWith('/entries') && current != null ? [current] : [],
      ),
      200,
    );
  }

  Future<bool> submit(RoutineController c) {
    if (operation == 'create') {
      return c.write('entries', {
        'product_id': 'product',
        'schedule': 'AM',
        'frequency': 'daily',
        'start_date': '2026-10-18',
        'instructions': 'Original instruction',
        'am_order': 0,
        'pm_order': 0,
      });
    }
    final old = c.entries!.single;
    return c.write(
      'entries/entry',
      operation == 'stop'
          ? {'active': false}
          : {'instructions': 'Original instruction'},
      method: 'PATCH',
      expectedUpdatedAt: old['updated_at'] as String,
      expectedRevision: old['revision'] as int,
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final operation in ['create', 'edit', 'stop']) {
    for (final loss in ['before', 'after']) {
      test(
        'routine $operation $loss response loss preserves original identity',
        () async {
          final w = RoutineWire()
            ..operation = operation
            ..loss = loss;
          if (operation == 'create') w.current = null;
          await w.run((c) async {
            expect(await w.submit(c), false);
            expect(c.configurationPending, isNotNull);
            await c.refresh();
            expect(await w.submit(c), false);
            expect(w.writes, 1);
            if (loss == 'before') {
              expect(await c.recoverConfiguration(), false);
              expect(c.configurationPending!.lookupStatus, 'unknown');
              expect(
                await c.recoverConfiguration(finishUnavailableReview: true),
                false,
              );
              w.lose = false;
            }
            expect(await c.recoverConfiguration(retryOriginal: true), true);
            expect(c.configurationPending, isNull);
            expect(c.uncertain, isEmpty);
            expect(
              c.entries!.single['revision'],
              operation == 'create' ? 1 : 9,
            );
            expect(w.writes, loss == 'before' ? 2 : 1);
          });
        },
      );
    }
  }
  test(
    'original configuration receipt does not roll back newer current configuration',
    () async {
      final w = RoutineWire();
      await w.run((c) async {
        expect(await w.submit(c), false);
        w.current = {...row(17), 'instructions': 'Newer configuration'};
        expect(await c.recoverConfiguration(), true);
        expect(c.entries!.single['revision'], 17);
        expect(c.entries!.single['instructions'], 'Newer configuration');
        expect(w.writes, 1);
      });
    },
  );
  for (final scenario in [
    'owner',
    'domain',
    'operation',
    'resource',
    'revision',
    'kind',
    'snapshot',
    'original',
    'unknown result',
  ]) {
    test(
      'invalid configuration receipt $scenario never resolves request',
      () async {
        final w = RoutineWire()
          ..change = (v) {
            if (scenario == 'owner') v['actor_id'] = 'other';
            if (scenario == 'domain') v['domain'] = 'experiment';
            if (scenario == 'operation') v['operation'] = 'stop';
            if (scenario == 'resource') v['resource_id'] = 'other';
            if (scenario == 'revision') v['resource_revision'] = 7;
            if (scenario == 'kind') v['result_kind'] = 'evaluation';
            if (scenario == 'snapshot') v['snapshot_basis'] = 'current';
            if (scenario == 'original') {
              v['result'] = {...row(9), 'source': 'fabricated'};
            }
            if (scenario == 'unknown result') v['status'] = 'unknown';
            return v;
          };
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(await c.recoverConfiguration(retryOriginal: true), false);
          expect(c.configurationPending, isNotNull);
          expect(w.writes, 1);
        });
      },
    );
  }
  for (final status in [401, 403, 404, 409, 410, 412, 422, 428, 503]) {
    test(
      'configuration lookup $status does not replay or replace key',
      () async {
        final w = RoutineWire()..lookupStatus = status;
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(await c.recoverConfiguration(retryOriginal: true), false);
          expect(w.writes, 1);
          if (status == 401) {
            expect(c.entries, isNull);
            expect(c.configurationPending, isNull);
          } else {
            expect(c.configurationPending, isNotNull);
          }
        });
      },
    );
  }
  for (final unavailable in ['expired', 'erased']) {
    test(
      '$unavailable original configuration requires explicit current-record review',
      () async {
        final w = RoutineWire()
          ..change = (v) => {
            ...v,
            'status': unavailable == 'expired' ? 'expired' : 'committed',
            'result_availability': unavailable,
            'result': null,
          };
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(await c.recoverConfiguration(retryOriginal: true), false);
          expect(c.configurationPending, isNotNull);
          expect(w.writes, 1);
          expect(
            await c.recoverConfiguration(finishUnavailableReview: true),
            true,
          );
          expect(c.configurationPending, isNull);
          expect(w.writes, 1);
          expect(c.error, contains('No original request was repeated'));
        });
      },
    );
  }
  test(
    'late configuration receipt after session change cannot restore routine',
    () async {
      final w = RoutineWire()..delayed = Completer<http.Response>();
      await w.run((c) async {
        expect(await w.submit(c), false);
        final recovery = c.recoverConfiguration();
        await w.lookupSent.future;
        await ApiService.instance.init();
        w.delayed!.complete(http.Response(jsonEncode(w.receipt()), 200));
        expect(await recovery, false);
        expect(c.entries, isNull);
        expect(c.configurationPending, isNull);
      });
    },
  );
  testWidgets('real routine screen reconciles original stopped step', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final w = RoutineWire()..operation = 'stop';
    await http.runWithClient(() async {
      await p.login();
      final c = RoutineController(RemoteRoutineRepository());
      await c.refresh();
      expect(await w.submit(c), false);
      c.dispose();
      await t.pumpWidget(const MaterialApp(home: RoutineScreen()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Check original routine request'));
      await t.tap(find.text('Check original routine request'));
      await t.pumpAndSettle();
      expect(find.text('Retry original routine request'), findsNothing);
      expect(
        find.textContaining('Original routine request confirmed'),
        findsOneWidget,
      );
      expect(w.writes, 1);
      await t.pumpWidget(const SizedBox());
      await ApiService.instance.init();
    }, () => MockClient(w.call));
  });
}
