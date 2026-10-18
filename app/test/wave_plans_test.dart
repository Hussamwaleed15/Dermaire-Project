import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/plans/plan_models.dart';
import 'package:dermaire_app/plans/plan_controller.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

class PlanWire extends f.DoctorWire {
  PlanWire({bool doctor = false}) {
    owner = doctor ? 'doctor-1' : 'patient-1';
    role = doctor ? 'doctor' : 'patient';
  }
  String mode = 'success';
  bool revoked = false;
  final receipts = <String, Map<String, dynamic>>{};
  final events = <Map<String, dynamic>>[];
  final sends = <http.Request>[];
  Completer<http.Response>? delayed;
  Map<String, dynamic> plan = {
    'schema_version': 'clinical-plan-1',
    'id': 'plan-1',
    'patient_id': 'patient-1',
    'doctor_id': 'doctor-1',
    'access_id': 'grant-patient-1',
    'kind': 'follow_up',
    'state': 'proposed',
    'revision': 1,
    'purpose': 'Review current skin tolerance',
    'due_at_utc': '2027-01-12T08:00:00Z',
    'created_at': '2026-10-18T10:00:00Z',
    'schedule_provenance': {
      'policy': 'fixed_utc_explicit_reschedule_v1',
      'timezone': 'Africa/Cairo',
      'local_time': '2027-01-12T10:00:00',
      'fold': 0,
      'due_at_utc': '2027-01-12T08:00:00Z',
    },
    'source_snapshot': <String, dynamic>{},
    'baseline_capture_id': null,
    'followup_capture_id': null,
    'acknowledged_at': null,
    'provenance': 'clinician_authored',
    'patient_visible': true,
    'clinical_clearance': false,
    'image_inference': {
      'status': 'unavailable',
      'reason': 'validated_model_not_integrated',
    },
  };
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    final path = request.url.path;
    if (!path.contains('/clinical-plans')) return super.call(request);
    requests.add(request);
    if (revoked) return f.json({}, 403);
    if (path.contains('/attempts/') || path.contains('/creation-attempts/')) {
      final row = receipts[path.split('/').last];
      return f.json({
        'attempt_id': 'attempt-1',
        'status': mode == 'expired'
            ? 'expired'
            : row == null
            ? 'unknown'
            : 'committed',
        'result': mode == 'expired' ? null : row,
      });
    }
    if (request.method == 'POST') {
      sends.add(request);
      if (delayed != null) return delayed!.future;
      if (int.tryParse(mode) != null) return f.json({}, int.parse(mode));
      if (mode == 'lost before') throw TimeoutException('synthetic');
      final body = jsonDecode(request.body) as Map;
      final operation = path.split('/').last;
      final key = request.headers['Idempotency-Key']!;
      final previous = receipts[key];
      if (previous != null) return f.json(previous, 201);
      if (operation != 'clinical-plans' &&
          body['expected_revision'] != plan['revision']) {
        return f.json({}, 409);
      }
      final result = Map<String, dynamic>.from(plan);
      if (operation == 'clinical-plans') {
        result['purpose'] = body['purpose'];
        result['kind'] = body['kind'];
        result['access_id'] = body['access_id'];
        result['baseline_capture_id'] = body['baseline_capture_id'];
        if (body['source_id'] != null) {
          result['source_snapshot'] = {
            'source_id': body['source_id'],
            'source_type': body['source_type'],
          };
        }
      } else {
        result['revision'] = (plan['revision'] as int) + 1;
        result['state'] = {
          'acknowledge': 'scheduled',
          'cancel': 'cancelled',
          'reschedule': 'proposed',
          'review': 'reviewed',
          'capture': 'captured',
        }[operation];
      }
      if (operation == 'acknowledge') {
        result['acknowledged_at'] = '2026-10-18T12:00:00Z';
      }
      if (operation == 'reschedule' || operation == 'clinical-plans') {
        result['schedule_provenance'] = {
          ...plan['schedule_provenance'] as Map,
          'local_time': body['local_due'],
          'timezone': body['timezone'],
          'fold': body['fold'] ?? 0,
        };
        if (operation == 'reschedule') result['acknowledged_at'] = null;
      }
      if (operation == 'capture') {
        result['followup_capture_id'] = body['capture_id'];
      }
      plan = result;
      receipts[key] = Map.from(result);
      events.add({
        'revision': result['revision'],
        'operation': operation == 'clinical-plans' ? 'create' : operation,
        'actor_id': owner,
        'recorded_at': '2026-10-18T12:00:00Z',
        'snapshot': {
          'plan': Map.from(result),
          'details': {'assessment': body['assessment']},
        },
      });
      if (mode == 'lost after') throw TimeoutException('synthetic');
      if (mode == 'newer readback') {
        plan = {
          ...result,
          'revision': (result['revision'] as int) + 1,
          'state': 'cancelled',
        };
      }
      if (mode == 'wrong owner') {
        return f.json({...result, 'patient_id': 'foreign'}, 201);
      }
      return f.json(result, 201);
    }
    if (path.endsWith('/history')) {
      final after = int.parse(request.url.queryParameters['after_revision']!);
      return f.json({
        'items': events.where((e) => e['revision'] > after).toList(),
        'next_after_revision': null,
        'numeric_comparison_metrics': null,
        'model_status': 'unavailable',
      });
    }
    if (path.endsWith('/clinical-plans')) {
      return f.json({
        'items': [plan],
        'next_after': null,
      });
    }
    return f.json(plan);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final doctor in [false, true]) {
    test(
      'role $doctor reads real current plans and immutable history',
      () async {
        final w = PlanWire(doctor: doctor);
        await w.run(() async {
          await w.login();
          final list = PlansController();
          await list.refresh();
          expect(list.plans.single.id, 'plan-1');
          final c = PlanController('plan-1');
          await c.refresh();
          expect(c.value!.revision, 1);
          expect(c.history, isEmpty);
          if (doctor) {
            expect(
              await c.mutate('review', {
                'assessment': 'Clinician reviewed tolerance.',
              }, 1),
              isTrue,
            );
          } else {
            expect(await c.mutate('acknowledge', {'consent': true}, 1), isTrue);
          }
          expect(c.value!.revision, 2);
          expect(c.history.single.revision, 2);
          expect(c.pending, isNull);
          c.dispose();
          list.dispose();
        });
      },
    );
  }
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    test('plan mutation $status never confirms success', () async {
      final w = PlanWire();
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        w.mode = '$status';
        expect(await c.mutate('acknowledge', {'consent': true}, 1), isFalse);
        expect(c.outcome, isNull);
        expect(c.error != null || !c.current, isTrue);
        c.dispose();
      });
    });
  }
  for (final loss in ['lost before', 'lost after']) {
    test(
      '$loss reconciles original key and revision without duplicates',
      () async {
        final w = PlanWire();
        await w.run(() async {
          await w.login();
          final c = PlanController('plan-1');
          await c.refresh();
          w.mode = loss;
          expect(await c.mutate('acknowledge', {'consent': true}, 1), isFalse);
          final intent = c.pending!;
          expect(
            await c.mutate('cancel', {'reason': 'Different action'}, 1),
            isFalse,
          );
          w.mode = 'success';
          expect(await c.reconcile(retryOriginal: true), isTrue);
          expect(c.value!.revision, 2);
          expect(w.events.length, 1);
          expect(
            w.sends.every(
              (r) =>
                  r.headers['Idempotency-Key'] == intent.key &&
                  r.body == w.sends.first.body,
            ),
            isTrue,
          );
          c.dispose();
        });
      },
    );
  }
  test('historical receipt never rolls back a newer current plan', () async {
    final w = PlanWire();
    await w.run(() async {
      await w.login();
      final c = PlanController('plan-1');
      await c.refresh();
      w.mode = 'newer readback';
      expect(await c.mutate('acknowledge', {'consent': true}, 1), isTrue);
      expect(c.value!.state, 'cancelled');
      expect(c.value!.revision, 3);
      c.dispose();
    });
  });
  test('reschedule preserves wall clock timezone and explicit fold', () async {
    final w = PlanWire(doctor: true);
    await w.run(() async {
      await w.login();
      final c = PlanController('plan-1');
      await c.refresh();
      expect(
        await c.mutate('reschedule', {
          'local_due': '2027-01-12T10:00',
          'timezone': 'Africa/Cairo',
          'fold': 0,
        }, 1),
        isTrue,
      );
      final body = jsonDecode(w.sends.single.body);
      expect(body['local_due'], '2027-01-12T10:00');
      expect(body['fold'], 0);
      expect(c.value!.state, 'proposed');
      expect(c.value!.acknowledged, isNull);
      c.dispose();
    });
  });
  test(
    'doctor creates only through original confirmed patient grant',
    () async {
      final w = PlanWire(doctor: true);
      await w.run(() async {
        await w.login();
        final parent = DoctorWorkspaceController(
          AccessSession(userId: w.owner, role: UserRole.doctor),
        );
        await parent.refresh();
        final conn = DoctorConnectionController(parent, w.patient);
        await conn.refresh();
        final c = CreatePlanController(conn);
        expect(c.current, isTrue);
        expect(
          await c.create({
            'kind': 'follow_up',
            'purpose': 'Review current skin tolerance',
            'local_due': '2027-01-12T10:00',
            'timezone': 'Africa/Cairo',
            'fold': 0,
          }),
          isTrue,
        );
        expect(c.created!.grant, 'grant-patient-1');
        expect(c.pending, isNull);
        conn.invalidate();
        expect(c.created, isNull);
        expect(c.current, isFalse);
        c.dispose();
        conn.dispose();
        parent.dispose();
      });
    },
  );
  test('stale UI revision does not issue a new mutation', () async {
    final w = PlanWire();
    await w.run(() async {
      await w.login();
      final c = PlanController('plan-1');
      await c.refresh();
      w.plan = {...w.plan, 'revision': 2};
      expect(await c.mutate('acknowledge', {'consent': true}, 1), isFalse);
      expect(w.sends, isEmpty);
      expect(c.value!.revision, 2);
      c.dispose();
    });
  });
  for (final action in ['hide', 'logout', 'switch']) {
    test(
      'late plan response after $action cannot restore private state',
      () async {
        final w = PlanWire();
        await w.run(() async {
          await w.login();
          final c = PlanController('plan-1');
          await c.refresh();
          w.delayed = Completer();
          final future = c.mutate('acknowledge', {'consent': true}, 1);
          await Future<void>.delayed(Duration.zero);
          if (action == 'hide') {
            c.hide();
          } else if (action == 'logout') {
            await api.logout();
          } else {
            w.owner = 'patient-2';
            await w.login();
          }
          w.delayed!.complete(
            f.json({
              ...w.plan,
              'revision': 2,
              'state': 'scheduled',
              'acknowledged_at': '2026-10-18T12:00:00Z',
            }),
          );
          expect(await future, isFalse);
          expect(c.value, isNull);
          expect(c.history, isEmpty);
          c.dispose();
        });
      },
    );
  }
  test('revoked doctor grant hides data on refresh', () async {
    final w = PlanWire(doctor: true);
    await w.run(() async {
      await w.login();
      final c = PlanController('plan-1');
      await c.refresh();
      w.revoked = true;
      await c.refresh();
      expect(c.value, isNull);
      expect(c.history, isEmpty);
      expect(c.error, isNotNull);
      c.dispose();
    });
  });
  test('invalid wall dates and unsupported authority fail closed', () {
    expect(
      validateWallSchedule('2027-02-30T10:00', 'Africa/Cairo', 0),
      isNotNull,
    );
    expect(
      validateWallSchedule('2027-01-12T10:00Z', 'Africa/Cairo', 0),
      isNotNull,
    );
    expect(
      validateWallSchedule('2027-01-12T10:00', 'Africa/Cairo', null),
      isNull,
    );
    final w = PlanWire();
    expect(
      () => ClinicalPlan.fromApi(
        {...w.plan, 'clinical_clearance': true},
        w.owner,
        w.role,
      ),
      throwsFormatException,
    );
    expect(
      () => ClinicalPlan.fromApi(
        {...w.plan, 'patient_id': 'foreign'},
        w.owner,
        w.role,
      ),
      throwsFormatException,
    );
  });
  for (final dark in [false, true]) {
    testWidgets('plan screen 320px 200% text dark=$dark', (tester) async {
      final w = PlanWire();
      await w.run(() async {
        await w.login();
        tester.view.physicalSize = const Size(320, 960);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const ClinicalPlanScreen(id: 'plan-1'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Plan details'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await api.logout();
      });
    });
  }
}
