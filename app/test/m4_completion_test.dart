import 'dart:async';
import 'package:http/testing.dart';
import 'observation_test.dart' as o;
import 'package:dermaire_app/experiments/experiment_contract.dart';
import 'package:dermaire_app/experiments/metric_contract.dart';
import 'package:dermaire_app/experiments/experiment_evidence.dart';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/routine/adherence_evidence.dart';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'experiment_authority_test.dart' as e;
import 'routine_authority_test.dart' as r;
import 'm4_adherence_test.dart' as a;
import 'product_authority_test.dart' as p;

Map<String, dynamic> saved() => {
  ...e.evaluation(),
  'result': {
    ...e.evaluation()['result'] as Map,
    'metric_contract': {
      'schema_version': 1,
      'metric': 'texture',
      'unit': 'score_0_to_100',
      'delta_unit': 'score_points',
      'source': 'manual',
      'direction': 'higher_is_better',
      'aggregation': 'within_UTC_day_mean_then_equal_day_mean',
      'evaluation_algorithm': 'experiment_v2_rules_1',
      'measurement_algorithm_versions': ['manual_v1'],
      'measurement_algorithm_provenance': 'recorded',
      'clinical_measurement': false,
    },
    'observed_change': {
      'metric': 'texture',
      'baseline_mean': 0,
      'experiment_mean': null,
      'delta_points': null,
    },
    'comparison': {
      'measurement_source': 'manual',
      'baseline_days': 0,
      'experiment_days': 0,
    },
    'adherence': {
      'expected_slots': 10,
      'reported_slots': 4,
      'followed_slots': 3,
      'expected_status': 'completed',
      'source': 'user_reported',
      'coverage': .4,
      'followed_fraction': .3,
    },
    'provenance': {
      'source': 'server_derived',
      'algorithm': 'experiment_v2_rules_1',
      'definition_snapshot': {
        'product': {'id': 'product'},
        'expected': {'id': 'entry'},
        'frozen_at': '2026-10-02T12:00:00',
      },
      'experiment_checkins': [
        {
          'id': 'original-report',
          'created_at': '2026-10-02T12:00:00',
          'source': 'manual',
        },
      ],
      'adherence': [],
      'contexts': [],
    },
  },
};
Map<String, dynamic> active() => {
  ...e.experiment('active'),
  'result': saved(),
  'definition_snapshot': {
    'engine_version': 2,
    'source': 'user_configured',
    'product': {'id': 'product', 'name': 'Original name'},
    'expected': {
      'id': 'entry',
      'product_id': 'product',
      'schedule': 'AM',
      'active': true,
    },
    'baseline': {
      'start': '2026-09-01',
      'end_exclusive': '2026-10-02',
      'checkins': [
        {
          'id': 'baseline-id',
          'source': 'manual',
          'created_at': '2026-09-20T00:00:00',
        },
      ],
    },
    'frozen_at': '2026-10-02T12:00:00',
  },
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final key in ['unusual_days', 'product_changed_after_activation']) {
    test('malformed confounder $key is not medical evidence', () {
      final v = saved();
      v['result']['confounders'] = {key: 'invented'};
      expect(ExperimentContract.result(v, 'experiment'), false);
    });
  }
  test(
    'optional metric contract distinguishes zero null and known units from legacy absence',
    () {
      final value = saved();
      expect(ExperimentContract.result(value, 'experiment'), true);
      final m = ExperimentMetricContract.parse(value['result']);
      expect(m!.source, 'manual');
      expect(m.versions, ['manual_v1']);
      expect(value['result']['observed_change']['baseline_mean'], 0);
      expect(value['result']['observed_change']['experiment_mean'], isNull);
      expect(ExperimentContract.result(e.evaluation(), 'experiment'), true);
    },
  );
  for (final field in [
    'schema_version',
    'metric',
    'unit',
    'delta_unit',
    'source',
    'direction',
    'aggregation',
    'evaluation_algorithm',
    'clinical_measurement',
    'measurement_algorithm_versions',
    'measurement_algorithm_provenance',
  ]) {
    test('unsupported metric $field cannot become current evaluation', () {
      final value = saved();
      value['result']['metric_contract'][field] = 'unsupported';
      expect(ExperimentContract.result(value, 'experiment'), false);
    });
  }
  for (final field in [
    'reported_slots',
    'followed_slots',
    'coverage',
    'followed_fraction',
  ]) {
    test('inconsistent saved aggregate $field rejected', () {
      final v = saved();
      v['result']['adherence'][field] = field.endsWith('slots') ? 11 : .9;
      expect(ExperimentContract.result(v, 'experiment'), false);
    });
  }
  test('mixed image algorithms cannot carry directional improvement label', () {
    final v = saved();
    v['result']['label'] = 'likely_associated_improvement';
    v['result']['metric_contract']['source'] = 'image_proxy';
    v['result']['comparison']['measurement_source'] = 'image_proxy';
    v['result']['metric_contract']['measurement_algorithm_provenance'] =
        'mixed';
    v['result']['metric_contract']['measurement_algorithm_versions'] = [
      'one',
      'two',
    ];
    expect(ExperimentContract.result(v, 'experiment'), false);
    v['result']['label'] = 'insufficient_evidence';
    expect(ExperimentContract.result(v, 'experiment'), true);
  });
  test(
    'production remote controller fails new unsupported contract closed',
    () async {
      var value = active();
      await http.runWithClient(
        () async {
          await p.login();
          final c = ExperimentController(RemoteExperimentRepository());
          await c.refresh();
          expect(c.stale, false);
          value = active();
          value['result']['result']['metric_contract']['unit'] =
              'fraction_0_to_1';
          await c.refresh();
          expect(c.stale, true);
          expect(c.error, isNotNull);
          c.dispose();
        },
        () => MockClient((req) async {
          expect(req.url.host, 'flutter-tests.invalid');
          if (req.url.path.endsWith('/auth/login')) return p.auth();
          if (req.url.path.endsWith('/users/me')) return o.user('patient-1');
          expect(req.method, 'GET');
          return http.Response(jsonEncode([value]), 200);
        }),
      );
    },
  );
  test(
    'routine stale boundary rejects earlier read without manufacturing adherence',
    () async {
      final repo = r.Repository()..entries = [r.entry()];
      final c = RoutineController(repo);
      await c.refresh();
      repo.pending = Completer();
      final read = c.refresh();
      c.markReadStale();
      repo.pending!.complete([
        {...r.entry(), 'product_name': 'Late renamed'},
      ]);
      await read;
      expect(c.stale, true);
      expect(c.entries!.single['product_name'], 'Inventory');
      expect(c.history, isEmpty);
      c.dispose();
    },
  );
  test(
    'experiment stale boundary rejects earlier read and preserves unresolved identity',
    () async {
      final repo = e.Repository()..rows = [active()];
      final c = ExperimentController(repo);
      await c.refresh();
      c.uncertain.add('experiment/evaluate');
      repo.pending = Completer();
      final read = c.refresh();
      c.markReadStale();
      repo.pending!.complete([e.experiment()]);
      await read;
      expect(c.stale, true);
      expect(c.rows!.single['status'], 'active');
      expect(c.uncertain, contains('experiment/evaluate'));
      c.dispose();
    },
  );
  for (final state in ['completed', 'skipped', 'unknown', 'historical']) {
    testWidgets('slot $state is not inferred from configuration', (t) async {
      final entry = r.entry();
      final history = state == 'unknown'
          ? <Map<String, dynamic>>[]
          : [
              {
                ...a.event(),
                'status': state == 'historical' ? 'completed' : state,
                'configuration_snapshot': {
                  ...r.entry(),
                  if (state == 'historical') 'product_id': 'old-product',
                },
              },
            ];
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AdherenceSlotEvidence(
              entry: entry,
              history: history,
              day: '2026-10-03',
              slot: 'AM',
              stale: false,
            ),
          ),
        ),
      );
      expect(
        find.textContaining(
          state == 'unknown'
              ? 'Adherence unknown'
              : state == 'historical'
              ? 'Historical configuration report'
              : ': $state',
        ),
        findsOneWidget,
      );
      if (state == 'historical') {
        expect(find.textContaining('old-product'), findsOneWidget);
      }
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'saved evidence dark=$dark 320px200 reduced preserves units IDs unknowns',
      (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Column(
                  children: [
                    FrozenExperimentSummary(row: active()),
                    ExperimentEvidenceDetails(result: saved()['result']),
                  ],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          find.textContaining('Frozen product: Original name'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Frozen baseline record: baseline-id'),
          findsOneWidget,
        );
        expect(find.textContaining('score_points'), findsOneWidget);
        expect(
          find.textContaining('6 slots remain unknown, not skipped'),
          findsOneWidget,
        );
        expect(find.textContaining('Baseline value: 0'), findsOneWidget);
        expect(find.textContaining('original-report'), findsOneWidget);
        expect(
          find.textContaining('Saved frozen references: product product'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'routine resume re-reads current data without automatic adherence',
    (t) async {
      final repo = _Reads()..entries = [r.entry()];
      await t.pumpWidget(MaterialApp(home: RoutineScreen(repository: repo)));
      await t.pumpAndSettle();
      final reads = repo.reads;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      repo.entries = [];
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(repo.reads, greaterThan(reads));
      expect(repo.writes, 0);
      expect(find.text('No routine configured'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('routine repository rebind prevents previous entry returning', (
    t,
  ) async {
    final old = r.Repository()..pending = Completer();
    final next = r.Repository()..entries = [];
    await t.pumpWidget(MaterialApp(home: RoutineScreen(repository: old)));
    await t.pump();
    await t.pumpWidget(MaterialApp(home: RoutineScreen(repository: next)));
    await t.pumpAndSettle();
    old.pending!.complete([r.entry()]);
    await t.pumpAndSettle();
    expect(find.text('No routine configured'), findsOneWidget);
    expect(find.textContaining('Inventory ·'), findsNothing);
  });
}

class _Reads extends r.Repository {
  int reads = 0, writes = 0;
  @override
  Future<List<Map<String, dynamic>>> read(String resource) {
    reads++;
    return super.read(resource);
  }

  @override
  Future<Map<String, dynamic>> write(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) {
    writes++;
    return super.write(resource, payload, method: method);
  }
}
