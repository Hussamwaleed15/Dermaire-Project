import 'dart:async';
import 'package:dermaire_app/psm/psm_models.dart';
import 'package:dermaire_app/psm/psm_controller.dart';
import 'package:dermaire_app/psm/psm_screen.dart';
import 'package:dermaire_app/psm/psm_source_view.dart';
import 'package:dermaire_app/assistance/assistance_models.dart';
import 'package:dermaire_app/assistance/assistance_controller.dart';
import 'package:dermaire_app/assistance/assistance_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'personal_skin_model_test.dart' as p;
import 'assistance_evidence_test.dart' as a;
import 'private_capture_history_test.dart' as h;

Map<String, dynamic> projection() {
  final d = p.payload();
  final sources = d['sources'] as Map;
  sources['daily_context'] = {
    'category': 'patient_reported',
    'days': [
      {
        'id': 'context-1',
        'date': '2026-10-13',
        'unusual_conditions': ['poor_sleep'],
        'freshness': p.fresh('stale'),
      },
    ],
  };
  sources['routine'] = {
    'category': 'patient_reported',
    'configured': [
      {
        'id': 'entry-1',
        'product_id': 'product-1',
        'schedule': 'AM',
        'frequency': 'daily',
        'start_date': '2026-10-01',
        'freshness': p.fresh(),
      },
    ],
    'adherence': {
      'category': 'deterministic_derived',
      'source': 'user_reported',
      'window_days': 14,
      'expected_known_slots': 10,
      'reported_slots': 3,
      'completed_slots': 2,
      'unknown_slots': 7,
      'freshness': p.fresh(),
      'caveats': ['Self-reported, not verified exposure.'],
    },
    'historical_snapshots': [
      {
        'category': 'patient_reported',
        'id': 'log-1',
        'entry_id': 'entry-1',
        'date': '2026-10-12',
        'slot': 'AM',
        'status': 'skipped',
        'recorded_at': p.generated,
        'configuration': {'product_id': 'old-product'},
      },
    ],
  };
  sources['product_intelligence'] = {
    'category': 'deterministic_derived',
    'products': [
      {
        'category': 'deterministic_derived',
        'product_id': 'product-1',
        'data_completeness': 'incomplete',
        'unknowns': ['Concentration unknown.'],
        'freshness': p.fresh(),
      },
    ],
  };
  return d;
}

PersonalSkinModel model([Map<String, dynamic>? d]) =>
    PersonalSkinModel.fromApi(d ?? projection(), owner: 'a');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  test(
    'product warnings retain deterministic source references and limitations',
    () {
      final d = projection();
      final pi = (d['sources'] as Map)['product_intelligence'] as Map;
      pi['warnings'] = [
        {
          'key': 'duplicate_active',
          'severity': 'info',
          'explanation': 'Synthetic evidence warning',
          'confidence': 'low',
          'limitations': ['Not a complete safety screen'],
          'evidence': [
            {'product_id': 'product-1'},
          ],
        },
      ];
      final m = model(d);
      expect(m.productWarnings.single.products, ['product-1']);
      expect(m.productWarnings.single.confidence, 'low');
      expect(m.productWarnings.single.limitations, [
        'Not a complete safety screen',
      ]);
      (pi['warnings'] as List)[0]['severity'] = 'diagnosis';
      expect(model(d).productWarnings, isEmpty);
      expect(
        model(d).partialIssues,
        contains('Product warnings is unsupported or incomplete.'),
      );
    },
  );
  test('moderation metadata remains separate from provider availability', () {
    final response = AssistanceResponse.fromApi(a.reply(), owner: 'a');
    expect(response.moderation!.state, 'not_invoked');
    expect(response.moderation!.invoked, false);
    expect(response.provider.availability, 'disabled');
  });
  for (final boundary in ['switch', 'ended']) {
    testWidgets('return after $boundary never refreshes original account PSM', (
      t,
    ) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = p.FakePsmRepository()..value = model();
        await h.mount(
          t,
          f,
          PersonalSkinModelScreen(state: f.state, repository: repo),
        );
        await t.pumpAndSettle();
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        if (boundary == 'switch') {
          await f.login('b');
        } else {
          await ApiService.instance.init();
        }
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(repo.reads, 1);
        expect(find.text('Session ended'), findsOneWidget);
        await f.done(t);
      });
    });
  }
  test(
    'missing clinician source cannot erase previous urgent warning',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final d = projection();
        ((((d['sources'] as Map)['doctor'] as Map)['current_decision'])
                as Map)['recommendation'] =
            'urgent';
        final repo = p.FakePsmRepository()..value = model(d);
        final c = PsmController(h.api, repository: repo);
        await c.refresh();
        final next = projection();
        (next['sources'] as Map).remove('doctor');
        repo.value = model(next);
        await c.refresh();
        expect(c.clinician!.recommendation, 'urgent');
        expect(c.clinicianStale, true);
        c.dispose();
        await f.done();
      });
    },
  );
  testWidgets(
    'failed refresh retains urgent clinician warning visibly marked stale',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final d = projection();
        ((((d['sources'] as Map)['doctor'] as Map)['current_decision'])
                as Map)['recommendation'] =
            'urgent';
        final repo = p.FakePsmRepository()..value = model(d);
        await h.mount(
          t,
          f,
          PersonalSkinModelScreen(state: f.state, repository: repo),
        );
        await t.pumpAndSettle();
        repo.pending = () async =>
            throw const FormatException('unsupported newer evidence');
        final button = find.byKey(const Key('refreshPersonalSkinModel'));
        await t.scrollUntilVisible(
          button,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await t.pumpAndSettle();
        await t.tap(button);
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byType(PsmClinicianPanel),
          -250,
          scrollable: find.byType(Scrollable).first,
        );
        final panel = t.widget<PsmClinicianPanel>(
          find.byType(PsmClinicianPanel),
        );
        expect(panel.value.recommendation, 'urgent');
        expect(panel.stale, true);
        expect(
          find.textContaining('Previously received clinician snapshot.'),
          findsOneWidget,
        );
        await f.done(t);
      });
    },
  );
  test(
    'PSM consumes real supported context routine history and product projections',
    () {
      final m = model();
      expect(m.contextDays.single.conditions, ['poor_sleep']);
      expect(m.routine!.unknown, 7);
      expect(m.routine!.history.single.product, 'old-product');
      expect(m.productEvidence.single.completeness, 'incomplete');
      expect(m.partialIssues, isEmpty);
    },
  );
  test('unknown freshness remains unknown and does not erase evidence', () {
    final d = projection();
    final source = (d['sources'] as Map)['profile'] as Map;
    source['freshness'] = {
      'state': 'unknown',
      'latest_at': '2028-01-01T00:00:00Z',
      'age_days': null,
    };
    final m = model(d);
    expect(m.profile!.freshness!.state, 'unknown');
    expect(m.profile!.freshness!.ageDays, isNull);
  });
  for (final section in ['daily_context', 'routine', 'product_intelligence']) {
    test(
      'unsupported $section provenance remains partial with independent safety intact',
      () {
        final d = projection();
        ((d['sources'] as Map)[section] as Map)['category'] = 'ai_inferred';
        final m = model(d);
        expect(m.partialIssues, isNotEmpty);
        expect(m.safety, isNotNull);
        expect(m.clinician, isNotNull);
      },
    );
  }
  test(
    'contradictory adherence cannot imply completed or skipped unknown slots',
    () {
      final d = projection();
      ((((d['sources'] as Map)['routine'] as Map)['adherence'])
              as Map)['unknown_slots'] =
          0;
      final m = model(d);
      expect(m.routine, isNull);
      expect(
        m.partialIssues,
        contains('Routine evidence is unsupported or incomplete.'),
      );
    },
  );
  for (final mode in ['degraded', 'safety_guard', 'narrowed']) {
    test('non-grounded $mode cannot fabricate AI inferred output', () {
      final d = a.reply(mode: mode);
      d['inferred_points'] = [
        {
          'category': 'ai_inferred',
          'statement': 'fabricated inference',
          'evidence_ids': ['f000'],
        },
      ];
      expect(
        () => AssistanceResponse.fromApi(d, owner: 'a'),
        throwsFormatException,
      );
    });
  }
  test('valid grounded source stays distinct without enabling a provider', () {
    final d = a.reply(mode: 'grounded_ai');
    d['inferred_points'] = [
      {
        'category': 'ai_inferred',
        'statement': 'Synthetic bounded selection',
        'evidence_ids': ['f000'],
      },
    ];
    expect(AssistanceResponse.fromApi(d, owner: 'a').inferences.length, 1);
  });
  for (final failure in ['offline', 'format', 'timeout']) {
    test(
      'urgent clinician snapshot retained as stale through $failure independently of evidence',
      () async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final d = projection();
          ((((d['sources'] as Map)['doctor'] as Map)['current_decision'])
                  as Map)['recommendation'] =
              'urgent';
          final repo = p.FakePsmRepository()..value = model(d);
          final c = PsmController(
            h.api,
            repository: repo,
            timeout: const Duration(milliseconds: 5),
          );
          await c.refresh();
          repo.pending = () async {
            if (failure == 'format') throw const FormatException('unsupported');
            if (failure == 'timeout') {
              return Completer<PersonalSkinModel>().future;
            }
            throw Exception('offline');
          };
          await c.refresh();
          expect(c.model, isNull);
          expect(c.clinician!.recommendation, 'urgent');
          expect(c.clinicianStale, true);
          c.dispose();
          await f.done();
        });
      },
    );
  }
  for (final code in [401, 403]) {
    test(
      'authorization $code clears cached clinician and Safety snapshots',
      () async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          final repo = p.FakePsmRepository()..value = model();
          final c = PsmController(h.api, repository: repo);
          await c.refresh();
          repo.pending = () async => throw PsmReadException(code);
          await c.refresh();
          expect(c.clinician, isNull);
          expect(c.safety, isNull);
          c.dispose();
          await f.done();
        });
      },
    );
  }
  test(
    'new private current decision never resurrects earlier visible history',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = p.FakePsmRepository()..value = model();
        final c = PsmController(h.api, repository: repo);
        await c.refresh();
        final d = projection();
        final doc = Map<String, dynamic>.from(
          (d['sources'] as Map)['doctor'] as Map,
        );
        (d['sources'] as Map)['doctor'] = doc;
        doc['history'] = [doc['current_decision']];
        doc['current_decision'] = null;
        doc['current_decision_visibility'] = 'not_available_to_patient';
        repo.value = model(d);
        await c.refresh();
        expect(c.clinician, isNull);
        c.dispose();
        await f.done();
      });
    },
  );
  test(
    'markStale blocks pending earlier read and session change wipes retained guidance',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<PersonalSkinModel>();
        final repo = p.FakePsmRepository()..value = model();
        final c = PsmController(h.api, repository: repo);
        await c.refresh();
        repo.pending = () => pending.future;
        final read = c.refresh();
        c.markStale();
        pending.complete(model());
        await read;
        expect(c.model, isNull);
        expect(c.clinicianStale, true);
        await f.login('b');
        expect(c.clinician, isNull);
        c.dispose();
        await f.done();
      });
    },
  );
  test(
    'assistance invalidation fences pending response without automatic retry',
    () async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final pending = Completer<AssistanceResponse>();
        final repo = _Assistance(() => pending.future);
        final c = AssistanceController(h.api, repository: repo);
        final send = c.send('My records');
        c.invalidateSnapshot();
        pending.complete(AssistanceResponse.fromApi(a.reply(), owner: 'a'));
        await send;
        expect(c.response, isNull);
        expect(c.canRetry, false);
        expect(repo.calls, 1);
        c.dispose();
        await f.done();
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'source provenance and unknowns accessible dark=$dark 320px200 reduced motion',
      (t) async {
        final f = h.Fixture();
        await f.run(() async {
          await f.login();
          await h.mount(
            t,
            f,
            Scaffold(
              body: SingleChildScrollView(child: PsmSourceView(model: model())),
            ),
            dark: dark,
            reduced: true,
            width: 320,
            scale: 2,
          );
          await t.pumpAndSettle();
          expect(
            find.textContaining('unknown of 10 known expected slots'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Frozen product: old-product'),
            findsOneWidget,
          );
          expect(find.text('Concentration unknown.'), findsOneWidget);
          expect(t.takeException(), isNull);
          await f.done(t);
        });
      },
    );
  }
  testWidgets(
    'return journey refreshes GET once and keeps clinician above model evidence',
    (t) async {
      final f = h.Fixture();
      await f.run(() async {
        await f.login();
        final repo = p.FakePsmRepository()..value = model();
        await h.mount(
          t,
          f,
          PersonalSkinModelScreen(state: f.state, repository: repo),
        );
        await t.pumpAndSettle();
        expect(repo.reads, 1);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(repo.reads, 2);
        await t.scrollUntilVisible(
          find.textContaining('Welcome back. Evidence has been reread'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Missing records do not imply missed treatment'),
          findsOneWidget,
        );
        expect(
          f.requests.where(
            (r) => r.method == 'POST' && !r.url.path.endsWith('/auth/login'),
          ),
          isEmpty,
        );
        await f.done(t);
      });
    },
  );
  testWidgets('PSM rebind does not retain original repository response', (
    t,
  ) async {
    final f = h.Fixture();
    await f.run(() async {
      await f.login();
      final pending = Completer<PersonalSkinModel>();
      final old = p.FakePsmRepository()..pending = () => pending.future;
      final next = p.FakePsmRepository()..value = model();
      await h.mount(
        t,
        f,
        PersonalSkinModelScreen(state: f.state, repository: old),
      );
      await h.mount(
        t,
        f,
        PersonalSkinModelScreen(state: f.state, repository: next),
      );
      await t.pumpAndSettle();
      pending.complete(model(p.payload(status: 'stale')));
      await t.pumpAndSettle();
      expect(next.reads, 1);
      expect(
        find.textContaining(
          'Historical evidence — current trajectory is unknown.',
        ),
        findsNothing,
      );
      await f.done(t);
    });
  });
  testWidgets('assistance lifecycle never automatically resubmits a question', (
    t,
  ) async {
    final f = h.Fixture();
    await f.run(() async {
      await f.login();
      final pending = Completer<AssistanceResponse>();
      final repo = _Assistance(() => pending.future);
      await h.mount(
        t,
        f,
        ContextualAssistanceScreen(state: f.state, repository: repo),
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('assistanceQuestion')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('assistanceQuestion')),
        'My evidence',
      );
      final button = find.byKey(const Key('requestAssistance'));
      await t.ensureVisible(button);
      await t.pumpAndSettle();
      await t.tap(button);
      await t.pump();
      expect(repo.calls, 1);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pending.complete(AssistanceResponse.fromApi(a.reply(), owner: 'a'));
      await t.pumpAndSettle();
      expect(repo.calls, 1);
      expect(find.text('Synthetic canonical assistance.'), findsNothing);
      await f.done(t);
    });
  });
}

class _Assistance implements AssistanceRepository {
  _Assistance(this.call);
  final Future<AssistanceResponse> Function() call;
  int calls = 0;
  @override
  Future<AssistanceResponse> request(String message, int generation) {
    calls++;
    return call();
  }
}
