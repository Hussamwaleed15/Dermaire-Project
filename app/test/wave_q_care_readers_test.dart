import 'dart:convert';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/messaging/messaging_controller.dart';
import 'package:dermaire_app/plans/plan_controller.dart';
import 'package:dermaire_app/recovery/message_receipt_reader.dart';
import 'package:dermaire_app/recovery/plan_receipt_reader.dart';
import 'package:dermaire_app/recovery/operation_journal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/recovery/recovery_ui.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_messaging_test.dart' as message;
import 'wave_plans_test.dart' as plans;
import 'wave_comparison_test.dart' as comparison;
import 'wave_q_domain_readers_test.dart' show identity;
import 'm6_doctor_fixture.dart' as base;

class MessageWire extends message.MessageWire {
  MessageWire({super.doctor});
  String? replacementGrant;
  String? changedField;
  int? lookupStatus;
  @override
  Map<String, dynamic> get thread => {
    ...super.thread,
    if (replacementGrant != null) 'access_id': replacementGrant,
  };
  @override
  Future<http.Response> call(http.Request r) async {
    if (lookupStatus != null && r.url.path.contains('/attempts/')) {
      expectHost(r);
      return base.json({}, lookupStatus!);
    }
    final result = await super.call(r);
    if (changedField != null && r.url.path.contains('/attempts/')) {
      final raw = jsonDecode(result.body) as Map<String, dynamic>;
      return base.json({
        ...raw,
        'result': {...raw['result'] as Map, changedField!: 'other'},
      });
    }
    return result;
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
      'message receipt/current read is original grant bound doctor=$doctor',
      () async {
        final w = MessageWire(doctor: doctor);
        await w.run(() async {
          await w.login();
          final c = ConversationController(w.model);
          try {
            await c.refresh();
            w.mode = 'lost after';
            expect(
              await c.send('Synthetic original private participant content.'),
              false,
            );
            final i = identity(c.pending!, w.owner, w.role);
            final reader = MessageReceiptReader(api, api.sessionGeneration);
            final r = await reader.lookup(i);
            expect(r.outcome, ReceiptOutcome.committed);
            expect(await reader.verifyCurrent(i, r), true);
            expect(
              jsonEncode(i.toJson()),
              isNot(contains('Synthetic original private')),
            );
            w.replacementGrant = 'another-grant';
            await expectLater(
              reader.lookup(i),
              throwsA(isA<RecoveryPermissionLost>()),
            );
            await expectLater(
              reader.verifyCurrent(i, r),
              throwsA(isA<RecoveryPermissionLost>()),
            );
            expect(w.posts, 1);
          } finally {
            c.dispose();
          }
        });
      },
    );
    for (final status in ['unknown', 'expired', 'withdrawn', 'revoked']) {
      test(
        'message $status stays locked without send doctor=$doctor',
        () async {
          final w = MessageWire(doctor: doctor);
          await w.run(() async {
            await w.login();
            final c = ConversationController(w.model);
            try {
              await c.refresh();
              w.mode = status == 'unknown' ? 'lost before' : 'lost after';
              await c.send('Synthetic private participant content.');
              final i = identity(c.pending!, w.owner, w.role);
              final reader = MessageReceiptReader(api, api.sessionGeneration);
              if (status == 'expired') w.mode = 'expired';
              if (status == 'withdrawn') w.closed = true;
              if (status == 'revoked') w.mode = 'revoked';
              if (['withdrawn', 'revoked'].contains(status)) {
                await expectLater(
                  reader.lookup(i),
                  throwsA(isA<RecoveryPermissionLost>()),
                );
              } else {
                final r = await reader.lookup(i);
                expect(
                  r.outcome,
                  status == 'unknown'
                      ? ReceiptOutcome.unknown
                      : ReceiptOutcome.expired,
                );
                expect(await reader.verifyCurrent(i, r), false);
              }
              expect(w.posts, 1);
              expect(c.pending!.key, i.key);
            } finally {
              c.dispose();
            }
          });
        },
      );
    }
  }
  for (final field in ['actor_id', 'thread_id', 'id']) {
    test(
      'message wrong original $field rejected before current success',
      () async {
        final w = MessageWire();
        await w.run(() async {
          await w.login();
          final c = ConversationController(w.model);
          try {
            await c.refresh();
            w.mode = 'lost after';
            await c.send('Synthetic original private message.');
            final i = identity(c.pending!, w.owner, w.role);
            w.changedField = field;
            await expectLater(
              MessageReceiptReader(api, api.sessionGeneration).lookup(i),
              throwsFormatException,
            );
            expect(w.posts, 1);
          } finally {
            c.dispose();
          }
        });
      },
    );
  }
  for (final operation in ['acknowledge', 'cancel', 'reschedule', 'review']) {
    test(
      'plan $operation original and current revisions remain separate',
      () async {
        final doctor = ['reschedule', 'review'].contains(operation);
        final w = plans.PlanWire(doctor: doctor);
        if (operation == 'review') {
          w.plan = {
            ...w.plan,
            'state': 'scheduled',
            'acknowledged_at': '2026-10-18T12:00:00Z',
          };
        }
        await w.run(() async {
          await w.login();
          final c = PlanController('plan-1');
          try {
            await c.refresh();
            w.mode = 'lost after';
            final fields = switch (operation) {
              'acknowledge' => <String, dynamic>{'consent': true},
              'cancel' => <String, dynamic>{
                'reason': 'Explicit synthetic participation withdrawal',
              },
              'reschedule' => <String, dynamic>{
                'local_due': '2027-01-12T10:00',
                'timezone': 'Africa/Cairo',
                'fold': 0,
              },
              _ => <String, dynamic>{
                'assessment':
                    'Explicit synthetic clinician follow-up assessment',
              },
            };
            expect(await c.mutate(operation, fields, c.value!.revision), false);
            final i = identity(c.pending!, w.owner, w.role);
            final reader = PlanReceiptReader(api, api.sessionGeneration);
            final r = await reader.lookup(i);
            expect(r.outcome, ReceiptOutcome.committed);
            expect(await reader.verifyCurrent(i, r), true);
            w.plan = {...w.plan, 'revision': 9, 'state': 'cancelled'};
            expect(await reader.verifyCurrent(i, r), false);
            w.revoked = true;
            await expectLater(
              reader.lookup(i),
              throwsA(isA<RecoveryPermissionLost>()),
            );
            expect(w.sends.length, 1);
          } finally {
            c.dispose();
          }
        });
      },
    );
  }
  test(
    'plan creation recovery is patient/doctor/original access bound',
    () async {
      final w = plans.PlanWire(doctor: true);
      await w.run(() async {
        await w.login();
        final parent = DoctorWorkspaceController(
          AccessSession(userId: w.owner, role: UserRole.doctor),
        );
        await parent.refresh();
        final connection = DoctorConnectionController(parent, w.patient);
        await connection.refresh();
        final c = CreatePlanController(connection);
        try {
          w.mode = 'lost after';
          expect(
            await c.create({
              'kind': 'follow_up',
              'purpose': 'Synthetic clinician-created follow-up plan',
              'local_due': '2027-01-12T10:00',
              'timezone': 'Africa/Cairo',
              'fold': 0,
            }),
            false,
          );
          final i = identity(c.pending!, w.owner, w.role);
          expect(i.scope['patient_id'], 'patient-1');
          final reader = PlanReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.resource, 'plan-1');
          expect(await reader.verifyCurrent(i, r), true);
          w.plan = {...w.plan, 'access_id': 'another-grant'};
          await expectLater(
            reader.verifyCurrent(i, r),
            throwsA(isA<RecoveryPermissionLost>()),
          );
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
          connection.dispose();
          parent.dispose();
        }
      });
    },
  );
  test(
    'comparison capture receipt is actual attached plan history, no arbitrary pair',
    () async {
      final w = comparison.ComparisonWire();
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        try {
          await c.refresh();
          w.mode = 'lost after';
          expect(
            await c.mutate('capture', {'capture_id': 'followup-1'}, 2),
            false,
          );
          final i = identity(c.pending!, w.owner, w.role);
          final reader = PlanReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(await reader.verifyCurrent(i, r), true);
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
        }
      });
    },
  );
  test(
    'comparison evaluation original job is separate from canceled or replaced current job',
    () async {
      final w = comparison.ComparisonWire();
      w.plan = {
        ...w.plan,
        'state': 'captured',
        'revision': 3,
        'followup_capture_id': 'followup-1',
      };
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        try {
          await c.refresh();
          w.mode = 'lost after';
          expect(
            await c.mutate('evaluation', {'image_processing_consent': true}, 3),
            false,
          );
          final i = identity(c.pending!, w.owner, w.role);
          final reader = PlanReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.resource, 'job-1');
          expect(await reader.verifyCurrent(i, r), true);
          w.job = {...w.job!, 'state': 'cancelled'};
          expect(await reader.verifyCurrent(i, r), false);
          w.job = {...w.job!, 'id': 'replacement-job', 'state': 'queued'};
          expect(await reader.verifyCurrent(i, r), false);
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
        }
      });
    },
  );
  for (final state in ['unknown', 'expired', 'wrong grant']) {
    test('plan $state receipt cannot confirm replacement', () async {
      final w = plans.PlanWire();
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        try {
          await c.refresh();
          w.mode = 'lost after';
          await c.mutate('acknowledge', {'consent': true}, 1);
          final i = identity(c.pending!, w.owner, w.role);
          if (state == 'unknown') w.receipts.clear();
          if (state == 'expired') w.mode = 'expired';
          if (state == 'wrong grant') {
            w.plan = {...w.plan, 'access_id': 'another-grant'};
          }
          final reader = PlanReceiptReader(api, api.sessionGeneration);
          if (state == 'wrong grant') {
            await expectLater(
              reader.lookup(i),
              throwsA(isA<RecoveryPermissionLost>()),
            );
          } else {
            final r = await reader.lookup(i);
            expect(
              r.outcome,
              state == 'unknown'
                  ? ReceiptOutcome.unknown
                  : ReceiptOutcome.expired,
            );
            expect(await reader.verifyCurrent(i, r), false);
          }
          expect(c.pending!.key, i.key);
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
        }
      });
    });
  }
  test(
    'comparison clinician inference review stays tied to original job and artifact',
    () async {
      final w = comparison.ComparisonWire(doctor: true);
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
        try {
          await c.refresh();
          w.mode = 'lost after';
          expect(
            await c.mutate('evaluation/review', {
              'job_id': 'job-1',
              'decision': 'reviewed',
              'assessment':
                  'Synthetic clinician reviewed image-quality evidence only.',
            }, 4),
            false,
          );
          final i = identity(c.pending!, w.owner, w.role);
          final reader = PlanReceiptReader(api, api.sessionGeneration);
          final r = await reader.lookup(i);
          expect(r.resource, 'job-1');
          expect(await reader.verifyCurrent(i, r), true);
          w.job = {
            ...w.job!,
            'id': 'another-job',
            'human_review': {
              ...w.job!['human_review'] as Map,
              'job_id': 'another-job',
            },
          };
          expect(await reader.verifyCurrent(i, r), false);
          expect(w.sends.length, 1);
        } finally {
          c.dispose();
        }
      });
    },
  );
  for (final doctor in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets(
        'retained original message verification doctor=$doctor dark=$dark at320px200%',
        (t) async {
          t.view.physicalSize = const Size(320, 1500);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final w = MessageWire(doctor: doctor);
          await w.run(() async {
            await w.login();
            final c = ConversationController(w.model);
            try {
              await c.refresh();
              w.mode = 'lost after';
              await c.send(
                'Synthetic message remains private during recovery.',
              );
              final key = c.pending!.key;
              w.lookupStatus = 401;
              await c.reconcile();
              expect(api.isAuthenticated, false);
              w.lookupStatus = null;
              await w.login();
              expect(api.quarantinedOperations.single.key, key);
              await t.pumpWidget(
                MaterialApp(
                  theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                  builder: (ctx, child) => MediaQuery(
                    data: MediaQuery.of(ctx).copyWith(
                      textScaler: const TextScaler.linear(2),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                  home: const RecoveryReviewScreen(),
                ),
              );
              await t.pumpAndSettle();
              final button = find.text('Check original message receipt');
              await t.scrollUntilVisible(button, 200);
              await t.ensureVisible(button);
              await t.pumpAndSettle();
              await t.tap(button);
              await t.pumpAndSettle();
              expect(
                find.textContaining('current message verified separately'),
                findsOneWidget,
              );
              expect(
                find.text('Synthetic message remains private during recovery.'),
                findsNothing,
              );
              expect(w.posts, 1);
              expect(api.quarantinedOperations.single.key, key);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox.shrink());
            } finally {
              c.dispose();
              await api.init();
            }
          });
        },
      );
    }
  }
}
