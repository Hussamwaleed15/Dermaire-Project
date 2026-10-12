import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/clinical/clinical_controller.dart';
import 'package:dermaire_app/clinical/clinical_models.dart';
import 'package:dermaire_app/clinical/clinical_ui.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/home/home_policy.dart';
import 'package:dermaire_app/home_controller.dart';
import 'package:dermaire_app/observations/observation_controller.dart';
import 'package:dermaire_app/observations/observation_models.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'observation_test.dart' as o;
import 'clinical_status_test.dart' as c;
import 'home_authority_test.dart' as h;
import 'baseline_authority_test.dart' as b;

final api = ApiService.instance;

class HomeRepo implements HomeRepository {
  Map<String, dynamic> data = {
    ...h.snapshot(),
    'experiment': null,
    'today_checked_in': false,
    'journal': [],
  };
  Completer<Map<String, dynamic>>? pending;
  bool fail = false;
  int calls = 0;
  @override
  Future<Map<String, dynamic>> read() async {
    calls++;
    if (fail) throw StateError('synthetic offline');
    return pending?.future ?? data;
  }
}

class HistoryRepo implements ObservationRepository {
  List<ObservationRecord> data = [];
  Completer<List<ObservationRecord>>? pending;
  bool fail = false;
  int reads = 0, writes = 0;
  @override
  Future<List<ObservationRecord>> history(int generation) async {
    reads++;
    if (fail) throw StateError('synthetic offline');
    return pending?.future ?? data;
  }

  @override
  Future<ObservationRecord> save(ObservationDraft draft, int generation) async {
    writes++;
    return ObservationRecord.fromApi(o.record(value: draft), owner: 'a');
  }
}

class ClinicalRepo implements ClinicalRepository {
  String status = 'track';
  Map<String, dynamic>? action;
  String? workflow;
  bool fail = false;
  Completer<SafetyAssessment>? pending;
  @override
  Future<SafetyAssessment> readSafety(int generation) async {
    if (fail) throw StateError('synthetic offline');
    return pending?.future ??
        SafetyAssessment.fromApi(c.safety(status: status, absent: true));
  }

  @override
  Future<ClinicianReview> readReview(int generation) async =>
      ClinicianReview.fromApi(
        c.review(
          state: workflow ?? (action == null ? 'not_requested' : 'reviewed'),
          action: action,
          evaluation: c.safety(status: status),
        ),
        owner: 'a',
      );
}

class Fixture {
  final home = HomeRepo(),
      baseline = b.FakeBaseline(),
      history = HistoryRepo(),
      clinical = ClinicalRepo();
  String owner = 'a', name = 'Verified Amr';
  late final state = DermaireState(
    homeRepository: home,
    baselineRepository: baseline,
    observationRepository: history,
    clinicalRepository: clinical,
  );
  Future<http.Response> transport(http.Request r) async {
    if (r.url.path.endsWith('/auth/login')) return o.auth(owner);
    if (r.url.path.endsWith('/users/me')) {
      return o.jsonResponse({
        ...jsonDecode(o.user(owner).body) as Map<String, dynamic>,
        'full_name': name,
      });
    }
    if (r.url.path.endsWith('/auth/logout')) return o.jsonResponse({});
    throw StateError('Unexpected HTTP: ${r.url.path}');
  }

  Future<void> login() async {
    await o.login(owner);
    await state.account.hydrate();
  }

  Future<void> ready() async {
    await login();
    await state.refreshPatientHome(generation: api.sessionGeneration);
  }

  HomeNextAction get next => HomeNextAction.select(
    clinical: state.clinical,
    observations: state.observations,
    hasExperiment: state.home.current?['experiment'] != null,
  );
}

Future<void> mount(
  WidgetTester t,
  Fixture f, {
  bool dark = false,
  double scale = 1,
  bool reduced = false,
}) async {
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? DermaireTheme.dark : DermaireTheme.light,
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduced,
        ),
        child: child!,
      ),
      home: Scaffold(body: HomeTab(state: f.state)),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder finder) async {
  await t.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await t.pumpAndSettle();
}

Future<void> finish(WidgetTester t, Fixture f) async {
  await t.pumpWidget(const SizedBox());
  f.state.dispose();
  await api.init();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() => api.init());
  for (final scenario in [
    'empty',
    'history',
    'experiment',
    'urgent',
    'clinician',
    'engine_review',
    'unknown',
    'stale',
    'uncertain',
  ]) {
    test('next action is explainable for $scenario', () async {
      final f = Fixture();
      await http.runWithClient(() async {
        if (scenario == 'history') {
          f.history.data = [ObservationRecord.fromApi(o.record(), owner: 'a')];
        }
        if (scenario == 'experiment') f.home.data = h.snapshot();
        if (scenario == 'urgent') f.clinical.status = 'urgent';
        if (scenario == 'engine_review') f.clinical.status = 'doctor_review';
        if (scenario == 'unknown') f.clinical.status = 'future_status';
        if (scenario == 'clinician') f.clinical.action = c.decision();
        await f.ready();
        if (scenario == 'stale') f.state.clinical.markStale();
        if (scenario == 'uncertain') {
          f.state.observations.phase = ObservationPhase.uncertain;
        }
        expect(f.next.action, switch (scenario) {
          'history' => HomeAction.history,
          'experiment' => HomeAction.experiment,
          'urgent' || 'engine_review' => HomeAction.safety,
          'clinician' => HomeAction.clinician,
          'unknown' || 'stale' => HomeAction.verifyGuidance,
          'uncertain' => HomeAction.uncertainObservation,
          _ => HomeAction.observe,
        });
        expect(f.next.reason, isNotEmpty);
        expect(f.history.writes, 0);
        f.state.dispose();
        await api.init();
      }, () => o.isolated(f.transport));
    });
  }
  test(
    'embedded urgent outranks lower standalone guidance and clinician action',
    () async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.ready();
        final controller = ClinicalController(
          api,
          repository: _EmbeddedUrgent(),
        );
        await controller.refresh();
        final next = HomeNextAction.select(
          clinical: controller,
          observations: f.state.observations,
          hasExperiment: true,
        );
        expect(next.action, HomeAction.safety);
        controller.dispose();
        f.state.dispose();
        await api.init();
      }, () => o.isolated(f.transport));
    },
  );
  for (final invalid in [
    'timestamp',
    'moment',
    'duplicate',
    'unsupported_metric',
  ]) {
    test(
      'Home rejects $invalid contract rather than fabricate facts',
      () async {
        final r = HomeRepo()..data = h.snapshot();
        final row = (r.data['journal'] as List).first as Map;
        switch (invalid) {
          case 'timestamp':
            row['created_at'] = '2026-02-31T10:00:00';
          case 'moment':
            row['time_of_day'] = 'future';
          case 'duplicate':
            r.data['journal'] = [row, row];
          case 'unsupported_metric':
            row['measurement_source'] = 'none';
        }
        final ctl = HomeController(r);
        expect(await ctl.refresh(), false);
        expect(ctl.current, isNull);
        ctl.dispose();
      },
    );
  }
  for (final withName in [true, false]) {
    testWidgets('verified greeting uses optional name=$withName', (t) async {
      final f = Fixture()..name = withName ? 'Verified Amr' : '  ';
      await http.runWithClient(() async {
        await f.ready();
        await mount(t, f);
        expect(
          find.text(withName ? 'Welcome, Verified' : 'Welcome'),
          findsOneWidget,
        );
        await finish(t, f);
      }, () => o.isolated(f.transport));
    });
  }
  testWidgets(
    'report-only activity never fabricates Home completion scores or dates',
    (t) async {
      final f = Fixture();
      f.history.data = [ObservationRecord.fromApi(o.record(), owner: 'a')];
      await http.runWithClient(() async {
        await f.ready();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('homePersonalStatus')));
        expect(
          find.text('No confirmed tracking measurement recorded today (UTC)'),
          findsOneWidget,
        );
        expect(
          find.text('Tracking reference: 0 of 5 confirmed UTC days'),
          findsOneWidget,
        );
        await reveal(
          t,
          find.byKey(const ValueKey('home-record-server-record')),
        );
        expect(find.text('2026-10-12 12:00:00 UTC · Morning'), findsOneWidget);
        expect(
          find.text('Report-only observation · No recorded measurements'),
          findsOneWidget,
        );
        expect(find.textContaining('Hydration:'), findsNothing);
        expect(find.textContaining('Completed'), findsNothing);
        expect(find.textContaining('improved by'), findsNothing);
        expect(f.history.writes, 0);
        await finish(t, f);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets('new user empty activity is distinct from unknown data', (
    t,
  ) async {
    final f = Fixture();
    await http.runWithClient(() async {
      await f.ready();
      await mount(t, f);
      await reveal(t, find.byKey(const Key('homeRecentActivity')));
      expect(
        find.text('No saved observations in server history.'),
        findsOneWidget,
      );
      expect(find.text('Saved observation'), findsNothing);
      await finish(t, f);
    }, () => o.isolated(f.transport));
  });
  testWidgets(
    'partial failure retains independent verified history and retry reads only',
    (t) async {
      final f = Fixture();
      f.home.fail = true;
      f.history.data = [ObservationRecord.fromApi(o.record(), owner: 'a')];
      await http.runWithClient(() async {
        await f.ready();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('homePersonalStatus')));
        expect(find.textContaining('Home unavailable'), findsOneWidget);
        await reveal(
          t,
          find.byKey(const ValueKey('home-record-server-record')),
        );
        expect(find.text('Saved observation'), findsOneWidget);
        f.home.fail = false;
        await reveal(t, find.byKey(const Key('homeRefresh')));
        await t.tap(find.byKey(const Key('homeRefresh')));
        await t.pumpAndSettle();
        expect(f.state.home.current, isNotNull);
        expect(f.history.writes, 0);
        expect(f.home.calls, 2);
        await finish(t, f);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'stale activity and safety remain labelled; metric facts are suppressed',
    (t) async {
      final f = Fixture();
      f.home.data = h.snapshot();
      f.history.data = [ObservationRecord.fromApi(o.record(), owner: 'a')];
      f.clinical.status = 'urgent';
      await http.runWithClient(() async {
        await f.ready();
        f.state.home.markStale();
        f.state.baseline.markStale();
        f.state.observations.markHistoryStale();
        f.state.clinical.markStale();
        await mount(t, f);
        expect(find.textContaining('Previously retrieved'), findsWidgets);
        expect(f.next.action, HomeAction.safety);
        await reveal(t, find.byKey(const Key('homePersonalStatus')));
        expect(find.text('Day 4 of 14'), findsNothing);
        expect(
          find.textContaining('Previously retrieved Home'),
          findsOneWidget,
        );
        await reveal(
          t,
          find.byKey(const ValueKey('home-record-server-record')),
        );
        expect(find.text('Previously retrieved record'), findsOneWidget);
        await finish(t, f);
      }, () => o.isolated(f.transport));
    },
  );
  testWidgets(
    'urgent and actionable clinician sources appear before next action',
    (t) async {
      final f = Fixture();
      f.clinical.status = 'urgent';
      f.clinical.action = c.decision();
      await http.runWithClient(() async {
        await f.ready();
        await mount(t, f);
        expect(
          find.text('Urgent medical assessment recommended'),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.emergency_outlined), findsOneWidget);
        await reveal(t, find.text('Clinician review'));
        expect(
          find.textContaining('Synthetic clinician instruction'),
          findsOneWidget,
        );
        await reveal(t, find.byKey(const Key('homeNextAction')));
        expect(f.next.action, HomeAction.safety);
        await finish(t, f);
      }, () => o.isolated(f.transport));
    },
  );
  for (final action in [
    'observe',
    'history',
    'guidance',
    'products',
    'profile',
    'context',
    'experiment',
  ]) {
    testWidgets('Home action $action reaches supported destination', (t) async {
      final f = Fixture();
      if (action == 'experiment') f.home.data = h.snapshot();
      await http.runWithClient(
        () async {
          await f.ready();
          await mount(t, f);
          final key = switch (action) {
            'observe' => 'homeObserve',
            'history' => 'homeHistory',
            'guidance' => 'clinicalDetails',
            'products' => 'homeProducts',
            'profile' => 'homeProfile',
            'context' => 'homeContext',
            _ => '',
          };
          final finder = action == 'experiment'
              ? find.text('Open experiment')
              : find.byKey(Key(key));
          await reveal(t, finder);
          await t.tap(finder);
          await t.pumpAndSettle();
          switch (action) {
            case 'observe':
              expect(find.byType(CameraScreen), findsOneWidget);
            case 'history':
              expect(find.byType(TimelineScreen), findsOneWidget);
            case 'guidance':
              expect(find.byType(ClinicalStatusScreen), findsOneWidget);
            case 'products':
              expect(f.state.selectedTab, 2);
            case 'profile':
              expect(f.state.selectedTab, 5);
            case 'context':
              expect(find.byType(ContextScreen), findsOneWidget);
            case 'experiment':
              expect(f.state.selectedTab, 1);
          }
          expect(f.history.writes, 0);
          await finish(t, f);
        },
        () => o.isolated((r) async {
          if (r.url.path.contains('/context/')) {
            return o.jsonResponse({
              'date': DateTime.now().toUtc().toIso8601String().split('T').first,
              'unusual_conditions': null,
              'cycle_day': null,
              'recorded': false,
            });
          }
          return f.transport(r);
        }),
      );
    });
  }
  testWidgets(
    'initial partial loading exposes observation access and independent status',
    (t) async {
      final f = Fixture();
      f.home.pending = Completer();
      await http.runWithClient(() async {
        await f.login();
        final waiting = f.state.refreshPatientHome(
          generation: api.sessionGeneration,
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(body: HomeTab(state: f.state)),
          ),
        );
        await t.pump();
        await t.pump();
        await reveal(t, find.byKey(const Key('homePersonalStatus')));
        expect(find.text('Loading tracking status…'), findsOneWidget);
        expect(
          find.text('Tracking reference: 0 of 5 confirmed UTC days'),
          findsOneWidget,
        );
        await reveal(t, find.byKey(const Key('homeObserve')));
        expect(
          t
              .widget<FilledButton>(find.byKey(const Key('homeObserve')))
              .onPressed,
          isNotNull,
        );
        f.home.pending!.complete(f.home.data);
        await waiting;
        await t.pumpAndSettle();
        await finish(t, f);
      }, () => o.isolated(f.transport));
    },
  );
  for (final source in ['home', 'baseline', 'history']) {
    testWidgets(
      'bounded $source timeout can retry reads and rejects late results',
      (t) async {
        final f = Fixture();
        await http.runWithClient(() async {
          await f.ready();
          Future<bool> waiting;
          switch (source) {
            case 'home':
              f.home.pending = Completer();
              waiting = f.state.home.refresh();
            case 'baseline':
              f.baseline.pending = Completer();
              waiting = f.state.baseline.refresh();
            default:
              f.history.pending = Completer();
              waiting = f.state.observations.loadHistory(
                generation: api.sessionGeneration,
              );
          }
          await t.pump(const Duration(seconds: 21));
          expect(await waiting, false);
          switch (source) {
            case 'home':
              f.home.pending!.complete(h.snapshot());
              f.home.pending = null;
              expect(f.state.home.current, isNull);
              expect(await f.state.home.refresh(), true);
            case 'baseline':
              f.baseline.pending!.complete(b.snapshot(5));
              f.baseline.pending = null;
              expect(f.state.baseline.available, false);
              expect(await f.state.baseline.refresh(), true);
            default:
              f.history.pending!.complete([
                ObservationRecord.fromApi(o.record(), owner: 'a'),
              ]);
              f.history.pending = null;
              expect(f.state.observations.historyError, isNotNull);
              expect(
                await f.state.observations.loadHistory(
                  generation: api.sessionGeneration,
                ),
                true,
              );
          }
          expect(f.history.writes, 0);
          f.state.dispose();
          await api.init();
        }, () => o.isolated(f.transport));
      },
    );
  }
  for (final path in ['home', 'baseline', 'checkins']) {
    for (final status in [401, 403, 503]) {
      test('isolated $path HTTP $status never becomes positive data', () async {
        final f = Fixture();
        await http.runWithClient(
          () async {
            await f.login();
            await expectLater(switch (path) {
              'home' => api.getHome(),
              'baseline' => api.getBaseline(),
              _ => api.getPatientObservations(
                generation: api.sessionGeneration,
              ),
            }, throwsException);
            expect(api.isAuthenticated, status != 401);
            f.state.dispose();
            await api.init();
          },
          () => o.isolated((r) async {
            if (r.url.path.endsWith('/$path')) {
              return o.jsonResponse({
                'sensitive': 'must not be displayed',
              }, status);
            }
            return f.transport(r);
          }),
        );
      });
    }
  }
  for (final end in ['logout', 'switch']) {
    test(
      'pending Home baseline history reject $end and old refresh callbacks',
      () async {
        final f = Fixture();
        await http.runWithClient(() async {
          await f.ready();
          final generation = api.sessionGeneration;
          f.home.pending = Completer();
          f.baseline.pending = Completer();
          f.history.pending = Completer();
          final waiting = f.state.refreshPatientHome(generation: generation);
          if (end == 'switch') {
            f.owner = 'b';
            await f.login();
          } else {
            await api.init();
          }
          f.home.pending!.complete(h.snapshot());
          f.baseline.pending!.complete(b.snapshot(5));
          f.history.pending!.complete([
            ObservationRecord.fromApi(o.record(), owner: 'a'),
          ]);
          await waiting;
          expect(f.state.home.current, isNull);
          expect(f.state.baseline.completedDays, isNull);
          expect(f.state.observations.rows, isNull);
          final reads = f.home.calls;
          await f.state.refreshPatientHome(generation: generation);
          expect(f.home.calls, reads);
          f.state.dispose();
          await api.init();
        }, () => o.isolated(f.transport));
      },
    );
  }
  for (final path in ['home', 'baseline', 'checkins']) {
    test('late old $path 401 cannot end reused-token newer session', () async {
      final f = Fixture();
      final old = Completer<http.Response>();
      bool hold = false;
      await http.runWithClient(
        () async {
          await f.login();
          hold = true;
          final result = switch (path) {
            'home' => api.getHome(),
            'baseline' => api.getBaseline(),
            _ => api.getPatientObservations(generation: api.sessionGeneration),
          };
          final assertion = expectLater(result, throwsException);
          f.owner = 'b';
          await f.login();
          old.complete(o.jsonResponse({}, 401));
          await assertion;
          expect(api.isAuthenticated, true);
          expect(api.observationOwner, 'b');
          f.state.dispose();
          await api.init();
        },
        () => o.isolated((r) async {
          if (hold && r.url.path.endsWith('/$path')) return old.future;
          return f.transport(r);
        }),
      );
    });
  }
  test('overlapping Home refresh keeps only latest result', () async {
    final f = Fixture();
    await http.runWithClient(() async {
      await f.ready();
      final pending = Completer<Map<String, dynamic>>();
      f.home.pending = pending;
      final old = f.state.home.refresh();
      f.home.pending = null;
      await f.state.home.refresh();
      pending.complete(h.snapshot());
      expect(await old, false);
      expect(f.state.home.current!['experiment'], isNull);
      f.state.dispose();
      await api.init();
    }, () => o.isolated(f.transport));
  });
  testWidgets(
    'retained Home navigation callbacks cannot open old session destinations',
    (t) async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.ready();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('homeObserve')));
        final callback = t
            .widget<FilledButton>(find.byKey(const Key('homeObserve')))
            .onPressed!;
        await api.init();
        callback();
        await t.pump();
        expect(find.byType(CameraScreen), findsNothing);
        expect(f.state.observations.rows, isNull);
        await finish(t, f);
      }, () => o.isolated(f.transport));
    },
  );
  for (final scenario in [
    'empty',
    'history',
    'experiment',
    'urgent',
    'clinician',
    'unknown',
  ]) {
    testWidgets('dynamic primary action navigates correctly for $scenario', (
      t,
    ) async {
      final f = Fixture();
      if (scenario == 'history') {
        f.history.data = [ObservationRecord.fromApi(o.record(), owner: 'a')];
      }
      if (scenario == 'experiment') f.home.data = h.snapshot();
      if (scenario == 'urgent') f.clinical.status = 'urgent';
      if (scenario == 'clinician') f.clinical.action = c.decision();
      if (scenario == 'unknown') f.clinical.status = 'future_status';
      await http.runWithClient(() async {
        await f.ready();
        await mount(t, f);
        await reveal(t, find.byKey(const Key('homeNextActionButton')));
        await t.tap(find.byKey(const Key('homeNextActionButton')));
        await t.pumpAndSettle();
        if (scenario == 'empty') {
          expect(find.byType(CameraScreen), findsOneWidget);
        } else if (scenario == 'history') {
          expect(find.byType(TimelineScreen), findsOneWidget);
        } else if (scenario == 'experiment') {
          expect(f.state.selectedTab, 1);
        } else {
          expect(find.byType(ClinicalStatusScreen), findsOneWidget);
        }
        expect(f.history.writes, 0);
        await finish(t, f);
      }, () => o.isolated(f.transport));
    });
  }
  for (final source in ['manual', 'image_proxy']) {
    testWidgets(
      'recent $source values keep source labels and no improvement claim',
      (t) async {
        final f = Fixture();
        f.history.data = [
          ObservationRecord.fromApi({
            ...o.record(),
            'observation': null,
            'ai_vision_analysis': {'measurement_source': source},
            'hydration_score': 80,
            'redness_score': 10,
            'texture_score': 75,
          }, owner: 'a'),
        ];
        await http.runWithClient(() async {
          await f.ready();
          await mount(t, f);
          await reveal(
            t,
            find.byKey(const ValueKey('home-record-server-record')),
          );
          expect(
            find.text(
              source == 'manual'
                  ? 'User-entered tracking measurements'
                  : 'Nonclinical image estimates · Not a diagnosis',
            ),
            findsOneWidget,
          );
          expect(
            find.text('Hydration: 80 · Redness: 10 · Texture: 75'),
            findsOneWidget,
          );
          expect(find.textContaining('health score'), findsNothing);
          expect(f.state.home.current!['today_checked_in'], false);
          await finish(t, f);
        }, () => o.isolated(f.transport));
      },
    );
  }
  testWidgets('recent activity preserves server order and remains bounded', (
    t,
  ) async {
    final f = Fixture();
    f.history.data = [
      for (final id in ['newest', 'second', 'older'])
        ObservationRecord.fromApi(o.record(id: id), owner: 'a'),
    ];
    await http.runWithClient(() async {
      await f.ready();
      await mount(t, f);
      await reveal(t, find.byKey(const Key('homeRecentActivity')));
      expect(find.byKey(const ValueKey('home-record-newest')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-record-second')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-record-older')), findsNothing);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('home-record-newest'))).dy,
        lessThan(
          t.getTopLeft(find.byKey(const ValueKey('home-record-second'))).dy,
        ),
      );
      await finish(t, f);
    }, () => o.isolated(f.transport));
  });
  test(
    'previous UTC-day baseline cannot claim today or current reference',
    () async {
      final f = Fixture();
      await http.runWithClient(() async {
        await f.ready();
        f.state.baseline.retrievedAt = DateTime.now().toUtc().subtract(
          const Duration(days: 1),
        );
        expect(f.state.baseline.available, false);
        expect(f.state.baseline.completedDays, isNull);
        expect(f.state.baseline.metrics, isEmpty);
        f.state.dispose();
        await api.init();
      }, () => o.isolated(f.transport));
    },
  );
  for (final dark in [false, true]) {
    for (final reduced in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'actual Home dark=$dark reduced=$reduced text=$scale is readable and English',
          (t) async {
            final f = Fixture();
            f.history.data = [
              ObservationRecord.fromApi(o.record(), owner: 'a'),
            ];
            await http.runWithClient(() async {
              await f.ready();
              t.view.physicalSize = const Size(320, 800);
              t.view.devicePixelRatio = 1;
              addTearDown(t.view.resetPhysicalSize);
              addTearDown(t.view.resetDevicePixelRatio);
              await mount(t, f, dark: dark, scale: scale, reduced: reduced);
              final semantics = t.ensureSemantics();
              await reveal(t, find.byKey(const Key('homePersonalStatus')));
              final transition = t.widget<AnimatedSize>(
                find.descendant(
                  of: find.byKey(const Key('homePersonalStatus')),
                  matching: find.byType(AnimatedSize),
                ),
              );
              expect(
                transition.duration,
                reduced ? Duration.zero : const Duration(milliseconds: 180),
              );
              expect(
                Theme.of(
                  t.element(find.byKey(const Key('homePersonalStatus'))),
                ).colorScheme.surface,
                dark ? const Color(0xFF24272D) : const Color(0xFFFFFCF8),
              );
              // Return to top so the source-label assertion remains visible.
              await t.drag(find.byType(ListView).first, const Offset(0, 4000));
              await t.pumpAndSettle();
              expect(find.text('Safety Engine'), findsOneWidget);
              await reveal(t, find.byKey(const Key('homeObserve')));
              expect(
                t
                    .getSemantics(find.byKey(const Key('homeObserve')))
                    .getSemanticsData()
                    .label,
                contains('Start observation'),
              );
              await reveal(t, find.byKey(const Key('homeRefresh')));
              expect(t.takeException(), isNull);
              expect(find.textContaining('Language'), findsNothing);
              expect(f.history.writes, 0);
              semantics.dispose();
              await finish(t, f);
            }, () => o.isolated(f.transport));
          },
        );
      }
    }
  }
}

class _EmbeddedUrgent implements ClinicalRepository {
  @override
  Future<SafetyAssessment> readSafety(int generation) async =>
      SafetyAssessment.fromApi(c.safety());
  @override
  Future<ClinicianReview> readReview(int generation) async =>
      ClinicianReview.fromApi(
        c.review(
          action: c.decision(),
          state: 'reviewed',
          evaluation: c.safety(status: 'urgent'),
        ),
        owner: 'a',
      );
}
