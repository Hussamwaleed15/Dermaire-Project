import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/doctor/access_invitation.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

class AccessWire extends f.DoctorWire {
  AccessWire({bool doctor = false}) {
    owner = doctor ? 'doctor-1' : 'patient-1';
    role = doctor ? 'doctor' : 'patient';
  }
  String mode = 'success';
  bool issued = false, claimed = false, revoked = false, newGrant = false;
  final sends = <http.Request>[],
      issues = <String, Map<String, dynamic>>{},
      claims = <String, Map<String, dynamic>>{},
      bodies = <String, String>{};
  Completer<http.Response>? delay;
  String get code =>
      'e30.${base64Url.encode(utf8.encode(jsonEncode({'patient_id': 'patient-1'}))).replaceAll('=', '')}.synthetic-signature';
  String get expiry =>
      DateTime.now().toUtc().add(const Duration(hours: 1)).toIso8601String();
  late final String fixedExpiry = expiry;
  Map<String, dynamic> get access => {
    'id': newGrant ? 'grant-2' : 'grant-1',
    'patient_id': 'patient-1',
    'doctor_id': 'doctor-1',
    'granted_by': 'patient-1',
    'doctor_name': 'Synthetic clinician',
    'status': revoked
        ? 'revoked'
        : claimed
        ? 'active'
        : 'pending',
    'created_at': '2026-10-01T00:00:00Z',
    'expires_at': fixedExpiry,
    'claimed_at': claimed ? '2026-10-18T12:00:00Z' : null,
    'revoked_at': revoked ? '2026-10-18T13:00:00Z' : null,
    'revoked_by': revoked ? 'patient-1' : null,
    'consent_version': 2,
    'consent_source': 'explicit_patient_intent',
    'view_consent': true,
    'export_consent': false,
    'scopes': ['VIEW'],
    'effective_scopes': claimed && !revoked ? ['VIEW'] : [],
  };
  Map<String, dynamic> get invitation => {
    'access_token': code,
    'qr_payload': 'dermaire://doctor-access?token=$code',
    'expires_at': fixedExpiry,
    'instructions': 'Give only to intended clinician.',
    'access': access,
  };
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    final path = r.url.path;
    if (path.endsWith('/doctor/access')) return f.json(issued ? [access] : []);
    if (path.contains('/consent-attempts/issue/')) {
      final key = path.split('/').last, row = issues[key];
      return row == null
          ? f.json({
              'schema_version': 1,
              'status': 'unknown',
              'result': null,
              'retry_safe': false,
            })
          : f.json({
              'schema_version': 1,
              'attempt_id': 'issue-attempt',
              'actor_id': owner,
              'owner_id': owner,
              'access_id': 'grant-1',
              'operation': 'issue',
              'status': 'committed',
              'result_availability': claimed || revoked
                  ? 'unavailable'
                  : 'retained',
              'result': claimed || revoked ? null : row,
              'snapshot_basis': 'original_committed_not_current',
            });
    }
    if (path.contains('/attempts/claim/')) {
      if (!claimed || revoked) return f.json({}, 403);
      final row = claims[path.split('/').last];
      return f.json({
        'schema_version': 1,
        'attempt_id': 'claim-attempt',
        'actor_id': owner,
        'patient_id': 'patient-1',
        'access_id': 'grant-1',
        'operation': 'claim',
        'status': row == null ? 'unknown' : 'committed',
        'result': row,
        'snapshot_basis': 'original_committed_not_current',
      });
    }
    if (path.endsWith('/doctor/generate-qr') ||
        path.endsWith('/doctor/claim')) {
      sends.add(r);
      if (delay != null) return delay!.future;
      if (int.tryParse(mode) != null) return f.json({}, int.parse(mode));
      if (mode == 'lost before') {
        throw TimeoutException('synthetic before commit');
      }
      final key = r.headers['Idempotency-Key']!,
          body = jsonDecode(r.body) as Map;
      final issue = path.endsWith('/generate-qr');
      final rows = issue ? issues : claims;
      if (rows.containsKey(key)) {
        if (bodies[key] != r.body) return f.json({}, 409);
        return f.json(rows[key]);
      }
      if (issue) {
        expect(r.url.queryParameters['minutes_valid'], '60');
        expect(body, {
          'view_consent': true,
          'export_consent': false,
          'doctor_id': 'doctor-1',
        });
        issued = true;
      } else {
        if (revoked) return f.json({}, 403);
        expect(body['access_token'], code);
        issued = true;
        claimed = true;
      }
      final result = issue
          ? invitation
          : {
              'success': true,
              'message': 'Patient access granted.',
              'access': access,
            };
      rows[key] = Map.from(result);
      bodies[key] = r.body;
      if (mode == 'lost after') {
        throw TimeoutException('synthetic after commit');
      }
      if (mode == 'wrong doctor') {
        return f.json({
          ...result,
          'access': {...access, 'doctor_id': 'foreign'},
        });
      }
      if (mode == 'fake scope') {
        return f.json({
          ...result,
          'access': {
            ...access,
            'effective_scopes': ['EXPORT'],
          },
        });
      }
      return f.json(result);
    }
    if (path.endsWith('/doctor/patients')) {
      if (mode == 'readback denied') return f.json({}, 403);
      return f.json(
        claimed && !revoked
            ? [
                {
                  ...row,
                  'access': [access],
                },
              ]
            : [],
      );
    }
    if (path.endsWith('/doctor/patients/patient-1')) {
      return revoked
          ? f.json({}, 403)
          : f.json({
              'patient_id': 'patient-1',
              'full_name': 'Synthetic patient',
              'access': access,
            });
    }
    return super.call(r);
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
    'invitation requires explicit VIEW consent and actual selected doctor',
    () async {
      final w = AccessWire();
      await w.run(() async {
        await w.login();
        final c = AccessInvitationController();
        await c.refresh();
        expect(await c.issue('doctor-1', consent: false), isFalse);
        expect(await c.issue('../invalid', consent: true), isFalse);
        expect(w.sends, isEmpty);
        expect(await c.issue('doctor-1', consent: true), isTrue);
        expect(c.token, w.code);
        expect(c.grant!.grant.status, 'pending');
        expect(c.grant!.effective, isEmpty);
        expect(c.grant!.scopes, ['VIEW']);
        c.dispose();
      });
    },
  );
  test(
    'claimed VIEW is shown only after current original grant and patient readback',
    () async {
      final w = AccessWire(doctor: true);
      await w.run(() async {
        await w.login();
        final c = ClaimInvitationController();
        expect(await c.claim(w.code, confirmed: false), isFalse);
        expect(w.sends, isEmpty);
        expect(await c.claim(w.code, confirmed: true), isTrue);
        expect(c.grant!.grant.patientId, 'patient-1');
        expect(c.grant!.effective, ['VIEW']);
        expect(c.pending, isNull);
        c.dispose();
      });
    },
  );
  for (final issue in [false, true]) {
    for (final loss in ['lost before', 'lost after']) {
      test(
        '${issue ? 'issue' : 'claim'} $loss reconciles original key/body',
        () async {
          final w = AccessWire(doctor: !issue);
          await w.run(() async {
            await w.login();
            w.mode = loss;
            if (issue) {
              final c = AccessInvitationController();
              expect(await c.issue('doctor-1', consent: true), isFalse);
              final intent = c.pending!;
              expect(c.token, isNull);
              w.mode = 'success';
              await c.reconcile(retry: true);
              expect(c.pending, isNull);
              expect(c.token, w.code);
              expect(w.issues.length, 1);
              expect(
                w.sends.every(
                  (r) =>
                      r.headers['Idempotency-Key'] == intent.key &&
                      r.body == w.sends.first.body,
                ),
                isTrue,
              );
              c.dispose();
            } else {
              final c = ClaimInvitationController();
              expect(await c.claim(w.code, confirmed: true), isFalse);
              final intent = c.pending!;
              w.mode = 'success';
              await c.reconcile(retry: true);
              expect(c.pending, isNull);
              expect(c.grant!.effective, ['VIEW']);
              expect(w.claims.length, 1);
              expect(
                w.sends.every(
                  (r) =>
                      r.headers['Idempotency-Key'] == intent.key &&
                      r.body == w.sends.first.body,
                ),
                isTrue,
              );
              c.dispose();
            }
          });
        },
      );
    }
  }
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    for (final issue in [false, true]) {
      test('access $status issue=$issue never invents authority', () async {
        final w = AccessWire(doctor: !issue);
        await w.run(() async {
          await w.login();
          w.mode = '$status';
          if (issue) {
            final c = AccessInvitationController();
            expect(await c.issue('doctor-1', consent: true), isFalse);
            expect(c.token, isNull);
            expect(c.grant, isNull);
            c.dispose();
          } else {
            final c = ClaimInvitationController();
            expect(await c.claim(w.code, confirmed: true), isFalse);
            expect(c.grant, isNull);
            expect(c.outcome, isNull);
            c.dispose();
          }
        });
      });
    }
  }
  for (final mode in ['wrong doctor', 'fake scope', 'readback denied']) {
    test('claim $mode never grants access', () async {
      final w = AccessWire(doctor: true)..mode = mode;
      await w.run(() async {
        await w.login();
        final c = ClaimInvitationController();
        expect(await c.claim(w.code, confirmed: true), isFalse);
        expect(c.grant, isNull);
        expect(c.pending, isNotNull);
        c.dispose();
      });
    });
  }
  test('new grant cannot restore original claimed authority', () async {
    final w = AccessWire(doctor: true);
    await w.run(() async {
      await w.login();
      final c = ClaimInvitationController();
      w.mode = 'lost after';
      expect(await c.claim(w.code, confirmed: true), isFalse);
      w.mode = 'success';
      w.newGrant = true;
      await c.reconcile();
      expect(c.grant, isNull);
      expect(c.pending, isNotNull);
      c.dispose();
    });
  });
  test(
    'claimed or revoked invitation receipt never restores bearer code',
    () async {
      final w = AccessWire();
      await w.run(() async {
        await w.login();
        final c = AccessInvitationController();
        await c.issue('doctor-1', consent: true);
        expect(c.token, isNotNull);
        c.hide();
        expect(c.token, isNull);
        w.claimed = true;
        await c.show();
        expect(c.token, isNull);
        expect(c.outcome, contains('No usable code'));
        expect(api.integrationReferences['doctor-issued-key'], isNull);
        c.dispose();
      });
    },
  );
  for (final change in ['hide', 'logout', 'switch']) {
    test('late invite after $change does not display code', () async {
      final w = AccessWire();
      await w.run(() async {
        await w.login();
        final c = AccessInvitationController();
        w.delay = Completer();
        final future = c.issue('doctor-1', consent: true);
        await Future<void>.delayed(Duration.zero);
        if (change == 'hide') {
          c.hide();
        } else if (change == 'logout') {
          await api.logout();
        } else {
          w.owner = 'patient-2';
          await w.login();
        }
        w.delay!.complete(f.json(w.invitation));
        expect(await future, isFalse);
        expect(c.token, isNull);
        expect(c.grant, isNull);
        c.dispose();
      });
    });
  }
  for (final dark in [false, true]) {
    for (final claim in [false, true]) {
      testWidgets('access forms readable 320px 200% dark=$dark claim=$claim', (
        tester,
      ) async {
        final w = AccessWire(doctor: claim);
        await w.run(() async {
          await w.login();
          tester.view.physicalSize = const Size(320, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: claim
                  ? const ClaimInvitationScreen()
                  : const AccessInvitationScreen(),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              claim ? 'Claim patient invitation' : 'Invite your clinician',
            ),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.text(
              claim
                  ? 'Claim original invitation'
                  : 'Create one-hour invitation',
            ),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await api.logout();
        });
      });
    }
  }
}
