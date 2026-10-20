import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/capture/guided_camera_screen.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/doctor/doctor_context_page.dart';
import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/observations/observation_models.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'home_state_integration_test.dart' as home;
import 'observation_test.dart' as observation;
import 'm6_clinical_reviews_test.dart' as clinical;
import 'm6_doctor_fixture.dart' as fixture;
import 'wave_messaging_test.dart' as messages;
import 'wave_plans_test.dart' as plans;

final api = ApiService.instance;
Future<void> tap(WidgetTester t, Finder target) async {
  await t.scrollUntilVisible(
    target,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pumpAndSettle();
}

Widget themed(Widget screen, bool dark) => MaterialApp(
  theme: dark ? DermaireTheme.dark : DermaireTheme.light,
  builder: (_, child) => MediaQuery(
    data: const MediaQueryData(
      textScaler: TextScaler.linear(2),
      disableAnimations: true,
    ),
    child: child!,
  ),
  home: screen,
);

class StoredHistory extends home.HistoryRepo {
  @override
  Future<ObservationRecord> save(ObservationDraft draft, int generation) async {
    final saved = await super.save(draft, generation);
    data = [saved];
    return saved;
  }
}

class PatientFixture extends home.Fixture {
  final StoredHistory storedHistory = StoredHistory();
  @override
  StoredHistory get history => storedHistory;
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.contains('/routine/') ||
        r.url.path.endsWith('/experiments')) {
      return fixture.json([]);
    }
    return transport(r);
  }
}

class ContextMessages extends messages.MessageWire {
  ContextMessages() : super(doctor: true);
  @override
  Map<String, dynamic> get thread => {
    ...super.thread,
    'access_id': 'grant-patient-1',
  };
}

// Contract-faithful deterministic winter Cairo schedule. The shared fixture
// preserves its old UTC value on reschedule; this journey must verify the new one.
class ScheduleWire extends plans.PlanWire {
  ScheduleWire() : super(doctor: true);
  @override
  Future<http.Response> call(http.Request r) async {
    final response = await super.call(r);
    if (r.method == 'POST' &&
        r.url.path.endsWith('/reschedule') &&
        response.statusCode == 201) {
      final body = jsonDecode(r.body) as Map;
      expect(body['local_due'], '2027-01-12T11:00');
      expect(body['timezone'], 'Africa/Cairo');
      expect(body['expected_revision'], 1);
      plan = {
        ...plan,
        'due_at_utc': '2027-01-12T09:00:00Z',
        'schedule_provenance': {
          ...plan['schedule_provenance'] as Map,
          'due_at_utc': '2027-01-12T09:00:00Z',
        },
      };
      receipts[r.headers['Idempotency-Key']!] = Map.from(plan);
      events.last['snapshot'] = {
        'plan': Map.from(plan),
        'details': <String, dynamic>{},
      };
      return fixture.json(plan, 201);
    }
    return response;
  }
}

class CareWire extends clinical.ClinicalWire {
  final messaging = ContextMessages();
  final plan = ScheduleWire();
  bool hold = false;
  final started = Completer<void>();
  final held = Completer<http.Response>();
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    if (hold &&
        r.method == 'GET' &&
        (r.url.path.endsWith('/messages') ||
            r.url.path.endsWith('/clinical-plans/plan-1'))) {
      if (!started.isCompleted) started.complete();
      return held.future;
    }
    if (r.url.path.contains('/messaging/')) return messaging.call(r);
    if (r.url.path.contains('/clinical-plans')) return plan.call(r);
    return super.call(r);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() => api.init());
  for (final dark in [false, true]) {
    testWidgets(
      'Home observation and routine return re-read server projection dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final f = PatientFixture();
        await http.runWithClient(() async {
          await f.ready();
          await t.pumpWidget(
            themed(Scaffold(body: HomeTab(state: f.state)), dark),
          );
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('homeObserve')));
          await tap(t, find.text('Photo quality check — separate'));
          await tap(t, find.byKey(const Key('openGuidedCamera')));
          expect(find.byType(GuidedCameraScreen), findsOneWidget);
          expect(find.byKey(const Key('startLiveCamera')), findsOneWidget);
          // Navigate the real disclosure screen; never start camera hardware.
          Navigator.of(t.element(find.byType(GuidedCameraScreen))).pop();
          await t.pumpAndSettle();
          for (final key in [
            'change_same',
            'moment_Morning',
            'routine_partial',
            'reviewObservation',
            'submitObservation',
          ]) {
            await tap(t, find.byKey(Key(key)));
          }
          expect(find.text('Observation saved'), findsOneWidget);
          expect(f.history.writes, 1);
          final before = f.home.calls;
          Navigator.of(t.element(find.byType(CameraScreen))).pop();
          await t.pumpAndSettle();
          expect(f.home.calls, greaterThan(before));
          expect(f.state.home.current?['today_checked_in'], false);
          expect(f.state.observations.rows, hasLength(1));
          await tap(t, find.byKey(const Key('homeRoutine')));
          expect(find.byType(RoutineScreen), findsOneWidget);
          final beforeRoutine = f.home.calls;
          Navigator.of(t.element(find.byType(RoutineScreen))).pop();
          await t.pumpAndSettle();
          expect(f.home.calls, greaterThan(beforeRoutine));
          expect(t.takeException(), isNull);
          await home.finish(t, f);
        }, () => observation.isolated(f.call));
      },
    );
    testWidgets('Home route return cannot refresh old account dark=$dark', (
      t,
    ) async {
      final f = PatientFixture();
      await http.runWithClient(() async {
        await f.ready();
        await t.pumpWidget(
          themed(Scaffold(body: HomeTab(state: f.state)), dark),
        );
        await t.pumpAndSettle();
        await tap(t, find.byKey(const Key('homeRoutine')));
        await api.logout();
        f.owner = 'b';
        f.name = 'Another account';
        await f.login();
        final before = f.home.calls;
        Navigator.of(t.element(find.byType(RoutineScreen))).pop();
        await t.pumpAndSettle();
        expect(f.home.calls, before);
        expect(f.state.home.current, isNull);
        expect(find.text('Welcome, Verified'), findsNothing);
        expect(t.takeException(), isNull);
        await home.finish(t, f);
      }, () => observation.isolated(f.call));
    });
    testWidgets(
      'created plan detail keeps original doctor context dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final w = CareWire();
        await w.run(() async {
          final v = await clinical.editor(w);
          await t.pumpWidget(
            themed(
              DoctorContextPage(
                connection: v.$2,
                child: CreateClinicalPlanScreen(connection: v.$2),
              ),
              dark,
            ),
          );
          await t.pumpAndSettle();
          for (final entry in {
            'followupPurpose':
                'Explicit synthetic follow-up for selected patient.',
            'planLocalDue': '2027-01-12 10:00',
            'planTimezone': 'Africa/Cairo',
          }.entries) {
            final field = find.byKey(Key(entry.key));
            await t.scrollUntilVisible(
              field,
              250,
              scrollable: find.byType(Scrollable).first,
            );
            await t.ensureVisible(field);
            await t.enterText(field, entry.value);
            FocusManager.instance.primaryFocus?.unfocus();
            await t.pumpAndSettle();
          }
          await tap(t, find.byKey(const Key('submitPlanSchedule')));
          expect(w.plan.sends, hasLength(1));
          expect(api.integrationIntents, isEmpty);
          await tap(t, find.text('Open confirmed plan'));
          expect(find.byType(ClinicalPlanScreen), findsOneWidget);
          await t.scrollUntilVisible(
            find.text('Explicit synthetic follow-up for selected patient.'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.text('Explicit synthetic follow-up for selected patient.'),
            findsOneWidget,
          );
          final due = find.byKey(const Key('planLocalDue'));
          await t.scrollUntilVisible(
            due,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await t.ensureVisible(due);
          await t.enterText(due, '2027-01-12 11:00');
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
          await tap(t, find.byKey(const Key('submitPlanSchedule')));
          expect(w.plan.sends, hasLength(2));
          expect(w.plan.plan['revision'], 2);
          expect(w.plan.plan['state'], 'proposed');
          expect(w.plan.plan['due_at_utc'], '2027-01-12T09:00:00Z');
          expect(api.integrationIntents, isEmpty);
          v.$1.selectPatient('not-authorized');
          await t.pumpAndSettle();
          expect(find.byType(ClinicalPlanScreen), findsNothing);
          expect(
            find.text('Explicit synthetic follow-up for selected patient.'),
            findsNothing,
          );
          expect(
            find.textContaining(
              'Patient context changed or access is unavailable.',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          clinical.clean(v);
          await api.init();
        });
      },
    );
    for (final messaging in [true, false]) {
      for (final late in [false, true]) {
        for (final loss in ['switch', 'revoked', 'logout']) {
          testWidgets(
            'nested doctor route purges old patient messaging=$messaging late=$late loss=$loss dark=$dark',
            (t) async {
              t.view.physicalSize = const Size(320, 1500);
              t.view.devicePixelRatio = 1;
              addTearDown(t.view.resetPhysicalSize);
              addTearDown(t.view.resetDevicePixelRatio);
              final w = CareWire();
              const privateText =
                  'Synthetic private message for selected patient.';
              w.messaging.messages.add(w.messaging.message(1, privateText));
              await w.run(() async {
                final v = await clinical.editor(w);
                await t.pumpWidget(
                  themed(
                    DoctorContextPage(
                      connection: v.$2,
                      child: messaging
                          ? CareThreadsScreen(
                              patient: 'patient-1',
                              connection: v.$2,
                            )
                          : ClinicalPlansScreen(
                              patient: 'patient-1',
                              connection: v.$2,
                            ),
                    ),
                    dark,
                  ),
                );
                await t.pumpAndSettle();
                w.hold = late;
                await tap(
                  t,
                  find.text(
                    messaging
                        ? 'Patient account patient-1'
                        : 'Clinician follow-up',
                  ),
                );
                if (late) {
                  await w.started.future;
                } else {
                  await t.scrollUntilVisible(
                    find.text(
                      messaging ? privateText : 'Review current skin tolerance',
                    ),
                    250,
                    scrollable: find.byType(Scrollable).first,
                  );
                  expect(
                    find.text(
                      messaging ? privateText : 'Review current skin tolerance',
                    ),
                    findsOneWidget,
                  );
                }
                switch (loss) {
                  case 'switch':
                    v.$1.selectPatient('not-authorized');
                  case 'revoked':
                    v.$1.forgetPatient('patient-1');
                  case 'logout':
                    await api.logout();
                }
                await t.pumpAndSettle();
                expect(
                  find.textContaining(
                    'Patient context changed or access is unavailable.',
                  ),
                  findsOneWidget,
                );
                if (late) {
                  final request = http.Request(
                    'GET',
                    Uri.parse(
                      messaging
                          ? 'https://flutter-tests.invalid/api/v1/messaging/threads/thread-1/messages?after=0&limit=50'
                          : 'https://flutter-tests.invalid/api/v1/clinical-plans/plan-1',
                    ),
                  );
                  w.held.complete(
                    await (messaging
                        ? w.messaging.call(request)
                        : w.plan.call(request)),
                  );
                  await t.pumpAndSettle();
                }
                expect(find.text(privateText), findsNothing);
                expect(find.byType(CareConversationScreen), findsNothing);
                expect(find.byType(ClinicalPlanScreen), findsNothing);
                expect(w.messaging.posts, 0);
                expect(w.plan.sends, isEmpty);
                expect(t.takeException(), isNull);
                await t.pumpWidget(const SizedBox());
                clinical.clean(v);
                await api.init();
              });
            },
          );
        }
      }
    }
  }
}
