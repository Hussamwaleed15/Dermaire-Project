import 'package:dermaire_app/clinical/clinical_controller.dart';
import 'package:dermaire_app/clinical/clinical_models.dart';
import 'package:dermaire_app/clinical/clinical_ui.dart';
import 'package:dermaire_app/home/home_policy.dart';
import 'package:dermaire_app/observations/observation_models.dart';
import 'package:dermaire_app/observations/observation_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'clinical_status_test.dart' as c;
import 'home_authority_test.dart' as h;
import 'home_observation_status_test.dart' as p;
import 'home_state_integration_test.dart' as f;
import 'observation_test.dart' as o;

class NotesRepository extends f.ClinicalRepo {
  @override
  Future<ClinicianReview> readReview(int generation) async =>
      ClinicianReview.fromApi({
        ...c.review(),
        'notes': [
          {
            'id': 'visible-note',
            'patient_id': 'a',
            'doctor_id': 'clinician',
            'priority': 'urgent',
            'patient_visible': true,
            'provenance': 'clinician_authored',
            'content': 'Recorded clinician instructions.',
            'follow_up': null,
            'created_at': '2026-10-12T12:00:00Z',
            'updated_at': '2026-10-12T12:00:00Z',
          },
        ],
      }, owner: 'a');
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  for (final scenario in [
    'today_complete',
    'today_empty_history',
    'legacy_history',
    'unavailable',
    'yesterday_unknown',
    'measurement_only',
    'report_only',
    'pending',
    'in_review',
    'urgent_clinician',
    'stale_urgent_clinician',
    'uncertain',
    'unknown_guidance_uncertain',
    'urgent_safety',
    'urgent_safety_clinician',
    'today_complete_experiment',
  ]) {
    test('M1 current authority determines next action: $scenario', () async {
      final fixture = f.Fixture();
      await http.runWithClient(() async {
        fixture.home.data = p.projection();
        fixture.history.data = [
          ObservationRecord.fromApi(o.record(), owner: 'a'),
        ];
        if (['today_empty_history', 'measurement_only'].contains(scenario)) {
          fixture.home.data = p.projection(
            completed: false,
            measured: scenario == 'measurement_only',
          );
        }
        if ([
          'legacy_history',
          'unavailable',
          'yesterday_unknown',
        ].contains(scenario)) {
          fixture.home.data = {...h.snapshot(), 'experiment': null};
        }
        if (scenario == 'pending' || scenario == 'in_review') {
          fixture.clinical.workflow = scenario;
        }
        if (scenario.contains('urgent_clinician') ||
            scenario == 'urgent_safety_clinician') {
          fixture.clinical.action = c.decision(recommendation: 'urgent');
        }
        if (scenario.startsWith('urgent_safety')) {
          fixture.clinical.status = 'urgent';
        }
        if (scenario == 'unknown_guidance_uncertain') {
          fixture.clinical.status = 'future';
        }
        if (scenario == 'today_complete_experiment') {
          fixture.home.data['experiment'] = h.snapshot()['experiment'];
        }
        await fixture.ready();
        if (scenario == 'unavailable') {
          fixture.home.fail = true;
          await fixture.state.home.refresh();
        }
        if (scenario == 'stale_urgent_clinician') {
          fixture.state.clinical.markStale();
        }
        if (scenario.contains('uncertain')) {
          fixture.state.observations.phase = ObservationPhase.uncertain;
        }
        final next = fixture.next;
        expect(next.action, switch (scenario) {
          'pending' ||
          'in_review' ||
          'urgent_clinician' ||
          'stale_urgent_clinician' => HomeAction.clinician,
          'urgent_safety' || 'urgent_safety_clinician' => HomeAction.safety,
          'uncertain' ||
          'unknown_guidance_uncertain' => HomeAction.uncertainObservation,
          'today_complete' || 'report_only' => HomeAction.history,
          'today_complete_experiment' => HomeAction.experiment,
          _ => HomeAction.observe,
        });
        if (['pending', 'in_review'].contains(scenario)) {
          expect(next.reason, contains('not a completed clinician decision'));
        }
        if (scenario == 'stale_urgent_clinician') {
          expect(next.reason, contains('Previously retrieved'));
        }
        if (scenario == 'measurement_only') {
          expect(fixture.state.home.current!['today_checked_in'], isTrue);
          expect(fixture.state.home.observationStatus!.completedToday, isFalse);
        }
        if (scenario == 'report_only') {
          expect(fixture.state.home.current!['today_checked_in'], isFalse);
        }
        if ([
          'legacy_history',
          'yesterday_unknown',
          'unavailable',
        ].contains(scenario)) {
          expect(next.reason, contains('does not establish an incomplete day'));
        }
        expect(next.title, isNot(contains('due')));
        expect(fixture.history.writes, 0);
        fixture.state.dispose();
      }, () => o.isolated(fixture.transport));
    });
  }

  test(
    'recorded notes invite clinician review without manufacturing current urgent risk',
    () async {
      final fixture = f.Fixture();
      await http.runWithClient(() async {
        await fixture.ready();
        final clinical = ClinicalController(api, repository: NotesRepository());
        await clinical.refresh();
        expect(clinical.review.value!.needsAttention, isTrue);
        expect(clinical.review.value!.hasUrgentGuidance, isFalse);
        expect(
          HomeNextAction.select(
            clinical: clinical,
            observations: fixture.state.observations,
            hasExperiment: false,
            observationStatus: fixture.state.home.observationStatus,
          ).action,
          HomeAction.clinician,
        );
        clinical.dispose();
        fixture.state.dispose();
      }, () => o.isolated(fixture.transport));
    },
  );

  testWidgets(
    'compact clinician notes lead to readable instructions and clear on session loss',
    (t) async {
      final fixture = f.Fixture();
      await http.runWithClient(() async {
        await fixture.ready();
        final controller = ClinicalController(
          api,
          repository: NotesRepository(),
        );
        await controller.refresh();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ClinicalHomePanel(controller: controller),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.textContaining('Patient-visible clinician notes are recorded'),
          findsOneWidget,
        );
        expect(find.text('Recorded clinician instructions.'), findsNothing);
        await t.pumpWidget(
          MaterialApp(home: ClinicalStatusScreen(controller: controller)),
        );
        await t.pumpAndSettle();
        expect(find.text('Recorded clinician instructions.'), findsOneWidget);
        await api.init();
        await t.pumpAndSettle();
        expect(find.text('Recorded clinician instructions.'), findsNothing);
        await t.pumpWidget(const SizedBox());
        controller.dispose();
        fixture.state.dispose();
      }, () => o.isolated(fixture.transport));
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'urgent clinician remains first while stale and opens real guidance dark=$dark',
      (t) async {
        final fixture = f.Fixture();
        await http.runWithClient(() async {
          fixture.home.data = p.projection();
          fixture.clinical.action = c.decision(recommendation: 'urgent');
          await fixture.ready();
          fixture.state.clinical.markStale();
          await f.mount(t, fixture, dark: dark, scale: 2, reduced: true);
          expect(
            t.getTopLeft(find.text('Clinician review')).dy,
            lessThan(t.getTopLeft(find.text('Safety Engine')).dy),
          );
          await f.reveal(t, find.byKey(const Key('homeNextActionButton')));
          expect(
            find.descendant(
              of: find.byKey(const Key('homeNextActionButton')),
              matching: find.text('Review urgent clinician guidance'),
            ),
            findsOneWidget,
          );
          await t.tap(find.byKey(const Key('homeNextActionButton')));
          await t.pumpAndSettle();
          expect(find.byType(ClinicalStatusScreen), findsOneWidget);
          expect(
            find.textContaining(
              'Previously retrieved clinician recommendation',
            ),
            findsOneWidget,
          );
          expect(fixture.history.writes, 0);
          expect(t.takeException(), isNull);
          await f.finish(t, fixture);
        }, () => o.isolated(fixture.transport));
      },
    );

    testWidgets(
      'explicit empty today opens observation rather than historical record dark=$dark',
      (t) async {
        final fixture = f.Fixture();
        await http.runWithClient(() async {
          fixture.home.data = p.projection(completed: false);
          fixture.history.data = [
            ObservationRecord.fromApi(o.record(), owner: 'a'),
          ];
          await fixture.ready();
          await f.mount(t, fixture, dark: dark, scale: 2, reduced: true);
          await f.reveal(t, find.byKey(const Key('homeNextActionButton')));
          expect(
            find.textContaining('optional, not a due schedule'),
            findsOneWidget,
          );
          await t.tap(find.byKey(const Key('homeNextActionButton')));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('reviewObservation')), findsOneWidget);
          expect(fixture.history.writes, 0);
          expect(t.takeException(), isNull);
          await f.finish(t, fixture);
        }, () => o.isolated(fixture.transport));
      },
    );
  }
}
