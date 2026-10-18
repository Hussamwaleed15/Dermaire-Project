import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/consent/evaluation_withdrawal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_plan_withdrawal_test.dart' as f;
import 'product_authority_test.dart' as auth;

class Wire extends f.Wire {
  Wire() {
    plan['kind'] = 'comparison';
    plan['state'] = 'captured';
  }
  int deletes = 0, status = 200, deleteFailure = 200;
  String loss = 'none';
  Completer<http.Response>? lateJob;
  final jobRequested = Completer<void>();
  Map<String, dynamic> job = {
    'schema_version': 'comparison-job-1',
    'id': 'job-1',
    'input': {'plan_id': 'plan-1'},
    'plan_revision': 1,
    'state': 'queued',
    'clinical_clearance': false,
    'medical_resources_modified': false,
    'inference': {'private': 'must never cross metadata boundary'},
  };
  @override
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/evaluation')) {
      if (r.method == 'GET' && lateJob != null) {
        if (!jobRequested.isCompleted) jobRequested.complete();
        return lateJob!.future;
      }
      if (status != 200) return http.Response('{}', status);
      if (r.method == 'DELETE') {
        deletes++;
        if (deleteFailure != 200) return http.Response('{}', deleteFailure);
        expect(r.headers['Idempotency-Key'], isNull);
        expect(r.body, isEmpty);
        expect(r.url.queryParameters['expected_revision'], '1');
        if (loss == 'before') throw TimeoutException('synthetic');
        if (job['state'] != 'cancelled') {
          if (plan['revision'] != 1) return http.Response('{}', 409);
          plan['revision'] = 2;
          job = {...job, 'state': 'cancelled', 'plan_revision': 2};
        }
        if (loss == 'after') throw TimeoutException('synthetic');
      }
      return http.Response(jsonEncode(job), 200);
    }
    return super.call(r);
  }

  Future<void> runJob(
    Future<void> Function(EvaluationWithdrawalController) c,
  ) => http.runWithClient(() async {
    await auth.login();
    final controller = EvaluationWithdrawalController('plan-1');
    try {
      await controller.refresh();
      await c(controller);
    } finally {
      controller.dispose();
    }
  }, () => MockClient(call));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final loss in ['none', 'before', 'after']) {
    test(
      'evaluation cancellation$loss remains separate from parent and uses no invented receipt',
      () async {
        final w = Wire()..loss = loss;
        await w.runJob((c) async {
          expect(c.job!.containsKey('inference'), false);
          await c.cancel();
          expect(w.deletes, 0);
          c.approve(true);
          await c.cancel();
          await c.cancel();
          expect(w.deletes, 1);
          if (loss != 'none') {
            expect(c.pending, isNotNull);
            await c.reconcile();
            if (loss == 'before') {
              expect(c.pending, isNotNull);
              w.loss = 'none';
              await c.reconcile(retryOriginal: true);
              expect(w.deletes, 2);
            }
          }
          expect(c.pending, isNull);
          expect(c.job!['state'], 'cancelled');
          expect(c.plan!['state'], 'captured');
          expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
        });
      },
    );
  }
  test(
    'new current evaluation cannot be cancelled by original retry',
    () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.job = {
          ...w.job,
          'id': 'job-2',
          'state': 'queued',
          'plan_revision': 3,
        };
        w.plan['revision'] = 3;
        await c.reconcile(retryOriginal: true);
        expect(c.pending, isNotNull);
        expect(w.deletes, 1);
        expect(w.job['state'], 'queued');
      });
    },
  );
  test('original plan CAS change cannot be silently rebased', () async {
    final w = Wire();
    await w.runJob((c) async {
      w.plan['revision'] = 2;
      c.approve(true);
      await c.cancel();
      expect(w.deletes, 0);
      expect(c.pending, isNull);
      expect(c.error, isNotNull);
    });
  });
  test(
    'completed human review withdrawal does not claim parent cancellation or erase clinical history',
    () async {
      final w = Wire()..job['state'] = 'reviewed';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        expect(c.job!['state'], 'cancelled');
        expect(c.plan!['state'], 'captured');
        expect(
          c.outcome,
          contains('No plan cancellation or clinical conclusion'),
        );
      });
    },
  );
  for (final code in [401, 403, 404, 409, 410, 422, 503]) {
    test(
      'evaluation lookup$code keeps uncertainty and suppresses replacement',
      () async {
        final w = Wire()..loss = 'after';
        await w.runJob((c) async {
          c.approve(true);
          await c.cancel();
          w.status = code;
          await c.reconcile(retryOriginal: true);
          expect(w.deletes, 1);
          expect(c.outcome, isNull);
          expect(c.pending == null, code == 401);
        });
      },
    );
  }
  for (final field in ['plan_id', 'grant', 'job']) {
    test('evaluation original $field mismatch remains locked', () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        if (field == 'plan_id') w.job['input'] = {'plan_id': 'foreign'};
        if (field == 'grant') w.plan['access_id'] = 'replacement';
        if (field == 'job') w.job['id'] = 'other-job';
        await c.reconcile(retryOriginal: true);
        expect(c.pending, isNotNull);
        expect(w.deletes, 1);
      });
    });
  }

  for (final event in ['hide', 'logout', 'switch']) {
    test(
      'late evaluation metadata after $event cannot restore scope',
      () async {
        final w = Wire()..loss = 'after';
        await w.runJob((c) async {
          c.approve(true);
          await c.cancel();
          w.lateJob = Completer<http.Response>();
          final read = c.reconcile();
          await w.jobRequested.future;
          if (event == 'hide') {
            c.hide();
          } else {
            await ApiService.instance.init();
          }
          if (event == 'switch') {
            w.owner = 'patient-2';
            await auth.login();
          }
          w.lateJob!.complete(http.Response(jsonEncode(w.job), 200));
          await read;
          expect(c.plan, isNull);
          expect(c.job, isNull);
          expect(c.outcome, isNull);
          expect(w.deletes, 1);
        });
      },
    );
  }

  test(
    'first definite DELETE conflict releases only for new explicit review',
    () async {
      final w = Wire()..deleteFailure = 409;
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        expect(c.pending, isNull);
        expect(c.plan, isNull);
        expect(w.deletes, 1);
        await c.refresh();
        expect(c.confirmed, false);
        expect(w.deletes, 1);
      });
    },
  );
  testWidgets(
    'real evaluation screen confirms separately without private images',
    (t) async {
      final w = Wire();
      await http.runWithClient(() async {
        await auth.login();
        await t.pumpWidget(
          const MaterialApp(home: EvaluationWithdrawalScreen(id: 'plan-1')),
        );
        await t.pumpAndSettle();
        expect(find.byType(Image), findsNothing);
        expect(find.textContaining('must never'), findsNothing);
        await t.ensureVisible(find.byType(Checkbox));
        await t.pumpAndSettle();
        await t.tap(find.byType(Checkbox));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Cancel evaluation job'));
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel evaluation job'));
        await t.pumpAndSettle();
        expect(w.deletes, 1);
        expect(w.plan['state'], 'captured');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      }, () => MockClient(w.call));
    },
  );
}
