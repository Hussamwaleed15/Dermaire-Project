import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:dermaire_app/comparison/comparison_domain.dart';
import 'package:dermaire_app/comparison/comparison_repository.dart';
import 'package:dermaire_app/comparison/comparison_controller.dart';
import 'package:dermaire_app/comparison/comparison_ui.dart';
import 'package:dermaire_app/capture/guided_capture_models.dart';
import 'package:dermaire_app/capture/private_capture_image.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/capture/guided_camera_screen.dart';
import 'package:dermaire_app/entry/entry_motion.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'guided_capture_test.dart' as g;
import 'observation_test.dart' as o;
import 'private_capture_history_test.dart' as h;

final api = ApiService.instance;
final instant = DateTime.utc(2026, 10, 13, 12);
GuidedCaptureRecord capture({
  String owner = 'a',
  String id = 'baseline',
  bool stored = true,
  String state = 'accepted',
}) => GuidedCaptureRecord.fromApi(
  g.receipt(owner: owner, id: id, inline: false, stored: stored, state: state),
  owner: owner,
  readback: true,
);
PlanCaptureAssociation link({
  String owner = 'a',
  String plan = 'plan',
  int revision = 1,
  CaptureRole role = CaptureRole.baseline,
  String? id,
  bool metadata = true,
  String state = 'accepted',
  bool stored = true,
}) => PlanCaptureAssociation(
  planId: plan,
  planRevision: revision,
  owner: owner,
  role: role,
  captureId: id ?? role.name,
  relationshipRecordId: 'link-${role.name}',
  metadata: metadata
      ? capture(owner: owner, id: id ?? role.name, stored: stored, state: state)
      : null,
);
ComparisonPlan plan({
  String owner = 'a',
  String id = 'plan',
  int revision = 1,
  ComparisonLifecycle lifecycle = ComparisonLifecycle.scheduled,
  SchedulingSource source = SchedulingSource.doctorDirected,
  bool resolved = true,
  bool baseline = true,
  bool followUp = false,
  bool metadata = true,
  PatientConfirmation confirmation = PatientConfirmation.confirmed,
  DateTime? date,
  bool noDate = false,
  bool? due,
  String? zone = 'Europe/Paris',
  InterventionReference? intervention,
  List<SchedulingDecision>? decisions,
  String? resolutionId,
}) => ComparisonPlan(
  id: id,
  owner: owner,
  revision: revision,
  recordedAt: instant,
  lifecycle: lifecycle,
  decisions:
      decisions ??
      [
        SchedulingDecision(
          recordId: 'decision',
          source: source,
          recordedAt: instant,
        ),
      ],
  resolvedDecisionId: resolved ? (resolutionId ?? 'decision') : null,
  schedule: FollowUpSchedule(
    instantUtc: noDate ? null : date ?? DateTime.utc(2026, 11, 4, 9),
    reportedTimezone: zone,
    serverDue: due,
  ),
  confirmation: confirmation,
  intervention: intervention,
  baseline: baseline
      ? link(owner: owner, plan: id, revision: revision, metadata: metadata)
      : null,
  followUp: followUp
      ? link(
          owner: owner,
          plan: id,
          revision: revision,
          role: CaptureRole.followUp,
          metadata: metadata,
        )
      : null,
);
ComparisonAssessment assessment({
  String owner = 'a',
  String planId = 'plan',
  int planRevision = 1,
  int revision = 1,
  AssessmentStatus status = AssessmentStatus.available,
  AssessmentSource source = AssessmentSource.aiObservation,
  bool baseline = true,
  bool followUp = true,
  AssessmentReview review = AssessmentReview.pending,
}) => ComparisonAssessment(
  id: 'assessment',
  owner: owner,
  planId: planId,
  planRevision: planRevision,
  revision: revision,
  status: status,
  source: source,
  sourceVersion: 'synthetic-source-v1',
  generatedAt: status == AssessmentStatus.available ? instant : null,
  baselineCaptureId: baseline ? 'baseline' : null,
  followUpCaptureId: followUp ? 'followUp' : null,
  review: review,
  reviewRecordId: review == AssessmentReview.recorded ? 'review-record' : null,
  observations: status == AssessmentStatus.available
      ? ['Synthetic source observation.']
      : [],
  evidenceRecords: ['synthetic-evidence'],
  limitations: ['Synthetic evidence limitation.'],
  uncertainties: ['Synthetic uncertainty.'],
);
ComparisonSnapshot snapshot({
  ComparisonPlan? value,
  ComparisonAssessment? result,
  ComparisonFreshness freshness = ComparisonFreshness.fresh,
}) => ComparisonSnapshot(
  plan: value ?? plan(),
  observedAt: instant,
  freshness: freshness,
  assessment: result,
);

class FakeComparisonRepository implements ComparisonRepository {
  ComparisonSnapshot? value;
  Object? failure;
  int reads = 0;
  final contexts = <ComparisonReadContext>[];
  Future<ComparisonSnapshot?> Function()? pending;
  @override
  Future<List<ComparisonPlan>> readPlans(ComparisonReadContext context) async =>
      value == null ? [] : [value!.plan];
  @override
  Future<ComparisonSnapshot?> readPlan(
    String id,
    ComparisonReadContext context,
  ) async {
    reads++;
    contexts.add(context);
    if (failure != null) throw failure!;
    return pending != null ? pending!() : value;
  }
}

Future<void> mount(
  WidgetTester t,
  h.Fixture f,
  ComparisonController controller, {
  bool dark = false,
  bool reduced = false,
  double scale = 1,
  double width = 390,
  bool images = false,
}) => h.mount(
  t,
  f,
  Scaffold(
    body: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ComparisonPanel(controller: controller),
          if (images)
            PlanReferenceImages(controller: controller, images: f.images),
        ],
      ),
    ),
  ),
  dark: dark,
  reduced: reduced,
  scale: scale,
  width: width,
);

Future<void> settlePair(WidgetTester t) async {
  // Serial codec completions are engine futures; drain them before advancing
  // fake timers, rather than letting pumpAndSettle simulate the 20s timeout.
  for (var i = 0; i < 5; i++) {
    await t.pump();
    await t.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
  }
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() async {
    await api.init();
  });
  for (final source in SchedulingSource.values) {
    test(
      'proposed scheduling source $source is kept distinct with persisted record reference',
      () {
        final p = plan(source: source);
        expect(p.resolvedDecision!.source, source);
        expect(p.decisions.single.recordId, 'decision');
        expect(p.decisions.single.recordedAt.isUtc, true);
        expect(() => p.decisions.clear(), throwsUnsupportedError);
      },
    );
  }
  test(
    'doctor/AI/patient decisions and unresolved conflicts remain separate',
    () {
      final decisions = [
        for (final source in [
          SchedulingSource.doctorDirected,
          SchedulingSource.aiProposed,
          SchedulingSource.patientConfirmed,
        ])
          SchedulingDecision(
            recordId: source.name,
            source: source,
            recordedAt: instant,
          ),
      ];
      final unresolved = plan(decisions: decisions, resolved: false);
      expect(unresolved.resolvedDecision, isNull);
      expect(unresolved.decisions.length, 3);
      final resolved = plan(
        decisions: decisions,
        resolutionId: 'doctorDirected',
      );
      expect(
        resolved.resolvedDecision!.source,
        SchedulingSource.doctorDirected,
      );
      expect(resolved.decisions[1].source, SchedulingSource.aiProposed);
    },
  );
  for (final state in ComparisonLifecycle.values) {
    test(
      'proposed lifecycle $state can be represented without advancing locally',
      () {
        final p = plan(lifecycle: state);
        expect(p.lifecycle, state);
        expect(p.lifecycle.label, isNotEmpty);
        if ([
          ComparisonLifecycle.cancelled,
          ComparisonLifecycle.expired,
          ComparisonLifecycle.superseded,
          ComparisonLifecycle.unknown,
        ].contains(state)) {
          expect(p.active, false);
        }
      },
    );
  }
  for (final kind in InterventionKind.values) {
    test(
      'explicit intervention relationship $kind is separate from routine completion',
      () {
        final p = plan(
          intervention: InterventionReference(
            kind: kind,
            recordId: 'intervention',
            relationshipRecordId: 'explicit-link',
          ),
        );
        expect(p.intervention!.recordId, 'intervention');
        expect(p.lifecycle, ComparisonLifecycle.scheduled);
        expect(p.schedule!.serverDue, isNull);
      },
    );
  }
  test('a past date does not invent a clinically due state', () {
    final p = plan(date: DateTime.utc(2000), due: false);
    expect(p.schedule!.serverDue, false);
    expect(p.lifecycle, ComparisonLifecycle.scheduled);
    final unknown = plan(date: DateTime.utc(2000));
    expect(unknown.schedule!.serverDue, isNull);
    final future = plan(date: DateTime.utc(2099), due: true);
    expect(future.schedule!.serverDue, true);
  });
  test(
    'UTC conversion is explicit and original scheduling timezone remains a reported label',
    () {
      final date = DateTime.parse('2026-11-01T01:30:00-04:00');
      expect(date.isUtc, true);
      final p = plan(date: date, zone: 'America/New_York');
      expect(p.schedule!.instantUtc, DateTime.utc(2026, 11, 1, 5, 30));
      expect(p.schedule!.reportedTimezone, 'America/New_York');
      expect(
        () => FollowUpSchedule(instantUtc: DateTime(2026, 11, 1, 1, 30)),
        throwsFormatException,
      );
    },
  );
  test(
    'missing date, timezone, references and decision resolution stay missing',
    () {
      final p = plan(
        noDate: true,
        zone: null,
        baseline: false,
        followUp: false,
        resolved: false,
      );
      expect(p.schedule!.instantUtc, isNull);
      expect(p.schedule!.reportedTimezone, isNull);
      expect(p.baseline, isNull);
      expect(p.followUp, isNull);
      expect(p.resolvedDecision, isNull);
    },
  );
  for (final fault in [
    'wrong owner',
    'wrong plan',
    'wrong revision',
    'wrong role',
    'same pair',
    'missing proof',
    'invalid ID',
    'unmatched resolution',
    'duplicate decisions',
  ]) {
    test(
      'reject $fault relationship evidence without guessing from history',
      () {
        expect(() {
          final baseline = link(
            owner: fault == 'wrong owner' ? 'b' : 'a',
            plan: fault == 'wrong plan' ? 'other' : 'plan',
            revision: fault == 'wrong revision' ? 2 : 1,
            role: fault == 'wrong role'
                ? CaptureRole.followUp
                : CaptureRole.baseline,
            id: fault == 'invalid ID' ? '../image?token=x' : null,
          );
          return ComparisonPlan(
            id: 'plan',
            owner: 'a',
            revision: 1,
            recordedAt: instant,
            lifecycle: ComparisonLifecycle.scheduled,
            decisions: fault == 'duplicate decisions'
                ? [
                    SchedulingDecision(
                      recordId: 'same',
                      source: SchedulingSource.doctorDirected,
                      recordedAt: instant,
                    ),
                    SchedulingDecision(
                      recordId: 'same',
                      source: SchedulingSource.aiProposed,
                      recordedAt: instant,
                    ),
                  ]
                : [],
            resolvedDecisionId: fault == 'unmatched resolution'
                ? 'not-recorded'
                : null,
            baseline: fault == 'missing proof'
                ? PlanCaptureAssociation(
                    planId: 'plan',
                    planRevision: 1,
                    owner: 'a',
                    role: CaptureRole.baseline,
                    captureId: 'baseline',
                    relationshipRecordId: '',
                  )
                : baseline,
            followUp: fault == 'same pair'
                ? link(role: CaptureRole.followUp, id: baseline.captureId)
                : null,
          );
        }, throwsFormatException);
      },
    );
  }
  test(
    'capture association requires matching owned metadata, not same time or filename',
    () {
      expect(
        () => PlanCaptureAssociation(
          planId: 'plan',
          planRevision: 1,
          owner: 'a',
          role: CaptureRole.baseline,
          captureId: 'baseline',
          relationshipRecordId: 'proof',
          metadata: capture(owner: 'b'),
        ),
        throwsFormatException,
      );
      expect(
        () => PlanCaptureAssociation(
          planId: 'plan',
          planRevision: 1,
          owner: 'a',
          role: CaptureRole.baseline,
          captureId: 'another',
          relationshipRecordId: 'proof',
          metadata: capture(),
        ),
        throwsFormatException,
      );
      final missing = plan(baseline: false, followUp: false);
      capture(id: 'oldest');
      capture(id: 'newest');
      expect(missing.baseline, isNull);
      expect(missing.followUp, isNull);
    },
  );
  for (final status in AssessmentStatus.values) {
    test(
      'future assessment $status carries explicit status without fake medical scores',
      () {
        final result = assessment(status: status);
        final s = snapshot(value: plan(followUp: true), result: result);
        expect(s.assessment!.status, status);
        if (status != AssessmentStatus.available) {
          expect(result.observations, isEmpty);
        }
        expect(
          () => result.observations.add('injected'),
          throwsUnsupportedError,
        );
        expect(() => result.limitations.clear(), throwsUnsupportedError);
      },
    );
  }
  for (final fault in [
    'owner',
    'plan',
    'revision',
    'baseline',
    'followup',
    'missing baseline',
    'missing followup',
  ]) {
    test('available assessment refuses mismatched $fault evidence', () {
      expect(
        () => snapshot(
          value: plan(
            followUp: fault != 'missing followup',
            baseline: fault != 'missing baseline',
          ),
          result: assessment(
            owner: fault == 'owner' ? 'b' : 'a',
            planId: fault == 'plan' ? 'other' : 'plan',
            planRevision: fault == 'revision' ? 2 : 1,
            baseline: fault != 'baseline',
            followUp: fault != 'followup',
          ),
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'available assessment requires generation instant and recorded review requires record evidence',
    () {
      expect(
        () => ComparisonAssessment(
          id: 'a',
          owner: 'a',
          planId: 'plan',
          planRevision: 1,
          revision: 1,
          status: AssessmentStatus.available,
          source: AssessmentSource.aiObservation,
        ),
        throwsFormatException,
      );
      expect(
        () => ComparisonAssessment(
          id: 'a',
          owner: 'a',
          planId: 'plan',
          planRevision: 1,
          revision: 1,
          status: AssessmentStatus.pending,
          source: AssessmentSource.unknown,
          review: AssessmentReview.recorded,
        ),
        throwsFormatException,
      );
      expect(
        () => ComparisonAssessment(
          id: 'a',
          owner: 'a',
          planId: 'plan',
          planRevision: 1,
          revision: 1,
          status: AssessmentStatus.insufficientEvidence,
          source: AssessmentSource.aiObservation,
          observations: ['fake result'],
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'default repository explicitly refuses list and detail operations with zero HTTP',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final n = f.requests.length;
        const repository = UnsupportedComparisonRepository();
        final context = ComparisonReadContext('a', api.sessionGeneration);
        await expectLater(
          repository.readPlans(context),
          throwsA(isA<ComparisonUnsupported>()),
        );
        await expectLater(
          repository.readPlan('plan', context),
          throwsA(isA<ComparisonUnsupported>()),
        );
        final controller = ComparisonController(api, planId: 'plan');
        await controller.refresh();
        expect(controller.phase, ComparisonPhase.unavailable);
        expect(controller.snapshot, isNull);
        expect(controller.canAssociateCapture, false);
        expect(controller.canRequestAssessment, false);
        expect(f.requests.length, n);
        controller.dispose();
        await f.done();
      });
    },
  );
  test(
    'controller loads only matching domain snapshot and context binds current account',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()..value = snapshot();
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        expect(controller.snapshot!.plan.id, 'plan');
        expect(repo.contexts.single.owner, 'a');
        expect(repo.contexts.single.generation, api.sessionGeneration);
        expect((await repo.readPlans(repo.contexts.single)).single.id, 'plan');
        controller.dispose();
        await f.done();
      });
    },
  );
  for (final reason in [
    'empty',
    'stale',
    'unknown freshness',
    'wrong owner',
    'wrong identity',
    'unsupported',
    'offline',
  ]) {
    test(
      'controller $reason does not publish a fresh confirmed plan',
      () async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository();
          repo.value = reason == 'empty'
              ? null
              : snapshot(
                  value: plan(
                    owner: reason == 'wrong owner' ? 'b' : 'a',
                    id: reason == 'wrong identity' ? 'other' : 'plan',
                  ),
                  freshness: reason == 'stale'
                      ? ComparisonFreshness.stale
                      : reason == 'unknown freshness'
                      ? ComparisonFreshness.unknown
                      : ComparisonFreshness.fresh,
                );
          if (reason == 'unsupported') {
            repo.failure = const ComparisonUnsupported();
          }
          if (reason == 'offline') {
            repo.failure = http.ClientException('Synthetic offline');
          }
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          expect(controller.snapshot, isNull);
          expect(
            controller.phase,
            reason == 'empty'
                ? ComparisonPhase.empty
                : reason == 'stale' || reason == 'unknown freshness'
                ? ComparisonPhase.stale
                : reason == 'unsupported'
                ? ComparisonPhase.unavailable
                : ComparisonPhase.failed,
          );
          controller.dispose();
          await f.done();
        });
      },
    );
  }
  test(
    'timeout remains failed and late completion cannot undo successful GET retry',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<ComparisonSnapshot?>();
        final repo = FakeComparisonRepository()..pending = () => pending.future;
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
          timeout: const Duration(milliseconds: 5),
        );
        await controller.refresh();
        expect(controller.phase, ComparisonPhase.failed);
        expect(controller.error, contains('timed out'));
        repo.pending = null;
        repo.value = snapshot(value: plan(revision: 2));
        await controller.refresh();
        pending.complete(snapshot());
        await Future<void>.delayed(Duration.zero);
        expect(controller.snapshot!.plan.revision, 2);
        controller.dispose();
        await f.done();
      });
    },
  );
  test('concurrent refresh permits only newest response', () async {
    final f = h.Fixture();
    await f.run(() async {
      await f.login();
      final a = Completer<ComparisonSnapshot?>(),
          b = Completer<ComparisonSnapshot?>();
      var reads = 0;
      final repo = FakeComparisonRepository()
        ..pending = () => reads++ == 0 ? a.future : b.future;
      final controller = ComparisonController(
        api,
        planId: 'plan',
        repository: repo,
      );
      final first = controller.refresh(), second = controller.refresh();
      b.complete(
        snapshot(
          value: plan(revision: 2, lifecycle: ComparisonLifecycle.cancelled),
        ),
      );
      await second;
      a.complete(snapshot());
      await first;
      expect(
        controller.snapshot!.plan.lifecycle,
        ComparisonLifecycle.cancelled,
      );
      controller.dispose();
      await f.done();
    });
  });
  for (final state in [
    ComparisonLifecycle.rescheduled,
    ComparisonLifecycle.cancelled,
    ComparisonLifecycle.superseded,
    ComparisonLifecycle.expired,
  ]) {
    test(
      '$state cannot be replaced by older or conflicting same-revision plan',
      () async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(
                revision: 2,
                lifecycle: state,
                date: DateTime.utc(2027),
              ),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          expect(controller.snapshot!.plan.lifecycle, state);
          repo.value = snapshot();
          await controller.refresh();
          expect(controller.snapshot, isNull);
          expect(controller.phase, ComparisonPhase.failed);
          repo.value = snapshot(value: plan(revision: 2));
          await controller.refresh();
          expect(controller.snapshot, isNull);
          controller.dispose();
          await f.done();
        });
      },
    );
  }
  test(
    'old assessment revision is not displayed after newer assessment',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..value = snapshot(
            value: plan(followUp: true),
            result: assessment(revision: 2),
          );
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        expect(controller.snapshot!.assessment!.revision, 2);
        repo.value = snapshot(
          value: plan(followUp: true),
          result: assessment(revision: 1),
        );
        await controller.refresh();
        expect(controller.phase, ComparisonPhase.failed);
        expect(controller.snapshot, isNull);
        controller.dispose();
        await f.done();
      });
    },
  );
  for (final action in ['logout', 'switch', 'revoke', 'dispose']) {
    test('$action rejects late plan and clears capture context', () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<ComparisonSnapshot?>();
        final repo = FakeComparisonRepository()..pending = () => pending.future;
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        final reading = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        if (action == 'logout') {
          await api.logout();
        } else if (action == 'switch') {
          await f.login('b');
        } else if (action == 'revoke') {
          f.noConsent = true;
          await f.state.account.hydrate(reuseConsent: false);
        } else {
          controller.dispose();
        }
        pending.complete(snapshot());
        await reading;
        expect(controller.snapshot, isNull);
        expect(controller.captureContext, isNull);
        expect(controller.current, false);
        if (action != 'dispose') controller.dispose();
        await f.done();
      });
    });
  }
  test(
    'old 401 through existing guarded transport cannot expire B with reused token',
    () async {
      final f = h.Fixture()..pendingDetail = Completer();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..pending = () async {
            await api.readGuidedCapture(
              id: 'baseline',
              generation: api.sessionGeneration,
            );
            return snapshot();
          };
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        final reading = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        await f.login('b');
        f.pendingDetail!.complete(o.jsonResponse({}, 401));
        await reading;
        expect(api.observationOwner, 'b');
        expect(api.hasConfirmedSafetyAcceptance, true);
        expect(controller.snapshot, isNull);
        controller.dispose();
        await f.done();
      });
    },
  );
  for (final variant in [
    'due',
    'unknown due',
    'pending patient',
    'unknown source',
    'missing date',
    'missing baseline',
    'cancelled',
  ]) {
    test(
      'capture handoff context $variant never associates uploaded capture locally',
      () async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(
                lifecycle: variant == 'cancelled'
                    ? ComparisonLifecycle.cancelled
                    : ComparisonLifecycle.due,
                due: variant == 'unknown due' ? null : true,
                confirmation: variant == 'pending patient'
                    ? PatientConfirmation.pending
                    : PatientConfirmation.confirmed,
                source: variant == 'unknown source'
                    ? SchedulingSource.unknown
                    : SchedulingSource.doctorDirected,
                noDate: variant == 'missing date',
                baseline: variant != 'missing baseline',
              ),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          final context = controller.captureContext;
          expect(context != null, variant == 'due');
          if (context != null) {
            expect(
              controller.recognizesUnassociatedCapture(
                context,
                capture(id: 'uploaded'),
              ),
              true,
            );
            expect(
              controller.recognizesUnassociatedCapture(
                context,
                capture(owner: 'b'),
              ),
              false,
            );
          }
          expect(controller.snapshot!.plan.followUp, isNull);
          expect(controller.canAssociateCapture, false);
          expect(controller.canRequestAssessment, false);
          controller.dispose();
          await f.done();
        });
      },
    );
  }
  for (final theme in [
    'light',
    'dark',
    'large light',
    'large dark',
    'reduced',
  ]) {
    testWidgets(
      'prepared summary $theme uses explicit source/date and no inferred medical result',
      (t) async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final decisions = [
            SchedulingDecision(
              recordId: 'doctor',
              source: SchedulingSource.doctorDirected,
              recordedAt: instant,
            ),
            SchedulingDecision(
              recordId: 'ai',
              source: SchedulingSource.aiProposed,
              recordedAt: instant,
            ),
          ];
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(
                decisions: decisions,
                resolutionId: 'doctor',
                date: DateTime.utc(2000),
              ),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          await mount(
            t,
            f,
            controller,
            dark: theme.contains('dark'),
            reduced: theme == 'reduced',
            scale: theme.contains('large') ? 2 : 1,
            width: theme.contains('large') ? 320 : 390,
          );
          await t.pumpAndSettle();
          expect(
            find.textContaining('Due status not provided'),
            findsOneWidget,
          );
          expect(
            find.textContaining('AI proposal — not a clinician instruction'),
            findsOneWidget,
          );
          expect(find.textContaining('Doctor-directed decision'), findsWidgets);
          expect(
            find.textContaining('Assessment unavailable.'),
            findsOneWidget,
          );
          expect(find.textContaining('2000-01-01'), findsOneWidget);
          expect(find.text('Compare any two photos'), findsNothing);
          expect(find.text('Start assessment'), findsNothing);
          expect(t.takeException(), isNull);
          controller.dispose();
          await f.done(t);
        });
      },
    );
  }
  for (final source in AssessmentSource.values) {
    testWidgets(
      'future result source $source stays explicit and never becomes a clinical score',
      (t) async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(followUp: true),
              result: assessment(
                source: source,
                review: source == AssessmentSource.clinicianAuthored
                    ? AssessmentReview.recorded
                    : AssessmentReview.pending,
              ),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          await mount(t, f, controller);
          await t.pumpAndSettle();
          expect(
            find.text('Synthetic source observation.'),
            source == AssessmentSource.unknown ? findsNothing : findsOneWidget,
          );
          if (source == AssessmentSource.aiObservation) {
            expect(
              find.text(
                'Source: AI-generated observation — not a clinician diagnosis.',
              ),
              findsOneWidget,
            );
          }
          if (source == AssessmentSource.clinicianAuthored) {
            expect(
              find.text('Source: clinician-authored statement.'),
              findsOneWidget,
            );
          }
          expect(find.text('Skin health score'), findsNothing);
          expect(find.textContaining('% improvement'), findsNothing);
          expect(
            find.text('Limitation: Synthetic evidence limitation.'),
            findsOneWidget,
          );
          expect(
            find.text('Uncertainty: Synthetic uncertainty.'),
            findsOneWidget,
          );
          controller.dispose();
          await f.done(t);
        });
      },
    );
  }
  for (final status in [
    AssessmentStatus.pending,
    AssessmentStatus.processing,
    AssessmentStatus.failed,
    AssessmentStatus.insufficientEvidence,
    AssessmentStatus.unknown,
  ]) {
    testWidgets(
      'assessment $status presentation stays distinct without fake success',
      (t) async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(followUp: true),
              result: assessment(status: status),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          await mount(t, f, controller);
          await t.pumpAndSettle();
          expect(find.text('Synthetic source observation.'), findsNothing);
          expect(find.text('Assessment record available.'), findsNothing);
          expect(
            find.textContaining(
              status == AssessmentStatus.insufficientEvidence
                  ? 'Insufficient evidence'
                  : status == AssessmentStatus.unknown
                  ? 'Unknown assessment status'
                  : status == AssessmentStatus.failed
                  ? 'Assessment failed'
                  : status == AssessmentStatus.processing
                  ? 'Assessment processing'
                  : 'Assessment pending',
            ),
            findsOneWidget,
          );
          controller.dispose();
          await f.done(t);
        });
      },
    );
  }
  testWidgets(
    'unsupported default shows unavailable, not a fake empty plan or comparison action',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final n = f.requests.length;
        final controller = ComparisonController(api, planId: 'plan');
        await controller.refresh();
        await mount(t, f, controller, images: true);
        await t.pumpAndSettle();
        expect(
          find.textContaining(
            'Scheduling and assessment contracts are not connected',
          ),
          findsOneWidget,
        );
        expect(
          find.text('No confirmed follow-up plan was returned.'),
          findsNothing,
        );
        expect(find.byType(PrivateCaptureImage), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(f.requests.length, n);
        controller.dispose();
        await f.done(t);
      });
    },
  );
  testWidgets(
    'prepared loading, failure and keyboard GET retry have honest semantics',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<ComparisonSnapshot?>();
        final repo = FakeComparisonRepository()..pending = () => pending.future;
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        final reading = controller.refresh();
        await mount(t, f, controller, reduced: true);
        expect(
          find.text('Reading confirmed follow-up information…'),
          findsOneWidget,
        );
        expect(
          EntryMotion.reduced(t.element(find.byType(ComparisonPanel))),
          true,
        );
        pending.completeError(http.ClientException('Synthetic offline'));
        await reading;
        await t.pumpAndSettle();
        expect(find.textContaining('could not be verified'), findsOneWidget);
        final semantics = t.ensureSemantics();
        await t.pump();
        await t.ensureVisible(find.text('Read follow-up information'));
        await t.pumpAndSettle();
        expect(
          t
              .getSemantics(find.text('Read follow-up information'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          true,
        );
        repo.pending = null;
        repo.value = null;
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.sendKeyEvent(LogicalKeyboardKey.enter);
        await t.pumpAndSettle();
        expect(repo.reads, 2);
        expect(
          find.text('No confirmed follow-up plan was returned.'),
          findsOneWidget,
        );
        semantics.dispose();
        controller.dispose();
        await f.done(t);
      });
    },
  );
  testWidgets(
    'superseded and cancelled plan never display prior images or assessment',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..value = snapshot(
            value: plan(
              followUp: true,
              lifecycle: ComparisonLifecycle.cancelled,
            ),
            result: assessment(),
          );
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        await mount(t, f, controller, images: true);
        await t.pumpAndSettle();
        expect(find.byType(PrivateCaptureImage), findsNothing);
        expect(find.text('Synthetic source observation.'), findsNothing);
        expect(
          find.text('Current plan-linked images unavailable.'),
          findsOneWidget,
        );
        expect(f.requests.where((r) => r.url.path.endsWith('/image')), isEmpty);
        controller.dispose();
        await f.done(t);
      });
    },
  );
  for (final variant in [
    'baseline missing',
    'followup missing',
    'metadata missing',
    'not stored',
  ]) {
    testWidgets('reference viewer $variant never infers images', (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final p = variant == 'not stored'
            ? ComparisonPlan(
                id: 'plan',
                owner: 'a',
                revision: 1,
                recordedAt: instant,
                lifecycle: ComparisonLifecycle.scheduled,
                decisions: [
                  SchedulingDecision(
                    recordId: 'decision',
                    source: SchedulingSource.doctorDirected,
                    recordedAt: instant,
                  ),
                ],
                resolvedDecisionId: 'decision',
                schedule: FollowUpSchedule(instantUtc: DateTime.utc(2027)),
                confirmation: PatientConfirmation.confirmed,
                baseline: link(stored: false),
              )
            : plan(
                baseline: variant != 'baseline missing',
                followUp:
                    variant == 'baseline missing' ||
                    variant == 'metadata missing',
                metadata: variant != 'metadata missing',
              );
        final repo = FakeComparisonRepository()..value = snapshot(value: p);
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        await mount(t, f, controller, images: true);
        await settlePair(t);
        final expected =
            variant == 'metadata missing' || variant == 'not stored' ? 0 : 1;
        expect(
          f.requests.where((r) => r.url.path.endsWith('/image')).length,
          expected,
        );
        expect(
          find.textContaining(
            variant == 'metadata missing'
                ? 'Owned capture metadata unavailable'
                : variant == 'not stored'
                ? 'Linked capture has no accepted stored image'
                : 'No explicit capture association provided.',
          ),
          findsWidgets,
        );
        controller.dispose();
        await f.done(t);
      });
    });
  }
  testWidgets(
    'authorized pair reuses bounded private viewer and zoom controls without alignment claims',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..value = snapshot(value: plan(followUp: true));
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        await mount(t, f, controller, width: 1000, images: true);
        await settlePair(t);
        expect(
          f.requests
              .where((r) => r.url.path.endsWith('/image'))
              .map((r) => r.url.path),
          [
            '/api/v1/captures/baseline/image',
            '/api/v1/captures/followUp/image',
          ],
        );
        expect(find.byType(RawImage), findsNWidgets(2));
        expect(find.byType(InteractiveViewer), findsNWidgets(2));
        expect(f.images.decodedPixels, 32 * 40 * 2);
        await t.ensureVisible(find.text('Zoom in').first);
        await t.pumpAndSettle();
        await t.tap(find.text('Zoom in').first);
        await t.pump();
        expect(
          t
              .widget<InteractiveViewer>(find.byType(InteractiveViewer).first)
              .transformationController!
              .value
              .getMaxScaleOnAxis(),
          1.5,
        );
        expect(
          find.textContaining('not clinically aligned or normalized'),
          findsOneWidget,
        );
        controller.dispose();
        await f.done(t);
        expect(f.images.decodedPixels, 0);
      });
    },
  );
  for (final action in ['switch', 'logout', 'reschedule', 'cancel', 'stale']) {
    testWidgets('$action clears displayed pair and late private responses', (
      t,
    ) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..value = snapshot(value: plan(followUp: true));
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        await mount(t, f, controller, images: true);
        await settlePair(t);
        expect(find.byType(RawImage), findsNWidgets(2));
        if (action == 'switch') {
          await f.login('b');
        } else if (action == 'logout') {
          await api.logout();
        } else {
          repo.value = snapshot(
            value: plan(
              revision: 2,
              lifecycle: action == 'cancel'
                  ? ComparisonLifecycle.cancelled
                  : ComparisonLifecycle.rescheduled,
              baseline: false,
            ),
            freshness: action == 'stale'
                ? ComparisonFreshness.stale
                : ComparisonFreshness.fresh,
          );
          await controller.refresh();
        }
        await t.pumpAndSettle();
        expect(find.byType(RawImage), findsNothing);
        expect(f.images.decodedPixels, 0);
        controller.dispose();
        await f.done(t);
      });
    });
  }
  testWidgets('late paired image load after account switch cannot paint in B', (
    t,
  ) async {
    final f = h.Fixture()..pendingImage = Completer();
    await f.run(() async {
      await f.login();
      final repo = FakeComparisonRepository()
        ..value = snapshot(value: plan(followUp: true));
      final controller = ComparisonController(
        api,
        planId: 'plan',
        repository: repo,
      );
      await controller.refresh();
      await mount(t, f, controller, images: true);
      await t.pump();
      await f.login('b');
      await t.pump();
      f.pendingImage!.complete(
        http.Response.bytes(
          g.pngBytes(),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
      await settlePair(t);
      expect(find.byType(RawImage), findsNothing);
      expect(f.images.decodedPixels, 0);
      expect(controller.snapshot, isNull);
      controller.dispose();
      await f.done(t);
    });
  });
  for (final variant in [
    'not scheduled',
    'pending AI',
    'patient only',
    'unknown source',
    'missing date',
  ]) {
    testWidgets(
      '$variant cannot expose paired images or an available assessment',
      (t) async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(
                followUp: true,
                lifecycle: variant == 'not scheduled'
                    ? ComparisonLifecycle.notScheduled
                    : ComparisonLifecycle.scheduled,
                source: variant == 'pending AI'
                    ? SchedulingSource.aiProposed
                    : variant == 'patient only'
                    ? SchedulingSource.patientConfirmed
                    : variant == 'unknown source'
                    ? SchedulingSource.unknown
                    : SchedulingSource.doctorDirected,
                confirmation: variant == 'pending AI'
                    ? PatientConfirmation.pending
                    : PatientConfirmation.confirmed,
                noDate: variant == 'missing date',
              ),
              result: assessment(),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          await mount(t, f, controller, images: true);
          await t.pumpAndSettle();
          expect(find.byType(PrivateCaptureImage), findsNothing);
          expect(find.text('Synthetic source observation.'), findsNothing);
          expect(
            f.requests.where((r) => r.url.path.endsWith('/image')),
            isEmpty,
          );
          expect(controller.captureContext, isNull);
          controller.dispose();
          await f.done(t);
        });
      },
    );
  }
  testWidgets(
    'paired private references support 320px 200% text dark/reduced motion',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..value = snapshot(value: plan(followUp: true));
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        await mount(
          t,
          f,
          controller,
          width: 320,
          scale: 2,
          dark: true,
          reduced: true,
          images: true,
        );
        await settlePair(t);
        expect(find.byType(RawImage), findsNWidgets(2));
        expect(find.text('Reset image zoom'), findsNWidgets(2));
        expect(t.takeException(), isNull);
        expect(f.images.decodedPixels, lessThan(1600 * 1600 * 2));
        controller.dispose();
        await f.done(t);
      });
    },
  );
  testWidgets(
    'idle expiration drops pending comparison read and its private references',
    (t) async {
      final f = h.Fixture()..ttl = 1;
      await f.run(() async {
        await f.login();
        final pending = Completer<ComparisonSnapshot?>();
        final repo = FakeComparisonRepository()..pending = () => pending.future;
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        final reading = controller.refresh();
        await mount(t, f, controller, images: true);
        await t.pump(const Duration(seconds: 2));
        pending.complete(snapshot(value: plan(followUp: true)));
        await reading;
        await t.pumpAndSettle();
        expect(controller.current, false);
        expect(controller.snapshot, isNull);
        expect(controller.phase, ComparisonPhase.ended);
        expect(find.byType(PrivateCaptureImage), findsNothing);
        controller.dispose();
        await f.done(t);
      });
    },
  );
  test(
    'current401 invalidates comparison state through existing guarded session layer',
    () async {
      final f = h.Fixture()..detailCode = 401;
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..pending = () async {
            await api.readGuidedCapture(
              id: 'baseline',
              generation: api.sessionGeneration,
            );
            return snapshot();
          };
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        expect(api.isAuthenticated, false);
        expect(controller.snapshot, isNull);
        expect(controller.phase, ComparisonPhase.ended);
        controller.dispose();
        await f.done();
      });
    },
  );
  test(
    'stale newer cancellation prevents older fresh plan resurrection',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()..value = snapshot();
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        repo.value = snapshot(
          value: plan(revision: 2, lifecycle: ComparisonLifecycle.cancelled),
          freshness: ComparisonFreshness.stale,
        );
        await controller.refresh();
        expect(controller.phase, ComparisonPhase.stale);
        repo.value = snapshot();
        await controller.refresh();
        expect(controller.phase, ComparisonPhase.failed);
        expect(controller.snapshot, isNull);
        repo.value = snapshot(
          value: plan(revision: 2, lifecycle: ComparisonLifecycle.cancelled),
        );
        await controller.refresh();
        expect(
          controller.snapshot!.plan.lifecycle,
          ComparisonLifecycle.cancelled,
        );
        controller.dispose();
        await f.done();
      });
    },
  );
  test(
    'temporary missing assessment does not remove revision watermark',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = FakeComparisonRepository()
          ..value = snapshot(
            value: plan(followUp: true),
            result: assessment(revision: 2),
          );
        final controller = ComparisonController(
          api,
          planId: 'plan',
          repository: repo,
        );
        await controller.refresh();
        repo.value = snapshot(value: plan(followUp: true));
        await controller.refresh();
        expect(controller.snapshot!.assessment, isNull);
        repo.value = snapshot(
          value: plan(followUp: true),
          result: assessment(revision: 1),
        );
        await controller.refresh();
        expect(controller.snapshot, isNull);
        expect(controller.phase, ComparisonPhase.failed);
        controller.dispose();
        await f.done();
      });
    },
  );
  for (final action in ['reschedule', 'cancel', 'logout', 'switch']) {
    test(
      'previous camera context cannot authorize a candidate after $action',
      () async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = FakeComparisonRepository()
            ..value = snapshot(
              value: plan(lifecycle: ComparisonLifecycle.due, due: true),
            );
          final controller = ComparisonController(
            api,
            planId: 'plan',
            repository: repo,
          );
          await controller.refresh();
          final context = controller.captureContext!;
          expect(
            controller.recognizesUnassociatedCapture(context, capture()),
            true,
          );
          if (action == 'logout') {
            await api.logout();
          } else if (action == 'switch') {
            await f.login('b');
          } else {
            repo.value = snapshot(
              value: plan(
                revision: 2,
                lifecycle: action == 'cancel'
                    ? ComparisonLifecycle.cancelled
                    : ComparisonLifecycle.due,
                due: true,
                date: DateTime.utc(2027),
              ),
            );
            await controller.refresh();
          }
          expect(
            controller.recognizesUnassociatedCapture(context, capture()),
            false,
          );
          expect(controller.canAssociateCapture, false);
          controller.dispose();
          await f.done();
        });
      },
    );
  }
  testWidgets(
    'current production shell/entry has no comparison navigation or synthetic plan state',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        await h.mount(t, f, AppShell(state: f.state));
        await t.pump(const Duration(milliseconds: 500));
        expect(AppShell.labels, [
          'Home',
          'Experiment',
          'Products',
          'Rewards',
          'Reports',
          'Profile',
        ]);
        expect(find.byType(ComparisonPanel), findsNothing);
        expect(find.byType(PlanReferenceImages), findsNothing);
        await t.pumpWidget(const SizedBox());
        await h.mount(t, f, Scaffold(body: GuidedCaptureEntry(state: f.state)));
        await t.pumpAndSettle();
        expect(find.text('Private image history'), findsOneWidget);
        expect(find.text('Compare'), findsNothing);
        expect(
          f.requests.where(
            (r) =>
                r.url.path.contains('comparison') ||
                r.url.path.contains('assessment'),
          ),
          isEmpty,
        );
        await f.done(t);
      });
    },
  );
}
