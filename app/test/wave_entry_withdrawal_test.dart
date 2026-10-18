import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/consent/clinician_withdrawal.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Wire {
  String owner = 'patient-1', role = 'patient', loss = 'after';
  bool lose = true;
  int deletes = 0, lookups = 0, accepts = 0, permissions = 2, failure = 200;
  final keys = <String>[];
  final recorded = <String, Map<String, dynamic>>{};
  Map<String, dynamic> Function(Map<String, dynamic>)? change;
  Completer<http.Response>? delayed;
  final lookupSent = Completer<void>();
  Map<String, dynamic> value(String key) =>
      recorded[key] ??
      {
        'schema_version': 1,
        'attempt_id': 'withdrawal-attempt',
        'status': 'unknown',
        'result': null,
        'retry_safe': false,
      };
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/auth/login')) {
      return http.Response(
        jsonEncode({
          'access_token': 'synthetic-token',
          'expires_in': 3600,
          'user_id': owner,
          'role': role,
        }),
        200,
      );
    }
    if (r.url.path.endsWith('/users/me')) {
      return http.Response(
        jsonEncode({
          'id': owner,
          'role': role,
          'safety_accepted': false,
          'full_name': 'Synthetic account',
          'email': 'synthetic@example.invalid',
        }),
        200,
      );
    }
    if (r.url.path.endsWith('/auth/accept-safety')) {
      accepts++;
      return http.Response('{}', 503);
    }
    if (r.url.path.contains('/consent-attempts/')) {
      lookups++;
      final key = r.url.pathSegments.last;
      expect(r.method, 'GET');
      expect(r.url.path.contains('/revoke_all/'), true);
      if (!lookupSent.isCompleted) lookupSent.complete();
      if (delayed != null) return delayed!.future;
      final receipt = value(key);
      return http.Response(
        jsonEncode(change?.call(receipt) ?? receipt),
        failure,
      );
    }
    if (r.url.path.endsWith('/doctor/revoke/$owner')) {
      expect(r.method, 'DELETE');
      expect(r.body, isEmpty);
      final key = r.headers['Idempotency-Key']!;
      expect(key, matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')));
      keys.add(key);
      deletes++;
      if (loss == 'before' && lose) throw TimeoutException('synthetic');
      if (!recorded.containsKey(key)) {
        permissions = 0;
        recorded[key] = {
          'schema_version': 1,
          'attempt_id': 'withdrawal-attempt',
          'owner_id': owner,
          'actor_id': owner,
          'access_id': owner,
          'operation': 'revoke_all',
          'status': 'committed',
          'result_availability': 'retained',
          'result': {
            'success': true,
            'message': 'Clinician access revoked immediately.',
          },
          'snapshot_basis': 'original_committed_not_current',
        };
      }
      if (lose) throw TimeoutException('synthetic');
      return http.Response('{"success":true}', 200);
    }
    throw StateError('Unexpected synthetic request ${r.method}');
  }

  Future<void> login() async {
    await ApiService.instance.login(
      email: 'synthetic@example.invalid',
      password: 'synthetic',
    );
    expect(await ApiService.instance.readSafetyAcceptance(), false);
  }

  Future<void> run(
    Future<void> Function(ClinicianWithdrawalController c) body,
  ) => http.runWithClient(() async {
    await login();
    final c = ClinicianWithdrawalController();
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
  test('withdrawal requires explicit scope and never accepts policy', () async {
    final w = Wire()..lose = false;
    await w.run((c) async {
      expect(c.canWithdraw, true);
      expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
      await c.withdrawAll();
      expect(w.deletes, 0);
      c.confirmScope(true);
      await c.withdrawAll();
      expect(w.deletes, 1);
      expect(c.pending, isNull);
      expect(w.lookups, 1);
      expect(w.permissions, 0);
      expect(c.outcome, contains('original withdrawal'));
      expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
      expect(w.accepts, 0);
    });
  });
  for (final loss in ['before', 'after']) {
    test(
      'policy-required withdrawal $loss loss preserves original key',
      () async {
        final w = Wire()..loss = loss;
        await w.run((c) async {
          c.confirmScope(true);
          await c.withdrawAll();
          expect(c.pending, isNotNull);
          expect(w.deletes, 1);
          await c.withdrawAll();
          expect(w.deletes, 1);
          await c.reconcile();
          if (loss == 'before') {
            expect(c.lookupStatus, 'unknown');
            w.lose = false;
            await c.reconcile(retryOriginal: true);
            expect(w.keys.toSet().length, 1);
            expect(w.deletes, 2);
          } else {
            await c.reconcile(retryOriginal: true);
            expect(w.deletes, 1);
          }
          expect(c.pending, isNull);
          expect(w.accepts, 0);
          expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
        });
      },
    );
  }
  test('replayed original withdrawal cannot revoke a later grant', () async {
    final w = Wire();
    await w.run((c) async {
      c.confirmScope(true);
      await c.withdrawAll();
      w.permissions = 1;
      await c.reconcile(retryOriginal: true);
      expect(w.permissions, 1);
      expect(w.deletes, 1);
      expect(
        c.outcome,
        contains('Permissions granted afterwards are not included'),
      );
      expect(c.confirmedScope, false);
      expect(c.pending, isNull);
    });
  });
  for (final bad in [
    'actor',
    'owner',
    'access',
    'operation',
    'basis',
    'success',
    'expired',
  ]) {
    test(
      'withdrawal $bad receipt cannot create a current-access claim',
      () async {
        final w = Wire()
          ..change = (v) {
            if (bad == 'actor') v['actor_id'] = 'other';
            if (bad == 'owner') v['owner_id'] = 'other';
            if (bad == 'access') v['access_id'] = 'other';
            if (bad == 'operation') v['operation'] = 'issue';
            if (bad == 'basis') v['snapshot_basis'] = 'current';
            if (bad == 'success') v['result'] = {'success': false};
            if (bad == 'expired') {
              v['status'] = 'expired';
              v['result_availability'] = 'expired';
              v['result'] = null;
            }
            return v;
          };
        await w.run((c) async {
          c.confirmScope(true);
          await c.withdrawAll();
          await c.reconcile(retryOriginal: true);
          expect(c.pending, isNotNull);
          expect(w.deletes, 1);
          expect(w.accepts, 0);
          if (bad == 'expired') {
            expect(c.lookupStatus, 'expired');
            expect(c.outcome, contains('expired'));
          } else {
            expect(c.error, isNotNull);
          }
        });
      },
    );
  }
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    test(
      'withdrawal lookup$status never invents confirmation or a new key',
      () async {
        final w = Wire()..failure = status;
        await w.run((c) async {
          c.confirmScope(true);
          await c.withdrawAll();
          await c.reconcile(retryOriginal: true);
          expect(w.deletes, 1);
          expect(w.accepts, 0);
          expect(c.outcome, isNull);
          if (status == 401) {
            expect(c.pending, isNull);
            expect(c.authenticatedCurrent, false);
          } else {
            expect(c.pending, isNotNull);
          }
        });
      },
    );
  }
  for (final event in ['hide', 'logout', 'switch']) {
    test(
      'late withdrawal receipt after $event cannot restore view or authority',
      () async {
        final w = Wire()..delayed = Completer<http.Response>();
        await w.run((c) async {
          c.confirmScope(true);
          final send = c.withdrawAll();
          // Initial reply was lost: explicit lookup remains the only readback.
          await send;
          final lookup = c.reconcile();
          await w.lookupSent.future;
          if (event == 'hide') {
            c.hide();
          } else {
            await ApiService.instance.init();
          }
          if (event == 'switch') {
            w.owner = 'patient-2';
            await w.login();
          }
          final value = w.recorded.values.first;
          w.delayed!.complete(http.Response(jsonEncode(value), 200));
          await lookup;
          expect(c.outcome, isNull);
          expect(c.confirmedScope, false);
          expect(w.deletes, 1);
        });
      },
    );
  }
  test('doctor role cannot call patient withdrawal', () async {
    final w = Wire()..role = 'doctor';
    await w.run((c) async {
      c.confirmScope(true);
      await c.withdrawAll();
      expect(w.deletes, 0);
      expect(c.canWithdraw, false);
    });
  });
  for (final path in [
    'doctor/consent-attempts/issue/abcdefghijklmnop',
    'doctor/patients/private-patient',
    'clinical-snapshot',
    'clinical-plans/private-plan',
  ]) {
    test('withdrawal flag cannot open private GET $path', () async {
      final w = Wire();
      await w.run((c) async {
        await expectLater(
          ApiService.instance.integrationResource(
            path,
            c.generation,
            withdrawal: true,
          ),
          throwsArgumentError,
        );
        expect(w.lookups, 0);
        expect(w.accepts, 0);
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'real entry gate permits withdrawal without shell320px200% dark=$dark',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final w = Wire()..lose = false;
        final state = DermaireState();
        await http.runWithClient(() async {
          await w.login();
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: PatientEntryGate(state: state),
            ),
          );
          await t.pumpAndSettle();
          expect(find.byType(AppShell), findsNothing);
          await t.ensureVisible(find.text('Manage clinician access'));
          await t.tap(find.text('Manage clinician access'));
          await t.pumpAndSettle();
          expect(find.text('Clinician access controls'), findsOneWidget);
          await t.scrollUntilVisible(
            find.byKey(const Key('confirmClinicianWithdrawal')),
            180,
          );
          final checkbox = find.descendant(
            of: find.byKey(const Key('confirmClinicianWithdrawal')),
            matching: find.byType(Checkbox),
          );
          await t.ensureVisible(checkbox);
          await t.pumpAndSettle();
          await t.tap(checkbox);
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Withdraw clinician access'));
          await t.tap(find.text('Withdraw clinician access'));
          await t.pumpAndSettle();
          expect(w.deletes, 1);
          expect(w.accepts, 0);
          expect(find.byType(AppShell), findsNothing);
          expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          state.dispose();
          await ApiService.instance.init();
        }, () => MockClient(w.call));
      },
    );
  }
}
