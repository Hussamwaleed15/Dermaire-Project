import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/plans/plan_models.dart';
import 'package:dermaire_app/plans/plan_evaluation.dart';
import 'package:dermaire_app/plans/plan_controller.dart';
import 'package:dermaire_app/plans/plan_images.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/capture/guided_camera_screen.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_plans_test.dart' as p;
import 'm6_doctor_fixture.dart' as f;
import 'guided_capture_test.dart' as g;
import 'observation_test.dart' as o;
import 'm6_clinical_records_test.dart' as records;

class ComparisonWire extends p.PlanWire {
  ComparisonWire({super.doctor}) {
    plan = {
      ...plan,
      'kind': 'comparison',
      'state': 'scheduled',
      'revision': 2,
      'baseline_capture_id': 'baseline-1',
      'acknowledged_at': '2026-10-18T12:00:00Z',
      'source_snapshot': {'source_type': 'routine', 'source_id': 'routine-1'},
    };
  }
  Map<String, dynamic>? job;
  bool revokeDuringImage = false;
  int imageReads = 0;
  Completer<http.Response>? imageDelay;
  Map<String, dynamic> evaluation({
    String state = 'queued',
    int revision = 4,
  }) => {
    'schema_version': 'comparison-job-1',
    'id': 'job-1',
    'state': state,
    'plan_revision': revision,
    'updated_at': '2026-10-18T13:00:00Z',
    'input': {
      'schema_version': 'comparison-input-1',
      'plan_id': 'plan-1',
      'plan_revision': 3,
      'baseline_capture_id': 'baseline-1',
      'followup_capture_id': 'followup-1',
      'consent_revision': 3,
    },
    'attempts': 0,
    'lease_token': null,
    'lease_until': null,
    'inference': state == 'unavailable'
        ? {
            'schema_version': 'comparison-model-boundary-1',
            'status': 'unavailable',
            'reason': 'validated_model_not_integrated',
            'result': null,
            'clinical_clearance': false,
          }
        : null,
    'medical_resources_modified': false,
    'clinical_clearance': false,
  };
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    if (r.url.path.endsWith('/timeline')) {
      final page = records.EvidenceWire().page(0);
      page['items'] = [
        records.item(id: 'baseline-1'),
        records.item(
          source: 'routine',
          id: 'routine-1',
          category: 'patient_reported',
          data: {'product_id': 'product-1', 'schedule': 'AM', 'active': true},
        ),
      ];
      page['total'] = 2;
      return f.json(page);
    }
    if ((r.url.path.endsWith('/evaluation') ||
            r.url.path.endsWith('/evaluation/review')) &&
        r.method != 'GET') {
      sends.add(r);
      if (revoked) return f.json({}, 403);
      if (delayed != null) return delayed!.future;
      if (int.tryParse(mode) != null) return f.json({}, int.parse(mode));
      if (mode == 'lost before') throw TimeoutException('synthetic');
      final body = r.method == 'DELETE'
          ? {
              'expected_revision': int.parse(
                r.url.queryParameters['expected_revision']!,
              ),
            }
          : jsonDecode(r.body) as Map;
      final key = r.headers['Idempotency-Key'];
      if (key != null && receipts.containsKey(key)) {
        return f.json(receipts[key], 202);
      }
      if (body['expected_revision'] != plan['revision']) return f.json({}, 409);
      final revision = (plan['revision'] as int) + 1;
      final review = r.url.path.endsWith('/review');
      final result = r.method == 'DELETE'
          ? {
              ...job!,
              'state': 'cancelled',
              'plan_revision': revision,
              'inference': null,
            }
          : review
          ? {
              ...job!,
              'state': body['decision'],
              'plan_revision': revision,
              'human_review': {
                'decision': body['decision'],
                'assessment': body['assessment'],
                'actor_id': owner,
                'job_id': job!['id'],
                'model_version': (job!['inference'] as Map)['model_version'],
                'artifact_sha256':
                    (job!['inference'] as Map)['artifact_sha256'],
                'reviewed_at': '2026-10-18T13:00:00Z',
                'provenance': 'clinician_authored',
                'clinical_accuracy_validated': false,
                'clinical_clearance': false,
              },
            }
          : evaluation(revision: revision);
      job = Map<String, dynamic>.from(result);
      plan = {...plan, 'revision': revision};
      if (key != null) receipts[key] = Map.from(job!);
      events.add({
        'revision': revision,
        'operation': 'evaluation',
        'actor_id': owner,
        'recorded_at': '2026-10-18T13:00:00Z',
        'snapshot': Map.from(job!),
      });
      if (mode == 'lost after') throw TimeoutException('synthetic');
      return f.json(job, r.method == 'POST' && !review ? 202 : 200);
    }
    if (r.url.path.endsWith('/evaluation') && r.method == 'GET') {
      return revoked
          ? f.json({}, 403)
          : f.json(job ?? {'state': 'not_requested', 'inference': null});
    }
    if (r.url.path.endsWith('/image')) {
      imageReads++;
      if (revokeDuringImage) revoked = true;
      return imageDelay?.future ??
          http.Response.bytes(
            g.pngBytes(),
            200,
            headers: {'content-type': 'image/png'},
          );
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
  for (final loss in ['success', 'lost before', 'lost after']) {
    test(
      'evaluation $loss preserves consent/key and reads current job',
      () async {
        final w = ComparisonWire();
        w.plan = {
          ...w.plan,
          'state': 'captured',
          'revision': 3,
          'followup_capture_id': 'followup-1',
        };
        await w.run(() async {
          await w.login();
          final c = PlanController('plan-1');
          await c.refresh();
          expect(
            await c.mutate('evaluation', {
              'image_processing_consent': false,
            }, 3),
            isFalse,
          );
          w.mode = loss;
          final result = await c.mutate('evaluation', {
            'image_processing_consent': true,
          }, 3);
          if (loss == 'success') {
            expect(result, isTrue);
          } else {
            expect(result, isFalse);
            final intent = c.pending!;
            w.mode = 'success';
            expect(await c.reconcile(retryOriginal: true), isTrue);
            expect(
              w.sends.every((r) => r.headers['Idempotency-Key'] == intent.key),
              isTrue,
            );
          }
          expect(c.value!.revision, 4);
          expect(c.evaluation!.state, 'queued');
          expect(c.outcome, contains('not a completed clinical analysis'));
          expect(w.events.length, 1);
          await c.cancelEvaluation();
          expect(c.value!.revision, 5);
          expect(c.evaluation!.state, 'cancelled');
          c.dispose();
        });
      },
    );
  }
  test(
    'doctor inference review is bound to exact artifact/job and not plan review',
    () async {
      final w = ComparisonWire(doctor: true);
      w.plan = {
        ...w.plan,
        'state': 'captured',
        'revision': 4,
        'followup_capture_id': 'followup-1',
      };
      w.job = {
        ...w.evaluation(state: 'pending_human_review'),
        'inference': {
          'schema_version': 'comparison-model-boundary-1',
          'status': 'pending_human_review',
          'model_version': 'synthetic-test-only',
          'artifact_sha256': 'a' * 64,
          'clinical_clearance': false,
          'result': {
            'schema_version': 'comparison-evidence-1',
            'baseline_capture_id': 'baseline-1',
            'followup_capture_id': 'followup-1',
            'provenance': 'nonclinical_image_quality_only',
            'quality_flags': ['lighting_mismatch'],
          },
        },
      };
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        expect(
          await c.mutate('evaluation/review', {
            'job_id': 'foreign',
            'decision': 'reviewed',
            'assessment': 'Synthetic review only',
          }, 4),
          isFalse,
        );
        expect(w.sends, isEmpty);
        expect(
          await c.mutate('evaluation/review', {
            'job_id': 'job-1',
            'decision': 'reviewed',
            'assessment': 'Synthetic review only',
          }, 4),
          isTrue,
        );
        expect(c.value!.state, 'captured');
        expect(c.evaluation!.state, 'reviewed');
        expect(c.evaluation!.wire['clinical_clearance'], false);
        c.dispose();
      });
    },
  );
  test(
    'evaluation status exposes original-authority cancellation without reactivating plan',
    () async {
      final w = ComparisonWire();
      w.plan = {
        ...w.plan,
        'state': 'captured',
        'revision': 4,
        'followup_capture_id': 'followup-1',
      };
      w.job = {
        ...w.evaluation(),
        'effective_state': 'cancelled',
        'reason': 'original_authority_revoked',
      };
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        expect(c.evaluation!.currentState, 'cancelled');
        expect(c.evaluation!.state, 'queued');
        c.dispose();
      });
    },
  );
  for (final doctor in [false, true]) {
    test(
      'original plan authorizes private images before and after bytes doctor=$doctor',
      () async {
        final w = ComparisonWire(doctor: doctor);
        await w.run(() async {
          await w.login();
          final c = PlanController('plan-1');
          await c.refresh();
          final images = PlanImages(c, c.value!);
          final bytes = await images.read('baseline-1', c.generation);
          expect(bytes.mime, 'image/png');
          expect(w.imageReads, 1);
          final reads = w.requests.where((r) => r.url.path.endsWith('/plan-1'));
          expect(reads.length, 3);
          images.dispose();
          c.dispose();
        });
      },
    );
  }
  test('image access refuses unrelated arbitrary pairs without HTTP', () async {
    final w = ComparisonWire();
    await w.run(() async {
      await w.login();
      final c = PlanController('plan-1');
      await c.refresh();
      final images = PlanImages(c, c.value!);
      await expectLater(
        images.read('foreign', c.generation),
        throwsFormatException,
      );
      expect(w.imageReads, 0);
      expect(c.value, isNull);
      images.dispose();
      c.dispose();
    });
  });
  test(
    'original grant revoked after bytes arrive prevents display and clears plan',
    () async {
      final w = ComparisonWire(doctor: true);
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        final images = PlanImages(c, c.value!);
        w.revokeDuringImage = true;
        await expectLater(
          images.read('baseline-1', c.generation),
          throwsA(anything),
        );
        expect(images.active, isFalse);
        expect(c.value, isNull);
        expect(c.history, isEmpty);
        images.dispose();
        c.dispose();
      });
    },
  );
  for (final change in ['hide', 'switch', 'revision']) {
    test('late image after $change cannot restore prior scope', () async {
      final w = ComparisonWire();
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        final images = PlanImages(c, c.value!);
        w.imageDelay = Completer();
        final read = images.read('baseline-1', c.generation);
        await Future<void>.delayed(Duration.zero);
        if (change == 'hide') {
          c.hide();
        } else if (change == 'switch') {
          w.owner = 'patient-2';
          await w.login();
        } else {
          w.plan = {...w.plan, 'revision': 3};
        }
        final denied = expectLater(read, throwsA(anything));
        w.imageDelay!.complete(
          http.Response.bytes(
            g.pngBytes(),
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await denied;
        expect(images.active, isFalse);
        images.dispose();
        c.dispose();
      });
    });
  }
  test(
    'capture attaches once with original revision and survives lost receipt',
    () async {
      final w = ComparisonWire();
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        w.mode = 'lost after';
        expect(
          await c.mutate('capture', {'capture_id': 'followup-1'}, 2),
          isFalse,
        );
        expect(c.pending, isNotNull);
        w.mode = 'success';
        expect(await c.reconcile(), isTrue);
        expect(c.value!.state, 'captured');
        expect(c.value!.followup, 'followup-1');
        expect(w.sends.length, 1);
        c.dispose();
      });
    },
  );
  test('real comparison creation binds selected source and baseline', () async {
    final w = ComparisonWire(doctor: true);
    w.plan = {
      ...w.plan,
      'state': 'proposed',
      'revision': 1,
      'acknowledged_at': null,
    };
    await w.run(() async {
      await w.login();
      final parent = DoctorWorkspaceController(
        AccessSession(userId: w.owner, role: UserRole.doctor),
      );
      await parent.refresh();
      final conn = DoctorConnectionController(parent, w.patient);
      await conn.refresh();
      final c = CreatePlanController(conn);
      expect(
        await c.create({
          'kind': 'comparison',
          'purpose': 'Compare tolerance after routine change',
          'source_type': 'routine',
          'source_id': 'routine-1',
          'baseline_capture_id': 'baseline-1',
          'local_due': '2027-01-12T10:00',
          'timezone': 'Africa/Cairo',
          'fold': 0,
        }),
        isTrue,
      );
      expect(c.created!.baseline, 'baseline-1');
      expect(c.created!.source['source_id'], 'routine-1');
      c.dispose();
      conn.dispose();
      parent.dispose();
    });
  });
  test(
    'mixed plan/evaluation events retain typed history and current job',
    () async {
      final w = ComparisonWire();
      w.plan = {
        ...w.plan,
        'state': 'captured',
        'revision': 4,
        'followup_capture_id': 'followup-1',
      };
      w.job = w.evaluation();
      w.events.add({
        'revision': 4,
        'operation': 'evaluation',
        'actor_id': 'patient-1',
        'recorded_at': '2026-10-18T13:00:00Z',
        'snapshot': w.job,
      });
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        expect(c.error, isNull);
        expect(c.value!.revision, 4);
        expect(c.history.single.snapshot, isNull);
        expect(c.history.single.evaluation!.state, 'queued');
        expect(c.evaluation!.state, 'queued');
        c.dispose();
      });
    },
  );
  test(
    'unavailable evaluation and effective cancellation never contain a clinical result',
    () {
      final w = ComparisonWire();
      w.plan = {
        ...w.plan,
        'state': 'captured',
        'revision': 4,
        'followup_capture_id': 'followup-1',
      };
      final model = ClinicalPlan.fromApi(w.plan, w.owner, w.role);
      final job = w.evaluation(state: 'unavailable');
      expect(PlanEvaluation(job, model).state, 'unavailable');
      expect(
        PlanEvaluation({
          ...job,
          'effective_state': 'cancelled',
        }, model).currentState,
        'cancelled',
      );
      expect(
        () => PlanEvaluation({...job, 'clinical_clearance': true}, model),
        throwsFormatException,
      );
      expect(
        () => PlanEvaluation({
          ...job,
          'input': {...job['input'] as Map, 'baseline_capture_id': 'foreign'},
        }, model),
        throwsFormatException,
      );
      expect(
        () => PlanEvaluation({
          ...job,
          'inference': {
            'status': 'unavailable',
            'result': {'score': 99},
          },
        }, model),
        throwsFormatException,
      );
    },
  );
  for (final accepted in [false, true]) {
    testWidgets(
      'camera offers plan return only for accepted stored receipt accepted=$accepted',
      (tester) async {
        final fixture = g.Fixture()
          ..resultState = accepted ? 'accepted' : 'rejected';
        await http.runWithClient(() async {
          await fixture.login();
          await tester.pumpWidget(
            MaterialApp(
              home: GuidedCameraScreen(
                state: fixture.state,
                cameraPort: fixture.camera,
                prepare: (bytes) async => g.sample(),
                returnCapture: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Use this confirmed capture'), findsNothing);
          fixture.choose();
          await fixture.capture.upload(generation: api.sessionGeneration);
          await tester.pumpAndSettle();
          expect(
            find.text('Use this confirmed capture'),
            accepted ? findsOneWidget : findsNothing,
          );
          expect(tester.takeException(), isNull);
          await fixture.done(tester);
        }, () => o.isolated(fixture.transport));
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets(
      'comparison creation lists only real evidence at 320px 200% dark=$dark',
      (tester) async {
        final w = ComparisonWire(doctor: true);
        await w.run(() async {
          await w.login();
          final parent = DoctorWorkspaceController(
            AccessSession(userId: w.owner, role: UserRole.doctor),
          );
          await parent.refresh();
          final conn = DoctorConnectionController(parent, w.patient);
          await conn.refresh();
          tester.view.physicalSize = const Size(320, 1000);
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
              home: CreateClinicalPlanScreen(
                connection: conn,
                comparison: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Create comparison plan'), findsOneWidget);
          await tester.scrollUntilVisible(find.byKey(const Key('followupPurpose')), 250);
          await tester.pumpAndSettle();
          expect(find.text('Capture baseline-1'), findsOneWidget);
          expect(find.text('routine · routine-1'), findsOneWidget);
          expect(w.sends, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          conn.dispose();
          parent.dispose();
          await api.logout();
        });
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets('comparison images and lifecycle fit 320px 200% dark=$dark', (
      tester,
    ) async {
      final w = ComparisonWire();
      await w.run(() async {
        await w.login();
        tester.view.physicalSize = const Size(320, 1000);
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
