import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:dermaire_app/psm/psm_models.dart';
import 'package:dermaire_app/psm/psm_controller.dart';
import 'package:dermaire_app/psm/psm_screen.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/capture/capture_history_screen.dart';
import 'package:dermaire_app/clinical/clinical_ui.dart';
import 'package:dermaire_app/observations/observation_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'guided_capture_test.dart' as g;
import 'observation_test.dart' as o;
import 'clinical_status_test.dart' as c;
import 'private_capture_history_test.dart' as h;

final api = ApiService.instance;
const generated = '2026-10-13T12:00:00Z';
Map<String, dynamic> fresh([String state = 'fresh']) => {
  'state': state,
  'latest_at': state == 'missing' ? null : generated,
  'age_days': state == 'missing'
      ? null
      : state == 'stale'
      ? 20
      : 0,
};
Map<String, dynamic> evidence({
  String source = 'checkin',
  String kind = 'user_reported',
  String id = 'report-id',
}) => {
  'source': source,
  'kind': kind,
  'id': id,
  'category': kind == 'user_reported' ? 'patient_reported' : 'system_observed',
  'recorded_at': generated,
  'fields': ['observation.user_reported.overall_change'],
};
Map<String, dynamic> finding() => {
  'code': 'recent_self_report',
  'subject': 'overall_change',
  'direction': 'same',
  'statement': 'Synthetic server-reported trend.',
  'strength': 'limited',
  'rule': 'report-6-days_latest-3-agree',
  'category': 'deterministic_derived',
  'evidence': [evidence()],
  'evidence_count': 1,
  'latest_evidence_at': generated,
  'confidence': 'limited',
  'caveats': ['Observational only, not diagnosis or cause.'],
  'reference_value': null,
  'recent_value': null,
  'threshold': null,
};
Map<String, dynamic> payload({
  String owner = 'a',
  String status = 'insufficient_data',
  bool partial = false,
  bool findings = false,
}) {
  final latest = g.measurement(id: 'capture-id');
  final historical = {
    'id': 'earlier-estimate',
    'capture_id': 'earlier-capture',
    'algorithm_version': 'measurement-1.0',
    'metrics': g.measurement(id: 'earlier-capture')['metrics'],
    'quality_reference': g.quality(),
    'received_at': generated,
    'measured_at': '2026-10-12T14:01:00Z',
    'freshness': fresh('stale'),
  };
  return {
    'schema_version': 2,
    'contract_version': 'personal-skin-model-2.0',
    'derivation_version': 'psm-v2.0',
    'generated_at': generated,
    'status': status,
    'statement': status == 'no_data'
        ? 'No authoritative skin observations yet; start tracking.'
        : status == 'stale'
        ? 'Current trajectory is unknown; record a fresh check-in.'
        : 'Synthetic deterministic model statement.',
    'strength': findings ? 'limited' : 'none',
    'changing': findings ? [finding()] : [],
    'stable': [],
    'associations': [],
    'sufficiency': {
      'confirmed_days': status == 'no_data' ? 0 : 6,
      'report_days': status == 'no_data' ? 0 : 6,
      'measurement_days': 0,
      'excluded_checkins': 2,
      'proxy_measurement_days': status == 'no_data' ? 0 : 1,
      'latest_proxy_measurement_at': status == 'no_data' ? null : generated,
      'latest_evidence_at': status == 'no_data' ? null : generated,
      'age_days': status == 'no_data'
          ? null
          : status == 'stale'
          ? 20
          : 0,
      'recency': status == 'no_data'
          ? 'missing'
          : status == 'stale'
          ? 'stale'
          : 'fresh',
      'baseline_ready': false,
      'reasons': ['Synthetic missing-evidence reason.'],
    },
    'profile': {
      'available': !partial,
      'primary_goals': partial ? [] : ['Improve routine tracking'],
      'evidence': partial ? [] : [evidence(source: 'profile', id: owner)],
    },
    'products': [],
    'limitations': ['Not a diagnosis or clinical certainty.'],
    'unknowns': ['Actual exposure and causation are unknown.'],
    'safety': c.safety(status: 'urgent'),
    'assistant_layer': {
      'category': 'ai_inferred',
      'authoritative': false,
      'included': false,
    },
    'sources': partial || status == 'no_data'
        ? {}
        : {
            'profile': {
              'category': 'patient_reported',
              'skin_type': 'oily',
              'skin_concerns': ['dryness'],
              'freshness': fresh(),
            },
            'history': {
              'category': 'patient_reported',
              'freshness': fresh(),
              'recent_reports': [
                {
                  'id': 'report-id',
                  'recorded_at': generated,
                  'report': {
                    'overall_change': 'same',
                    'symptoms': ['dryness'],
                    'routine_status': null,
                  },
                  'freshness': fresh(),
                },
              ],
            },
            'measurements': {
              'category': 'deterministic_derived',
              'latest': latest,
              'latest_measured': historical,
              'trend_status': 'not_comparable',
              'freshness': fresh(),
            },
            'experiments': [
              {
                'id': 'experiment-id',
                'category': 'patient_reported',
                'status': 'completed',
                'change_type': 'start_entry',
                'product_id': 'product-id',
                'start_date': generated,
                'target_days': 7,
                'stopped_at': generated,
                'baseline_window': {},
                'evaluation': {
                  'id': 'evaluation-id',
                  'category': 'deterministic_derived',
                  'label': 'insufficient_evidence',
                  'strength': 'insufficient',
                  'evidence_count': null,
                  'statement':
                      'Experiment outcome is an association, not evidence of cause.',
                  'freshness': fresh('stale'),
                  'caveats': [
                    'Frozen evaluation; subsequent edits do not reevaluate it.',
                  ],
                  'comparison': {},
                  'adherence': {},
                  'confounders': {},
                  'evaluation_window': {},
                },
              },
            ],
            'doctor': {
              'category': 'clinician_authored',
              'state': 'reviewed',
              'freshness': fresh(),
              'current_decision': {
                'id': 'decision-id',
                'category': 'clinician_authored',
                'state': 'reviewed',
                'recommendation': 'track',
                'rationale': 'Synthetic clinician rationale.',
                'recorded_at': generated,
                'freshness': fresh(),
                'diverges_from_current_safety': true,
                'lower_than_current_safety': true,
              },
              'history': [],
              'notes': [],
            },
          },
    'summaries': {},
  };
}

class Fixture extends h.Fixture {
  Object? body;
  int status = 200;
  bool psmOffline = false;
  Completer<http.Response>? pendingPsm;
  @override
  Future<http.Response> transport(http.Request r) async {
    if (r.url.path.endsWith('/personal-skin-model')) {
      requests.add(r);
      expectSync(r.method, 'GET');
      expectSync(r.url.query, isEmpty);
      expectSync(r.headers['Authorization'], 'Bearer reused-synthetic-token');
      if (psmOffline) throw http.ClientException('Synthetic offline');
      if (pendingPsm != null) return pendingPsm!.future;
      return o.jsonResponse(body ?? payload(owner: owner), status);
    }
    if (r.url.path.endsWith('/experiments') ||
        r.url.path.endsWith('/checkins')) {
      return o.jsonResponse([]);
    }
    return super.transport(r);
  }
}

class FakePsmRepository implements PsmRepository {
  late PersonalSkinModel value;
  Future<PersonalSkinModel> Function()? pending;
  int reads = 0;
  @override
  Future<PersonalSkinModel> read(int generation) async {
    reads++;
    return pending == null ? value : pending!();
  }
}

Future<void> mount(
  WidgetTester t,
  Fixture f, {
  bool dark = false,
  bool reduced = false,
  double scale = 1,
  double width = 390,
  PsmRepository? repository,
}) => h.mount(
  t,
  f,
  PersonalSkinModelScreen(state: f.state, repository: repository),
  dark: dark,
  reduced: reduced,
  scale: scale,
  width: width,
);
Future<void> scrollTo(
  WidgetTester t,
  Finder finder, {
  double step = 250,
}) async {
  await t.scrollUntilVisible(
    finder,
    step,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 200,
  );
  await t.pumpAndSettle();
  await t.ensureVisible(finder);
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
  test(
    'actual v2 response maps source, version, UTC and coverage without clinical inference',
    () {
      final m = PersonalSkinModel.fromApi(payload(findings: true), owner: 'a');
      expect(m.contract, 'personal-skin-model-2.0');
      expect(m.derivation, 'psm-v2.0');
      expect(m.generatedAt, DateTime.utc(2026, 10, 13, 12));
      expect(m.coverage.recordDays, 6);
      expect(m.coverage.trackingDays, 0);
      expect(m.coverage.proxyDays, 1);
      expect(m.profile!.goals, ['Improve routine tracking']);
      expect(m.reports.single.routine, isNull);
      expect(m.changing.single.evidence.single.kind, 'user_reported');
      expect(m.clinician!.rationale, 'Synthetic clinician rationale.');
      expect(m.partialIssues, isEmpty);
      expect(() => m.unknowns.clear(), throwsUnsupportedError);
      expect(() => m.changing.clear(), throwsUnsupportedError);
    },
  );
  for (final state in [
    'no_data',
    'insufficient_data',
    'no_meaningful_change',
    'meaningful_change',
    'stale',
  ]) {
    test('actual PSM status $state remains as reported', () {
      final m = PersonalSkinModel.fromApi(payload(status: state), owner: 'a');
      expect(m.status, state);
      if (state == 'no_data') expect(m.coverage.reportDays, 0);
    });
  }
  for (final field in [
    'schema_version',
    'contract_version',
    'derivation_version',
    'status',
    'strength',
    'generated_at',
    'sufficiency',
  ]) {
    test(
      'unsupported essential field $field cannot become a successful empty model',
      () {
        final d = payload();
        d[field] = field == 'schema_version'
            ? 3
            : field == 'sufficiency'
            ? {}
            : 'unknown';
        expect(
          () => PersonalSkinModel.fromApi(d, owner: 'a'),
          throwsA(anything),
        );
      },
    );
  }
  test(
    'timezone parsing honors actual offsets and rejects naive/invalid dates',
    () {
      final d = payload()..['generated_at'] = '2026-10-13T14:00:00+02:00';
      expect(
        PersonalSkinModel.fromApi(d, owner: 'a').generatedAt,
        DateTime.utc(2026, 10, 13, 12),
      );
      for (final time in ['2026-10-13T14:00:00', '2026-02-30T12:00:00Z']) {
        d['generated_at'] = time;
        expect(
          () => PersonalSkinModel.fromApi(d, owner: 'a'),
          throwsFormatException,
        );
      }
    },
  );
  test('schema optional/default sections can be missing without fake data', () {
    final d = payload(partial: true)
      ..remove('sources')
      ..remove('summaries')
      ..remove('unknowns')
      ..remove('assistant_layer')
      ..remove('safety');
    final m = PersonalSkinModel.fromApi(d, owner: 'a');
    expect(m.reports, isEmpty);
    expect(m.measurements, isNull);
    expect(m.clinician, isNull);
    expect(m.safety, isNull);
    expect(m.profile!.skinType, isNull);
    expect(m.unknowns, isEmpty);
  });
  for (final field in [
    'profile',
    'history',
    'measurements',
    'experiments',
    'doctor',
  ]) {
    test('invalid optional $field is isolated and explicitly partial', () {
      final d = payload();
      if (field == 'profile') {
        d['profile'] = {'available': 'bad'};
      } else {
        (d['sources'] as Map)[field] = 'unsupported';
      }
      final m = PersonalSkinModel.fromApi(d, owner: 'a');
      expect(m.partialIssues, isNotEmpty);
      expect(m.status, 'insufficient_data');
      expect(m.coverage.reportDays, 6);
    });
  }
  for (final fault in [
    'no evidence',
    'unknown source',
    'unknown kind',
    'wrong category',
    'wrong count',
    'wrong timestamp',
    'NaN',
  ]) {
    test(
      'unsupported finding $fault is not promoted to a model conclusion',
      () {
        final d = payload(findings: true);
        final item = (d['changing'] as List).single as Map;
        if (fault == 'no evidence') {
          item['evidence'] = [];
        } else if (fault == 'wrong count') {
          item['evidence_count'] = 99;
        } else if (fault == 'wrong timestamp') {
          item['latest_evidence_at'] = '2000-01-01T00:00:00Z';
        } else if (fault == 'NaN') {
          item['reference_value'] = double.nan;
        } else {
          final e = (item['evidence'] as List).single as Map;
          e[fault == 'unknown source'
                  ? 'source'
                  : fault == 'unknown kind'
                  ? 'kind'
                  : 'category'] =
              'unknown';
        }
        final m = PersonalSkinModel.fromApi(d, owner: 'a');
        expect(m.changing, isEmpty);
        expect(m.partialIssues.single, contains('Changing findings'));
      },
    );
  }
  for (final kind in ['user_reported', 'image_proxy', 'server_recorded']) {
    test('evidence $kind preserves category and precise references', () {
      final e = PsmEvidence.fromApi(evidence(kind: kind));
      expect(e.kind, kind);
      expect(
        e.category,
        kind == 'user_reported' ? 'patient_reported' : 'system_observed',
      );
      expect(e.id, 'report-id');
    });
  }
  test('foreign profile evidence cannot personalize current user', () {
    final d = payload(owner: 'b');
    final m = PersonalSkinModel.fromApi(d, owner: 'a');
    expect(m.profile, isNull);
    expect(
      m.partialIssues,
      contains('Profile evidence is unsupported or incomplete.'),
    );
  });
  test(
    'current and earlier image estimates map exact method/units/source and separate freshness',
    () {
      final m = PersonalSkinModel.fromApi(payload(), owner: 'a');
      expect(
        m.measurements!.latest!.metrics['red_chromaticity_proxy']!.value,
        0.351,
      );
      expect(
        m.measurements!.latest!.metrics['texture_contrast_proxy']!.unit,
        'fraction_0_to_1',
      );
      expect(
        m.measurements!.latest!.source,
        'server_computed_from_upload_bytes',
      );
      expect(m.measurements!.historical!.captureId, 'earlier-capture');
      expect(m.measurements!.historical!.source, isNull);
      expect(m.measurements!.historical!.freshness!.state, 'stale');
      expect(m.measurements!.trend, 'not_comparable');
    },
  );
  for (final status in [
    'measured',
    'unavailable',
    'failed',
    'insufficient_quality',
  ]) {
    test('image estimate $status has no missing-as-zero value', () {
      final d = payload();
      ((d['sources'] as Map)['measurements'] as Map)['latest'] = g.measurement(
        status: status,
      );
      final value = PersonalSkinModel.fromApi(
        d,
        owner: 'a',
      ).measurements!.latest!;
      expect(value.status, status);
      expect(
        value.metrics.values.every(
          (v) => status == 'measured' ? v.value != null : v.value == null,
        ),
        true,
      );
    });
  }
  for (final fault in [
    'algorithm',
    'unit',
    'source capture',
    'provenance',
    'quality',
    'nonfinite',
    'out of range',
  ]) {
    test(
      'unverified image $fault does not erase otherwise supported model',
      () {
        final d = payload();
        final latest =
            ((d['sources'] as Map)['measurements'] as Map)['latest'] as Map;
        if (fault == 'algorithm') {
          latest['algorithm_version'] = 'measurement-99';
        } else if (fault == 'provenance') {
          latest['provenance'] = 'ai_inferred';
        } else if (fault == 'quality') {
          (latest['capture_quality'] as Map)['version'] = 'unknown';
        } else {
          final metric =
              (latest['metrics'] as Map)['red_chromaticity_proxy'] as Map;
          metric[fault == 'unit'
              ? 'unit'
              : fault == 'source capture'
              ? 'source_capture_id'
              : 'value'] = fault == 'nonfinite'
              ? double.infinity
              : fault == 'out of range'
              ? 3
              : 'unsupported';
        }
        final m = PersonalSkinModel.fromApi(d, owner: 'a');
        expect(m.measurements!.latest, isNull);
        expect(m.measurements!.latestUnsupported, true);
        expect(m.reports.length, 1);
      },
    );
  }
  test(
    'missing current clinician decision does not fall back to older visible history',
    () {
      final d = payload();
      final doctor = Map<String, dynamic>.from(
        (d['sources'] as Map)['doctor'] as Map,
      );
      (d['sources'] as Map)['doctor'] = doctor;
      doctor['history'] = [doctor['current_decision']];
      doctor['current_decision'] = null;
      expect(PersonalSkinModel.fromApi(d, owner: 'a').clinician, isNull);
    },
  );
  test('unknown AI/private fields are ignored, not forwarded or displayed', () {
    final d = payload();
    d['raw_profile'] = {'diagnosis': 'PRIVATE-DIAGNOSIS'};
    (d['sources'] as Map)['private'] = 'PRIVATE-SECRET';
    final m = PersonalSkinModel.fromApi(d, owner: 'a');
    expect(m.profile!.skinType, 'oily');
    expect(m.status, 'insufficient_data');
  });
  for (final field in ['included', 'authoritative', 'category']) {
    test(
      'PSM refuses incompatible assistant layer $field instead of presenting AI as deterministic',
      () {
        final d = payload();
        (d['assistant_layer'] as Map)[field] = field == 'category'
            ? 'unknown'
            : true;
        expect(
          () => PersonalSkinModel.fromApi(d, owner: 'a'),
          throwsFormatException,
        );
      },
    );
  }
  test('PSM request refuses redirects without publishing a model', () async {
    final f = Fixture()..status = 302;
    await f.run(() async {
      await f.login();
      final controller = PsmController(api);
      await controller.refresh();
      expect(controller.model, isNull);
      expect(controller.phase, PsmPhase.failed);
      expect(f.requests.last.followRedirects, false);
      controller.dispose();
      await f.done();
    });
  });
  test(
    'real PSM GET is authenticated and read only, no owner query or assistant call',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final n = f.requests.length;
        final m = await api.readPersonalSkinModel(api.sessionGeneration);
        expect(m.owner, 'a');
        expect(f.requests.length, n + 1);
        expect(f.requests.last.url.path, '/api/v1/personal-skin-model');
        expect(f.requests.last.method, 'GET');
        expect(f.requests.last.url.query, isEmpty);
        await f.done();
      });
    },
  );
  test('unconfirmed server consent prevents PSM transport', () async {
    final f = Fixture()..noConsent = true;
    await f.run(() async {
      await f.login();
      final n = f.requests.length;
      await expectLater(
        api.readPersonalSkinModel(api.sessionGeneration),
        throwsA(isA<ApiException>()),
      );
      expect(f.requests.length, n);
      await f.done();
    });
  });
  for (final code in [403, 404, 500, 503]) {
    test('PSM $code is failure, with safe GET retry', () async {
      final f = Fixture()..status = code;
      await f.run(() async {
        await f.login();
        final controller = PsmController(api);
        await controller.refresh();
        expect(controller.model, isNull);
        expect(controller.phase, PsmPhase.failed);
        expect(controller.error, isNotNull);
        f.status = 200;
        await controller.refresh();
        expect(controller.model, isNotNull);
        expect(
          f.requests
              .where((r) => r.url.path.endsWith('/personal-skin-model'))
              .every((r) => r.method == 'GET'),
          true,
        );
        controller.dispose();
        await f.done();
      });
    });
  }
  test(
    'PSM offline never claims no data/healthy or successful analysis',
    () async {
      final f = Fixture()..psmOffline = true;
      await f.run(() async {
        await f.login();
        final controller = PsmController(api);
        await controller.refresh();
        expect(controller.model, isNull);
        expect(controller.error, contains('connection'));
        controller.dispose();
        await f.done();
      });
    },
  );
  test('current PSM 401 clears session and model', () async {
    final f = Fixture()..status = 401;
    await f.run(() async {
      await f.login();
      final controller = PsmController(api);
      await controller.refresh();
      expect(api.isAuthenticated, false);
      expect(controller.model, isNull);
      expect(controller.phase, PsmPhase.ended);
      controller.dispose();
      await f.done();
    });
  });
  test('old PSM 401 cannot expire B despite reused token', () async {
    final f = Fixture()..pendingPsm = Completer();
    await f.run(() async {
      await f.login();
      final controller = PsmController(api);
      final pending = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      await f.login('b');
      f.pendingPsm!.complete(o.jsonResponse({}, 401));
      await pending;
      expect(api.observationOwner, 'b');
      expect(controller.model, isNull);
      controller.dispose();
      await f.done();
    });
  });
  for (final action in ['logout', 'switch', 'revoke', 'dispose']) {
    test('$action discards late PSM and all safety/profile state', () async {
      final f = Fixture()..pendingPsm = Completer();
      await f.run(() async {
        await f.login();
        final controller = PsmController(api);
        final pending = controller.refresh();
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
        f.pendingPsm!.complete(o.jsonResponse(payload()));
        await pending;
        expect(controller.model, isNull);
        expect(controller.safety, isNull);
        expect(controller.current, false);
        if (action != 'dispose') controller.dispose();
        await f.done();
      });
    });
  }
  test('timeout/late reply cannot override a newer successful read', () async {
    final f = Fixture();
    await f.run(() async {
      await f.login();
      final pending = Completer<PersonalSkinModel>();
      final repo = FakePsmRepository()..pending = () => pending.future;
      final controller = PsmController(
        api,
        repository: repo,
        timeout: const Duration(milliseconds: 5),
      );
      await controller.refresh();
      expect(controller.error, contains('timed out'));
      repo.pending = null;
      repo.value = PersonalSkinModel.fromApi(
        payload(status: 'no_data'),
        owner: 'a',
      );
      await controller.refresh();
      pending.complete(PersonalSkinModel.fromApi(payload(), owner: 'a'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.model!.status, 'no_data');
      controller.dispose();
      await f.done();
    });
  });
  test(
    'concurrent newest read wins and wrong repository owner is refused',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final a = Completer<PersonalSkinModel>(),
            b = Completer<PersonalSkinModel>();
        int reads = 0;
        final repo = FakePsmRepository()
          ..pending = () => reads++ == 0 ? a.future : b.future;
        final controller = PsmController(api, repository: repo);
        final first = controller.refresh(), second = controller.refresh();
        b.complete(
          PersonalSkinModel.fromApi(payload(status: 'stale'), owner: 'a'),
        );
        await second;
        a.complete(PersonalSkinModel.fromApi(payload(), owner: 'a'));
        await first;
        expect(controller.model!.status, 'stale');
        repo.pending = null;
        repo.value = PersonalSkinModel.fromApi(payload(owner: 'b'), owner: 'b');
        await controller.refresh();
        expect(controller.model, isNull);
        expect(controller.phase, PsmPhase.unsupported);
        controller.dispose();
        await f.done();
      });
    },
  );
  for (final theme in [
    'light',
    'dark',
    'reduced',
    'large light',
    'large dark',
  ]) {
    testWidgets(
      'PSM $theme presents deterministic evidence and real source distinctions',
      (t) async {
        final f = Fixture()..body = payload(findings: true);
        await f.run(() async {
          await f.login();
          await mount(
            t,
            f,
            dark: theme.contains('dark'),
            reduced: theme == 'reduced',
            scale: theme.contains('large') ? 2 : 1,
            width: theme.contains('large') ? 320 : 390,
          );
          await t.pumpAndSettle();
          expect(find.text('Personal Skin Model'), findsOneWidget);
          await scrollTo(t, find.text('Safety Engine · PSM snapshot'));
          expect(find.text('Safety Engine · PSM snapshot'), findsOneWidget);
          expect(
            find.text('Urgent medical assessment recommended'),
            findsWidgets,
          );
          await scrollTo(t, find.text('Model overview'));
          expect(
            find.textContaining('personal-skin-model-2.0'),
            findsOneWidget,
          );
          expect(
            find.textContaining('rule-based label, not an accuracy percentage'),
            findsOneWidget,
          );
          await scrollTo(t, find.text('Your reported profile'));
          expect(find.text('Skin type: oily'), findsOneWidget);
          expect(find.text('Goals: Improve routine tracking'), findsOneWidget);
          await scrollTo(t, find.text('Supporting evidence · overall_change'));
          await t.tap(find.text('Supporting evidence · overall_change'));
          await t.pumpAndSettle();
          expect(
            find.text('User-reported · checkin · report-id'),
            findsOneWidget,
          );
          await scrollTo(t, find.text('Nonclinical image estimates'));
          expect(
            find.textContaining(
              'red_chromaticity_proxy: 0.351 · fraction_0_to_1',
            ),
            findsWidgets,
          );
          expect(
            find.text(
              'No image delta or clinical change is computed or interpreted on this device.',
            ),
            findsOneWidget,
          );
          expect(find.text('Skin health score'), findsNothing);
          expect(find.text('AI diagnosis'), findsNothing);
          expect(t.takeException(), isNull);
          await f.done(t);
        });
      },
    );
  }
  for (final status in ['no_data', 'insufficient_data', 'stale']) {
    testWidgets(
      'PSM $status is truthful and does not imply healthy/completed analysis',
      (t) async {
        final f = Fixture()..body = payload(status: status, partial: true);
        await f.run(() async {
          await f.login();
          await mount(t, f);
          await t.pumpAndSettle();
          await scrollTo(t, find.text('Model overview'));
          expect(
            find.textContaining(
              status == 'no_data'
                  ? 'No eligible skin evidence yet'
                  : status == 'stale'
                  ? 'Historical evidence — current trajectory is unknown'
                  : 'Insufficient evidence for an overall trajectory',
            ),
            findsOneWidget,
          );
          expect(find.text('Healthy skin'), findsNothing);
          expect(find.text('Analysis complete'), findsNothing);
          await f.done(t);
        });
      },
    );
  }
  testWidgets(
    'partial model and unknown finding hide unsupported statement without fake success',
    (t) async {
      final d = payload(findings: true);
      (((d['changing'] as List).single as Map)['evidence'] as List).clear();
      final f = Fixture()..body = d;
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Partial model data'));
        expect(
          find.text(
            'Model statement withheld because supporting findings are unsupported.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Synthetic deterministic model statement.'),
          findsNothing,
        );
        await f.done(t);
      });
    },
  );
  testWidgets(
    'missing optional profile fields stay unknown without disclosure prompts',
    (t) async {
      final f = Fixture()..body = payload(partial: true);
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Your reported profile'));
        expect(find.text('Skin type: not provided'), findsOneWidget);
        expect(find.text('Goals: not provided'), findsOneWidget);
        expect(
          find.textContaining('Optional disclosures remain optional'),
          findsOneWidget,
        );
        await f.done(t);
      });
    },
  );
  testWidgets(
    'estimate failure is distinct from historical last measured reference',
    (t) async {
      final d = payload();
      ((d['sources'] as Map)['measurements'] as Map)['latest'] = g.measurement(
        id: 'capture-id',
        status: 'failed',
      );
      final f = Fixture()..body = d;
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Nonclinical image estimates'));
        expect(
          find.textContaining('Method: measurement-1.0 · Status: failed'),
          findsOneWidget,
        );
        expect(
          find.textContaining('red_chromaticity_proxy: unavailable'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Earlier measured estimate — historical reference, not a replacement for the latest record',
          ),
          findsOneWidget,
        );
        expect(find.text('Reference freshness: stale'), findsOneWidget);
        await f.done(t);
      });
    },
  );
  testWidgets(
    'stale experiment evaluation remains labeled association and historical',
    (t) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Experiment experiment-id · completed'));
        await t.tap(find.text('Experiment experiment-id · completed'));
        await t.pumpAndSettle();
        expect(
          find.text('Evaluation record: evaluation-id · stale'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Experiment outcome is an association, not evidence of cause.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('treatment effectiveness'), findsOneWidget);
        await f.done(t);
      });
    },
  );
  testWidgets(
    'unsupported essential format preserves independent clinical guidance',
    (t) async {
      final f = Fixture()..body = {'schema_version': 99};
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        expect(find.byType(ClinicalHomePanel), findsOneWidget);
        await scrollTo(t, find.textContaining('unsupported model format'));
        expect(find.byType(PsmEvidenceView), findsNothing);
        expect(find.text('No eligible skin evidence yet.'), findsNothing);
        await f.done(t);
      });
    },
  );
  testWidgets(
    'PSM urgent remains prominent independently of lower clinician snapshot',
    (t) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        expect(
          find.text('Urgent medical assessment recommended'),
          findsWidgets,
        );
        await scrollTo(t, find.text('Clinician decision · PSM snapshot'));
        expect(find.text('Server recommendation: track'), findsOneWidget);
        expect(
          find.textContaining('lower clinician recommendation does not remove'),
          findsOneWidget,
        );
        await scrollTo(
          t,
          find.text('Safety Engine · PSM snapshot'),
          step: -250,
        );
        final safetyPosition =
            t.getTopLeft(find.text('Safety Engine · PSM snapshot')).dy +
            t
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels;
        await scrollTo(t, find.text('Model overview'));
        final modelPosition =
            t.getTopLeft(find.text('Model overview')).dy +
            t
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels;
        expect(safetyPosition, lessThan(modelPosition));
        await f.done(t);
      });
    },
  );
  testWidgets(
    'refresh failure removes model but keeps prior safety clearly unconfirmed',
    (t) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.byKey(const Key('refreshPersonalSkinModel')));
        f.psmOffline = true;
        await t.tap(find.byKey(const Key('refreshPersonalSkinModel')));
        await t.pumpAndSettle();
        expect(find.byType(PsmEvidenceView), findsNothing);
        await scrollTo(
          t,
          find.text(
            'Previously received safety snapshot. Current PSM read is unconfirmed; refresh is required.',
          ),
          step: -250,
        );
        expect(
          find.text(
            'Previously received safety snapshot. Current PSM read is unconfirmed; refresh is required.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Urgent medical assessment recommended'),
          findsWidgets,
        );
        expect(find.text('Healthy skin'), findsNothing);
        await f.done(t);
      });
    },
  );
  testWidgets('initial loading and safe keyboard read retry are accessible', (
    t,
  ) async {
    final f = Fixture()..pendingPsm = Completer();
    await f.run(() async {
      await f.login();
      await mount(t, f, reduced: true);
      await scrollTo(t, find.text('Reading your skin evidence…'));
      expect(find.byType(PsmEvidenceView), findsNothing);
      f.pendingPsm!.complete(o.jsonResponse({}, 503));
      await t.pumpAndSettle();
      f.pendingPsm = null;
      f.status = 200;
      await scrollTo(t, find.byKey(const Key('refreshPersonalSkinModel')));
      final semantics = t.ensureSemantics();
      await t.pump();
      expect(
        t
            .getSemantics(find.text('Refresh skin evidence'))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        true,
      );
      Focus.of(t.element(find.text('Refresh skin evidence'))).requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      await scrollTo(t, find.text('Model overview'));
      expect(find.byType(PsmEvidenceView), findsOneWidget);
      semantics.dispose();
      await f.done(t);
    });
  });
  testWidgets(
    'evidence expansions support reduced motion and keyboard interaction',
    (t) async {
      final f = Fixture()..body = payload(findings: true);
      await f.run(() async {
        await f.login();
        await mount(t, f, reduced: true);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Supporting evidence · overall_change'));
        final tile = t.widget<ExpansionTile>(
          find.ancestor(
            of: find.text('Supporting evidence · overall_change'),
            matching: find.byType(ExpansionTile),
          ),
        );
        expect(tile.expansionAnimationStyle, AnimationStyle.noAnimation);
        final semantics = t.ensureSemantics();
        await t.pump();
        expect(
          t
              .getSemantics(find.text('Supporting evidence · overall_change'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          true,
        );
        await t.tap(find.text('Supporting evidence · overall_change'));
        await t.pump();
        expect(find.text('Rule: report-6-days_latest-3-agree'), findsOneWidget);
        semantics.dispose();
        await f.done(t);
      });
    },
  );
  for (final action in ['switch', 'logout', 'revoke']) {
    testWidgets('$action clears displayed model and stale route actions', (
      t,
    ) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Model overview'));
        expect(find.byType(PsmEvidenceView), findsOneWidget);
        if (action == 'switch') {
          await f.login('b');
        } else if (action == 'logout') {
          await api.logout();
        } else {
          f.noConsent = true;
          await f.state.account.hydrate(reuseConsent: false);
        }
        await t.pumpAndSettle();
        expect(find.text('Session ended'), findsOneWidget);
        expect(find.byType(PsmEvidenceView), findsNothing);
        expect(find.byKey(const Key('psmRecordObservation')), findsNothing);
        expect(find.text('Skin type: oily'), findsNothing);
        await f.done(t);
      });
    });
  }
  testWidgets('idle expiration during model loading rejects late PSM', (
    t,
  ) async {
    final f = Fixture()
      ..ttl = 1
      ..pendingPsm = Completer();
    await f.run(() async {
      await f.login();
      await mount(t, f);
      await t.pump(const Duration(seconds: 2));
      f.pendingPsm!.complete(o.jsonResponse(payload()));
      await t.pumpAndSettle();
      expect(find.text('Session ended'), findsOneWidget);
      expect(find.byType(PsmEvidenceView), findsNothing);
      await f.done(t);
    });
  });
  testWidgets(
    'unknown safety reason preserves urgent message and does not imply clearance',
    (t) async {
      final d = payload();
      d['safety'] = {
        ...c.safety(status: 'urgent'),
        'reasons': [
          {
            'code': 'new_reason',
            'state': 'unsupported',
            'summary': 'Synthetic unknown safety reason.',
            'evidence': [],
          },
        ],
      };
      final f = Fixture()..body = d;
      await f.run(() async {
        await f.login();
        await mount(t, f);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Safety Engine · PSM snapshot'));
        expect(
          find.text(
            'The safety snapshot contains unsupported values. It cannot establish medical clearance.',
          ),
          findsOneWidget,
        );
        expect(
          find.text('Urgent medical assessment recommended'),
          findsWidgets,
        );
        await f.done(t);
      });
    },
  );
  testWidgets(
    'Reports uses real PSM entry and keeps bottom navigation labels',
    (t) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        await h.mount(t, f, Scaffold(body: ReportsTab(state: f.state)));
        await t.pumpAndSettle();
        expect(AppShell.labels, [
          'Home',
          'Experiment',
          'Products',
          'Rewards',
          'Reports',
          'Profile',
        ]);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/personal-skin-model')),
          isEmpty,
        );
        await t.tap(find.byKey(const Key('openPersonalSkinModel')));
        await t.pumpAndSettle();
        expect(find.text('Personal Skin Model'), findsOneWidget);
        expect(
          f.requests
              .where((r) => r.url.path.endsWith('/personal-skin-model'))
              .length,
          1,
        );
        await f.done(t);
      });
    },
  );
  for (final target in ['observation', 'images', 'clinical']) {
    testWidgets(
      'next action $target opens implemented destination and returning uses GET refresh',
      (t) async {
        final f = Fixture()..list = [];
        await f.run(() async {
          await f.login();
          await mount(t, f);
          await t.pumpAndSettle();
          final before = f.requests
              .where((r) => r.url.path.endsWith('/personal-skin-model'))
              .length;
          final key = Key(
            target == 'observation'
                ? 'psmRecordObservation'
                : target == 'images'
                ? 'psmImageHistory'
                : 'psmClinicalGuidance',
          );
          await scrollTo(t, find.byKey(key));
          await t.tap(find.byKey(key));
          await t.pumpAndSettle();
          expect(
            target == 'observation'
                ? find.byType(ObservationScreen)
                : target == 'images'
                ? find.byType(CaptureHistoryScreen)
                : find.byType(ClinicalStatusScreen),
            findsOneWidget,
          );
          await t.pageBack();
          await t.pumpAndSettle();
          expect(
            f.requests
                .where((r) => r.url.path.endsWith('/personal-skin-model'))
                .length,
            before + 1,
          );
          expect(
            f.requests.where(
              (r) =>
                  r.url.path.endsWith('/assistance') ||
                  r.url.path.endsWith('/chat'),
            ),
            isEmpty,
          );
          await f.done(t);
        });
      },
    );
  }
}
