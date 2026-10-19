import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/doctor/access_invitation.dart';
import 'package:dermaire_app/consent/clinician_withdrawal.dart';
import 'package:dermaire_app/recovery/grant_receipt_reader.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_access_test.dart' as access_fixture;
import 'wave_q_domain_readers_test.dart' show identity;
import 'm6_doctor_fixture.dart' as base;

class GrantWire extends access_fixture.AccessWire {
  GrantWire({super.doctor});
  bool additionalGrant = false;
  int withdrawals = 0;
  final withdrawalReceipts = <String, Map<String, dynamic>>{};
  Map<String, dynamic> Function(Map<String, dynamic>)? change;
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    final path = r.url.path;
    if (r.method == 'DELETE' &&
        (path.contains('/doctor/access/') ||
            path.contains('/doctor/revoke/'))) {
      withdrawals++;
      revoked = true;
      final operation = path.contains('/access/') ? 'revoke' : 'revoke_all';
      final key = r.headers['Idempotency-Key']!;
      withdrawalReceipts[key] = {
        'schema_version': 1,
        'attempt_id': 'withdrawal-$key',
        'owner_id': owner,
        'actor_id': owner,
        'access_id': operation == 'revoke' ? 'grant-1' : owner,
        'operation': operation,
        'status': 'committed',
        'result_availability': 'retained',
        'snapshot_basis': 'original_committed_not_current',
        'result': operation == 'revoke'
            ? Map<String, dynamic>.of(access)
            : {
                'success': true,
                'message': 'Clinician access revoked immediately.',
              },
      };
      throw TimeoutException('Synthetic committed withdrawal response loss');
    }
    if (path.contains('/consent-attempts/revoke')) {
      final raw =
          withdrawalReceipts[path.split('/').last] ??
          {
            'schema_version': 1,
            'attempt_id': 'unknown-attempt',
            'status': 'unknown',
            'result': null,
            'retry_safe': false,
          };
      return base.json(change?.call(raw) ?? raw);
    }
    if (path.endsWith('/doctor/access') && additionalGrant) {
      return base.json([
        access,
        {
          ...access,
          'id': 'additional-grant',
          'status': 'active',
          'revoked_at': null,
          'revoked_by': null,
          'effective_scopes': ['VIEW'],
        },
      ]);
    }
    final response = await super.call(r);
    if (change != null && path.contains('/attempts/') ||
        change != null && path.contains('/consent-attempts/')) {
      return base.json(
        change!(jsonDecode(response.body) as Map<String, dynamic>),
        response.statusCode,
      );
    }
    return response;
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  test(
    'issue metadata never restores bearer or advertises old code validity',
    () async {
      final w = GrantWire();
      await w.run(() async {
        await w.login();
        final c = AccessInvitationController();
        try {
          w.mode = 'lost after';
          expect(await c.issue('doctor-1', consent: true), false);
          final i = identity(c.pending!, w.owner, w.role);
          final reader = GrantReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.outcome, ReceiptOutcome.committed);
          expect(r.resource, 'grant-1');
          expect(await reader.verifyCurrent(i, r), false);
          expect(jsonEncode(i.toJson()), isNot(contains(w.code)));
          expect(c.token, isNull);
          w.claimed = true;
          final unavailable = await reader.lookup(i);
          expect(unavailable.outcome, ReceiptOutcome.committed);
          expect(await reader.verifyCurrent(i, unavailable), false);
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
        }
      });
    },
  );
  test(
    'claim minimum routing hint is never authority; receipt and current original grant required',
    () async {
      final w = GrantWire(doctor: true);
      await w.run(() async {
        await w.login();
        final c = ClaimInvitationController();
        try {
          w.mode = 'lost after';
          expect(await c.claim(w.code, confirmed: true), false);
          final i = identity(c.pending!, w.owner, w.role);
          expect(i.scope['patient_id'], 'patient-1');
          expect(i.receiptPath, 'doctor/patients/patient-1/attempts/claim');
          expect(jsonEncode(i.toJson()), isNot(contains(w.code)));
          final reader = GrantReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.outcome, ReceiptOutcome.committed);
          expect(await reader.verifyCurrent(i, r), true);
          w.newGrant = true;
          await expectLater(
            reader.lookup(i),
            throwsA(isA<RecoveryPermissionLost>()),
          );
          expect(w.sends.length, 1);
          expect(c.grant, isNull);
        } finally {
          c.dispose();
        }
      });
    },
  );
  test('unparseable claim bearer has no invented recovery lookup', () async {
    final w = GrantWire(doctor: true);
    await w.run(() async {
      await w.login();
      final c = ClaimInvitationController();
      try {
        // Routing hint failure does not establish a patient or a fake endpoint.
        expect(c.candidateToken('opaque-untrusted-code'), isNull);
        expect(
          c.candidateToken('a.eyJwYXRpZW50X2lkIjoiLi4vZm9yZWlnbiJ9.c'),
          isNull,
        );
        expect(w.sends, isEmpty);
      } finally {
        c.dispose();
      }
    });
  });
  for (final selected in [false, true]) {
    test(
      'withdrawal receipt selected=$selected is separate from current permissions',
      () async {
        final w = GrantWire()
          ..issued = true
          ..claimed = true;
        await w.run(() async {
          await w.login();
          final ClinicianWithdrawalController c = selected
              ? SelectiveWithdrawalController()
              : ClinicianWithdrawalController();
          try {
            await c.refresh();
            if (c is SelectiveWithdrawalController) c.select('grant-1');
            c.confirmScope(true);
            await c.withdrawAll();
            final i = identity(c.pending!, w.owner, w.role);
            final reader = GrantReceiptReader(api, api.sessionGeneration);
            final r = await reader.lookup(i);
            expect(r.outcome, ReceiptOutcome.committed);
            expect(await reader.verifyCurrent(i, r), true);
            w.additionalGrant = true;
            expect(await reader.verifyCurrent(i, r), selected);
            expect(w.withdrawals, 1);
            expect(c.pending!.key, i.key);
          } finally {
            c.dispose();
          }
        });
      },
    );
  }
  for (final operation in ['issue', 'claim']) {
    for (final state in ['expired', 'wrong actor', 'wrong grant']) {
      test('$operation $state metadata never restores access', () async {
        final w = GrantWire(doctor: operation == 'claim');
        await w.run(() async {
          await w.login();
          final issue = operation == 'issue'
              ? AccessInvitationController()
              : null;
          final claim = operation == 'claim'
              ? ClaimInvitationController()
              : null;
          try {
            w.mode = 'lost after';
            if (issue != null) await issue.issue('doctor-1', consent: true);
            if (claim != null) await claim.claim(w.code, confirmed: true);
            final i = identity(
              (issue?.pending ?? claim!.pending)!,
              w.owner,
              w.role,
            );
            w.change = (v) => state == 'expired'
                ? {
                    ...v,
                    'status': 'expired',
                    'result_availability': 'expired',
                    'result': null,
                  }
                : state == 'wrong actor'
                ? {...v, 'actor_id': 'another-account'}
                : {...v, 'access_id': 'another-grant'};
            final reader = GrantReceiptReader(api, api.sessionGeneration);
            if (state == 'expired') {
              final r = await reader.lookup(i);
              expect(r.outcome, ReceiptOutcome.expired);
              expect(await reader.verifyCurrent(i, r), false);
            } else {
              await expectLater(reader.lookup(i), throwsA(anything));
            }
            expect(w.sends.length, 1);
            expect(issue?.token, isNull);
            expect(claim?.grant, isNull);
          } finally {
            issue?.dispose();
            claim?.dispose();
          }
        });
      });
    }
  }
  test(
    'unknown invitation is not rejected and never a replacement key',
    () async {
      final w = GrantWire();
      await w.run(() async {
        await w.login();
        final c = AccessInvitationController();
        try {
          w.mode = 'lost before';
          await c.issue('doctor-1', consent: true);
          final i = identity(c.pending!, w.owner, w.role);
          final r = await GrantReceiptReader(
            api,
            api.sessionGeneration,
          ).lookup(i);
          expect(r.outcome, ReceiptOutcome.unknown);
          expect(c.pending!.key, i.key);
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
        }
      });
    },
  );
}
