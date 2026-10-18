import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/experiments/experiment_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_experiment_revision_test.dart' as rev;
import 'm4_experiments_test.dart' as m;
import 'product_authority_test.dart' as p;

class ReceiptWire extends rev.Wire {
  String operation = 'activate', loss = 'after';
  bool lose = true;
  int submissions = 0, lookupStatus = 200;
  String? key, body, parentMatch, routineMatch;
  Map<String, dynamic>? original;
  Map<String, dynamic> Function(Map<String, dynamic>)? change;
  Completer<http.Response>? delayed;
  final lookupSent = Completer<void>();
  Map<String, dynamic> receipt() => {
    'schema_version': 1,
    'attempt_id': 'experiment-attempt',
    'owner_id': 'patient-1',
    'actor_id': 'patient-1',
    'domain': 'experiment',
    'operation': operation,
    'status': original == null ? 'unknown' : 'committed',
    'result': original,
    if (original != null) ...{
      'resource_id': 'experiment',
      'resource_revision': operation == 'create' ? 1 : 13,
      'recorded_at': '2026-10-18T01:00:00Z',
      'expires_at': '2026-11-17T01:00:00Z',
      'result_kind': operation == 'evaluate' ? 'evaluation' : 'experiment',
      'result_availability': 'retained',
      'snapshot_basis': 'original_committed_not_current',
    },
  };
  @override
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.contains('/operation-attempts/')) {
      expect(r.method, 'GET');
      expect(r.url.path.endsWith('/$key'), true);
      expect(
        r.url.queryParameters['resource_id'],
        operation == 'create' ? null : 'experiment',
      );
      if (!lookupSent.isCompleted) lookupSent.complete();
      if (delayed != null) return delayed!.future;
      final value = receipt();
      return http.Response(
        jsonEncode(change?.call(value) ?? value),
        lookupStatus,
      );
    }
    if (r.method == 'GET' || r.url.path.contains('/auth/')) {
      return super.call(r);
    }
    submissions++;
    if (key == null) {
      key = r.headers['Idempotency-Key'];
      body = r.body;
      parentMatch = r.headers['If-Match'];
      routineMatch = r.headers['Routine-If-Match'];
      expect(key, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
    } else {
      expect(r.headers['Idempotency-Key'], key);
      expect(r.body, body);
      expect(r.headers['If-Match'], parentMatch);
      expect(r.headers['Routine-If-Match'], routineMatch);
    }
    if (status != 200) return http.Response('{}', status);
    if (loss == 'before' && lose) throw TimeoutException('synthetic');
    http.Response result;
    if (original != null) {
      result = http.Response(
        jsonEncode(original),
        operation == 'create' || operation == 'evaluate' ? 201 : 200,
      );
    } else if (operation == 'create') {
      expect(parentMatch, isNull);
      writes++;
      row = {
        ...rev.experiment(),
        ...jsonDecode(r.body) as Map<String, dynamic>,
        'revision': 1,
      };
      result = http.Response(jsonEncode(row), 201);
    } else {
      if (operation == 'activate' &&
          routineMatch != '"${routine['revision']}"') {
        return http.Response('{}', 412);
      }
      result = await super.call(r);
    }
    original ??= jsonDecode(result.body) as Map<String, dynamic>;
    if (lose) throw TimeoutException('synthetic');
    return result;
  }

  Future<bool> submit(ExperimentController c) {
    if (operation == 'create') return c.write('', m.draft());
    final old = c.rows!.single;
    return c.write(
      operation == 'edit' || operation == 'cancel'
          ? 'experiment'
          : 'experiment/$operation',
      operation == 'edit'
          ? {
              'definition': {...m.draft(), 'goal': 'Original goal'},
              'notes': null,
            }
          : operation == 'finish'
          ? {'status': 'stopped'}
          : {},
      method: operation == 'edit'
          ? 'PATCH'
          : operation == 'cancel'
          ? 'DELETE'
          : 'POST',
      expected: Map.of(old),
      expectedRoutine: operation == 'activate' ? Map.of(routine) : null,
    );
  }

  @override
  Future<void> run(Future<void> Function(ExperimentController c) body) =>
      http.runWithClient(() async {
        await p.login();
        final c = ExperimentController(RemoteExperimentRepository());
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
  for (final operation in [
    'create',
    'edit',
    'activate',
    'finish',
    'cancel',
    'evaluate',
  ]) {
    for (final loss in ['before', 'after']) {
      test(
        'experiment $operation $loss loss preserves exact original operation',
        () async {
          final w = ReceiptWire()
            ..operation = operation
            ..loss = loss;
          if (['finish', 'evaluate'].contains(operation)) {
            w.row = rev.experiment('active');
          }
          await w.run((c) async {
            expect(await w.submit(c), false);
            expect(c.configurationPending, isNotNull);
            await c.refresh();
            expect(await w.submit(c), false);
            expect(w.submissions, 1);
            if (loss == 'before') {
              expect(await c.recoverConfiguration(), false);
              expect(c.configurationPending!.lookupStatus, 'unknown');
              w.lose = false;
            }
            expect(await c.recoverConfiguration(retryOriginal: true), true);
            expect(c.configurationPending, isNull);
            expect(c.uncertain, isEmpty);
            expect(w.submissions, loss == 'before' ? 2 : 1);
            expect(w.writes, 1);
            expect(c.rows!.single['revision'], operation == 'create' ? 1 : 13);
            if (operation == 'evaluate') {
              expect(c.rows!.single['result']['id'], 'evaluation');
            }
          });
        },
      );
    }
  }
  test(
    'lost activation and changed routine retry keeps old pair of headers and is rejected',
    () async {
      final w = ReceiptWire()..loss = 'before';
      await w.run((c) async {
        expect(await w.submit(c), false);
        w.routine = {...w.routine, 'revision': 8};
        w.lose = false;
        expect(await c.recoverConfiguration(retryOriginal: true), false);
        expect(c.configurationPending, isNotNull);
        expect(w.writes, 0);
        expect(w.submissions, 2);
        expect(w.parentMatch, '"5"');
        expect(w.routineMatch, '"7"');
      });
    },
  );
  test(
    'older activation result cannot overwrite a newer current stopped experiment',
    () async {
      final w = ReceiptWire();
      await w.run((c) async {
        expect(await w.submit(c), false);
        w.row = {...rev.experiment('stopped'), 'revision': 21};
        expect(await c.recoverConfiguration(), true);
        expect(c.rows!.single['revision'], 21);
        expect(c.rows!.single['status'], 'stopped');
        expect(w.submissions, 1);
      });
    },
  );
  for (final scenario in [
    'wrong owner',
    'wrong evaluation',
    'wrong original revision',
  ]) {
    test('reject $scenario original experiment receipt', () async {
      final w = ReceiptWire()
        ..operation = 'evaluate'
        ..row = rev.experiment('active')
        ..change = (v) {
          if (scenario == 'wrong owner') v['owner_id'] = 'other';
          if (scenario == 'wrong evaluation') {
            v['result'] = {
              ...v['result'] as Map<String, dynamic>,
              'experiment_id': 'other',
            };
          }
          if (scenario == 'wrong original revision') v['resource_revision'] = 5;
          return v;
        };
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(await c.recoverConfiguration(retryOriginal: true), false);
        expect(c.configurationPending, isNotNull);
        expect(w.submissions, 1);
      });
    });
  }
  for (final status in [401, 403, 404, 409, 410, 412, 422, 428, 503]) {
    test(
      'experiment attempt $status is not committed or safe to rekey',
      () async {
        final w = ReceiptWire()..lookupStatus = status;
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(await c.recoverConfiguration(retryOriginal: true), false);
          expect(w.submissions, 1);
          if (status == 401) {
            expect(c.rows, isNull);
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
      '$unavailable experiment receipt requires explicit review with no replay',
      () async {
        final w = ReceiptWire()
          ..change = (v) => {
            ...v,
            'status': unavailable == 'expired' ? 'expired' : 'committed',
            'result_availability': unavailable,
            'result': null,
          };
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(await c.recoverConfiguration(retryOriginal: true), false);
          expect(
            await c.recoverConfiguration(finishUnavailableReview: true),
            true,
          );
          expect(w.submissions, 1);
          expect(c.error, contains('No original request was repeated'));
        });
      },
    );
  }
  test(
    'late experiment receipt after logout cannot restore private result',
    () async {
      final w = ReceiptWire()..delayed = Completer<http.Response>();
      await w.run((c) async {
        expect(await w.submit(c), false);
        final recovery = c.recoverConfiguration();
        await w.lookupSent.future;
        await ApiService.instance.init();
        w.delayed!.complete(http.Response(jsonEncode(w.receipt()), 200));
        expect(await recovery, false);
        expect(c.rows, isNull);
        expect(c.configurationPending, isNull);
      });
    },
  );
  testWidgets(
    'real experiment view resolves original evaluation without another evaluation',
    (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final w = ReceiptWire()
        ..operation = 'evaluate'
        ..row = rev.experiment('active');
      await http.runWithClient(() async {
        await p.login();
        final c = ExperimentController(RemoteExperimentRepository());
        await c.refresh();
        expect(await w.submit(c), false);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExperimentsView(controller: c, autoLoad: false),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Check original experiment request'));
        await t.tap(find.text('Check original experiment request'));
        await t.pumpAndSettle();
        expect(c.configurationPending, isNull);
        expect(c.rows!.single['result']['id'], 'evaluation');
        expect(w.submissions, 1);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await ApiService.instance.init();
      }, () => MockClient(w.call));
    },
  );
  test(
    'definite experiment create422 permits a reviewed independent replacement',
    () async {
      final w = ReceiptWire()
        ..operation = 'create'
        ..lose = false
        ..status = 422;
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(c.configurationPending, isNull);
        expect(c.uncertain, isEmpty);
        final rejectedKey = w.key;
        await c.refresh();
        w.status = 200;
        w.key = null;
        expect(
          await c.write('', {...m.draft(), 'goal': 'Reviewed replacement'}),
          true,
        );
        expect(w.key, isNot(rejectedKey));
        expect(w.submissions, 2);
      });
    },
  );
}
