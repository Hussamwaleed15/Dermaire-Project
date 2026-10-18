import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/consent/clinician_withdrawal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_entry_withdrawal_test.dart' as base;
import 'wave_access_test.dart' as access;

class Wire extends base.Wire {
  late final rows = <Map<String, dynamic>>[
    {
      ...(access.AccessWire()..claimed = true).access,
      'doctor_name': 'First clinician',
    },
    {
      ...access.AccessWire().access,
      'id': 'grant-2',
      'doctor_id': 'doctor-2',
      'doctor_name': 'Second clinician',
    },
  ];
  int status = 200;
  bool before = false;
  final attempts = <String, Map<String, dynamic>>{};
  final started = Completer<void>();
  Completer<http.Response>? held;
  @override
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    final path = r.url.path;
    if (path.contains('/doctor/access') ||
        path.contains('/consent-attempts/revoke/')) {
      if (status != 200) return http.Response('{}', status);
      if (r.method == 'GET' && path.endsWith('/access')) {
        return http.Response(jsonEncode(rows), 200);
      }
      if (r.method == 'DELETE') {
        deletes++;
        final key = r.headers['Idempotency-Key']!;
        keys.add(key);
        if (before && lose) throw TimeoutException('synthetic');
        if (!attempts.containsKey(key)) {
          final g = rows.firstWhere((v) => v['id'] == r.url.pathSegments.last);
          g.addAll({
            'status': 'revoked',
            'revoked_at': '2026-10-18T13:00:00Z',
            'revoked_by': owner,
            'effective_scopes': <String>[],
          });
          attempts[key] = {
            'schema_version': 1,
            'attempt_id': 'attempt-1',
            'owner_id': owner,
            'actor_id': owner,
            'access_id': g['id'],
            'operation': 'revoke',
            'status': 'committed',
            'result_availability': 'retained',
            'snapshot_basis': 'original_committed_not_current',
            'result': Map.of(g),
          };
        }
        if (lose) throw TimeoutException('synthetic');
        return http.Response(jsonEncode(attempts[key]!['result']), 200);
      }
      lookups++;
      if (!started.isCompleted) started.complete();
      if (held != null) return held!.future;
      return http.Response(
        jsonEncode(
          attempts[r.url.pathSegments.last] ??
              {
                'schema_version': 1,
                'attempt_id': 'attempt-1',
                'status': 'unknown',
                'result': null,
                'retry_safe': false,
              },
        ),
        200,
      );
    }
    return super.call(r);
  }

  Future<void> runSelected(
    Future<void> Function(SelectiveWithdrawalController) body,
  ) => http.runWithClient(() async {
    await login();
    final c = SelectiveWithdrawalController();
    try {
      await c.refresh();
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
  for (final before in [true, false]) {
    test(
      'selected original grant loss before=$before preserves key and leaves other grants',
      () async {
        final w = Wire()..before = before;
        await w.runSelected((c) async {
          expect(c.grants.length, 2);
          c.select('grant-1');
          c.confirmScope(true);
          await c.withdrawAll();
          await c.withdrawAll();
          expect(w.deletes, 1);
          await c.reconcile();
          if (before) {
            expect(c.lookupStatus, 'unknown');
            w.lose = false;
            await c.reconcile(retryOriginal: true);
          }
          expect(c.pending, isNull);
          expect(w.keys.toSet().length, 1);
          expect(c.grants.first.status, 'revoked');
          expect(c.grants.last.status, 'pending');
          expect(w.accepts, 0);
          expect(ApiService.instance.hasConfirmedSafetyAcceptance, false);
        });
      },
    );
  }
  test(
    'original receipt does not revoke a later grant to same clinician',
    () async {
      final w = Wire();
      await w.runSelected((c) async {
        c.select('grant-1');
        c.confirmScope(true);
        await c.withdrawAll();
        w.rows.add({...w.rows.last, 'id': 'grant-3', 'doctor_id': 'doctor-1'});
        await c.reconcile(retryOriginal: true);
        expect(w.deletes, 1);
        expect(c.grants.last.status, 'pending');
      });
    },
  );
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    test(
      'selective lookup$status never claims success or replaces pending key',
      () async {
        final w = Wire();
        await w.runSelected((c) async {
          c.select('grant-1');
          c.confirmScope(true);
          await c.withdrawAll();
          w.status = status;
          await c.reconcile(retryOriginal: true);
          expect(c.outcome, isNull);
          expect(w.deletes, 1);
          expect(w.accepts, 0);
          expect(c.pending == null, status == 401);
        });
      },
    );
  }
  for (final kind in ['actor', 'grant', 'operation', 'current', 'expired']) {
    test('selective $kind mismatch stays unconfirmed', () async {
      final w = Wire();
      await w.runSelected((c) async {
        c.select('grant-1');
        c.confirmScope(true);
        await c.withdrawAll();
        final receipt = w.attempts.values.single;
        if (kind == 'actor') receipt['actor_id'] = 'other';
        if (kind == 'grant') receipt['access_id'] = 'grant-2';
        if (kind == 'operation') receipt['operation'] = 'revoke_all';
        if (kind == 'current') w.rows.first['status'] = 'pending';
        if (kind == 'expired') {
          receipt['status'] = 'expired';
          receipt['result_availability'] = 'expired';
          receipt['result'] = null;
        }
        await c.reconcile(retryOriginal: true);
        expect(c.pending, isNotNull);
        expect(w.deletes, 1);
      });
    });
  }
  for (final event in ['hide', 'logout', 'switch']) {
    test('selected late receipt after $event stays private', () async {
      final w = Wire();
      await w.runSelected((c) async {
        c.select('grant-1');
        c.confirmScope(true);
        await c.withdrawAll();
        w.held = Completer<http.Response>();
        final check = c.reconcile();
        await w.started.future;
        if (event == 'hide') {
          c.hide();
        } else {
          await ApiService.instance.init();
        }
        if (event == 'switch') {
          w.owner = 'patient-2';
          await w.login();
        }
        w.held!.complete(
          http.Response(jsonEncode(w.attempts.values.single), 200),
        );
        await check;
        expect(c.grants, isEmpty);
        expect(c.outcome, isNull);
        expect(c.confirmedScope, false);
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets('selective real screen320px200% dark=$dark', (t) async {
      await t.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final w = Wire()..lose = false;
      await http.runWithClient(() async {
        await w.login();
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(
                ctx,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const SelectiveWithdrawalScreen(),
          ),
        );
        await t.pumpAndSettle();
        final select = find.text('Select this grant').first;
        await t.ensureVisible(select);
        await t.pumpAndSettle();
        await t.tap(select);
        await t.pumpAndSettle();
        final cb = find.byType(Checkbox);
        await t.scrollUntilVisible(cb, 180);
        await t.ensureVisible(cb);
        await t.pumpAndSettle();
        await t.tap(cb);
        await t.pumpAndSettle();
        final send = find.text('Revoke selected grant');
        await t.ensureVisible(send);
        await t.pumpAndSettle();
        await t.tap(send);
        await t.pumpAndSettle();
        expect(w.deletes, 1);
        expect(w.accepts, 0);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      }, () => MockClient(w.call));
    });
  }
}
