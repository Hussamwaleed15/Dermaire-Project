import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/consent/plan_withdrawal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_plans_test.dart' as f;
import 'product_authority_test.dart' as auth;

class Wire extends f.PlanWire {
  int lookupFailure = 200;
  final seen = Completer<void>();
  Completer<http.Response>? held;
  @override
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/users/me')) {
      return http.Response(
        jsonEncode({"id": owner, "role": "patient", "safety_accepted": false}),
        200,
      );
    }
    if (r.url.path.contains('/attempts/')) {
      if (!seen.isCompleted) seen.complete();
      if (held != null) return held!.future;
      if (lookupFailure != 200) return http.Response('{}', lookupFailure);
    }
    final result = await super.call(r);
    return result.statusCode == 201 ? http.Response(result.body, 200) : result;
  }

  Future<void> runPatient(Future<void> Function(PlanWithdrawalController) c) =>
      http.runWithClient(() async {
        await auth.login();
        final controller = PlanWithdrawalController();
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
  for (final mode in ['success', 'lost before', 'lost after']) {
    test(
      'plan withdrawal $mode freezes original identity without policy acceptance',
      () async {
        final w = Wire()..mode = mode;
        await w.runPatient((c) async {
          expect(c.plans.single.keys.toSet(), {
            'id',
            'patient_id',
            'doctor_id',
            'access_id',
            'kind',
            'revision',
            'state',
          });
          final row = c.plans.single;
          await c.cancel(row);
          await c.cancel(row);
          if (mode != 'success') {
            expect(c.pending, isNotNull);
            final key = c.pending!.key;
            await c.reconcile();
            if (mode == 'lost before') {
              w.mode = 'success';
              await c.reconcile(retryOriginal: true);
            }
            expect(
              w.sends.every((r) => r.headers['Idempotency-Key'] == key),
              true,
            );
          }
          expect(c.pending, isNull);
          expect(c.plans.single['state'], 'cancelled');
          expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
          expect(
            w.sends.every((r) => jsonDecode(r.body)['expected_revision'] == 1),
            true,
          );
        });
      },
    );
  }
  for (final code in [401, 403, 404, 409, 410, 422, 503]) {
    test('plan original lookup$code stays unresolved', () async {
      final w = Wire()..mode = 'lost after';
      await w.runPatient((c) async {
        await c.cancel(c.plans.single);
        w.lookupFailure = code;
        await c.reconcile(retryOriginal: true);
        expect(c.outcome, isNull);
        expect(w.sends.length, 1);
        expect(c.pending == null, code == 401);
      });
    });
  }
  test(
    'changed revision requires fresh review without silently replacing CAS',
    () async {
      final w = Wire();
      await w.runPatient((c) async {
        final row = c.plans.single;
        w.plan['revision'] = 2;
        await c.cancel(row);
        expect(c.pending, isNull);
        expect(c.plans, isEmpty);
        expect(w.sends.length, 1);
        await c.refresh();
        expect(c.plans.single['revision'], 2);
        expect(w.sends.length, 1);
      });
    },
  );
  test(
    'wrong original grant and expired receipt cannot confirm cancellation',
    () async {
      final w = Wire()..mode = 'lost after';
      await w.runPatient((c) async {
        await c.cancel(c.plans.single);
        w.receipts.values.single['access_id'] = 'new-grant';
        await c.reconcile();
        expect(c.pending, isNotNull);
        expect(c.outcome, isNull);
        w.mode = 'expired';
        await c.reconcile(retryOriginal: true);
        expect(c.lookupStatus, 'expired');
        expect(w.sends.length, 1);
      });
    },
  );
  for (final event in ['hide', 'logout', 'switch']) {
    test('plan late result after$event does not restore metadata', () async {
      final w = Wire()..mode = 'lost after';
      await w.runPatient((c) async {
        await c.cancel(c.plans.single);
        w.held = Completer<http.Response>();
        final read = c.reconcile();
        await w.seen.future;
        if (event == 'hide') {
          c.hide();
        } else {
          await ApiService.instance.init();
        }
        if (event == 'switch') {
          w.owner = 'patient-2';
          await auth.login();
        }
        w.held!.complete(
          http.Response(
            jsonEncode({
              'attempt_id': 'a',
              'status': 'committed',
              'result': w.receipts.values.single,
            }),
            200,
          ),
        );
        await read;
        expect(c.plans, isEmpty);
        expect(c.outcome, isNull);
      });
    });
  }
  testWidgets(
    'withdrawal real screen never displays clinical purpose or images',
    (t) async {
      final w = Wire();
      await http.runWithClient(() async {
        await auth.login();
        await t.pumpWidget(const MaterialApp(home: PlanWithdrawalScreen()));
        await t.pumpAndSettle();
        expect(find.text('Follow-up plan'), findsOneWidget);
        expect(find.text(w.plan['purpose']), findsNothing);
        expect(find.byType(Image), findsNothing);
        await t.tap(find.text('Withdraw from this plan'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byType(Checkbox));
        await t.pumpAndSettle();
        await t.tap(find.byType(Checkbox));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Cancel plan'));
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel plan'));
        await t.pumpAndSettle();
        expect(w.sends.length, 1);
        expect(
          find.textContaining('Original plan cancellation confirmed.'),
          findsOneWidget,
        );
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      }, () => MockClient(w.call));
    },
  );
}
