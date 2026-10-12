import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/observations/observation_controller.dart';
import 'package:dermaire_app/observations/observation_models.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = ApiService.instance;
ObservationDraft draft({
  String change = 'same',
  String? routine,
  String notes = '',
  Map<String, bool?> flags = const {},
  String? severity,
  String? pain,
}) => ObservationDraft(
  change: change,
  moment: 'Morning',
  routine: routine,
  notes: notes,
  flags: flags,
  severity: severity,
  pain: pain,
);
Map<String, dynamic> record({
  String id = 'server-record',
  String owner = 'a',
  ObservationDraft? value,
}) {
  final d = value ?? draft();
  final report = {
    ...d.report,
    'routine_status': d.routine,
    'safety': d.report['safety'] == null
        ? null
        : {
            'severity': d.severity,
            'pain': d.pain,
            for (final key in safetyQuestions.keys) key: d.flags[key],
          },
  };
  return {
    'id': id,
    'user_id': owner,
    'created_at': '2026-10-12T12:00:00Z',
    'time_of_day': d.moment,
    'notes': d.submittedNotes,
    'hydration_score': null,
    'redness_score': null,
    'texture_score': null,
    'ai_vision_analysis': {'measurement_source': 'none'},
    'observation': {
      'schema_version': 1,
      'user_reported': report,
      'daily_context_date': '2026-10-12',
      'daily_context_id': null,
      'provenance': {'report': 'user_reported', 'measurements': 'not_recorded'},
    },
  };
}

http.Response jsonResponse(Object? body, [int code = 200]) =>
    http.Response(jsonEncode(body), code);
http.Response auth(String owner, {int ttl = 3600}) => jsonResponse({
  'access_token': 'reused-synthetic-token',
  'expires_in': ttl,
  'user_id': owner,
  'role': 'patient',
});
http.Response user(String owner) => jsonResponse({
  'id': owner,
  'safety_accepted': true,
  'role': 'patient',
  'full_name': 'Synthetic',
  'email': '$owner@example.invalid',
  'skin_concerns': [],
});
Map<String, dynamic> safety([String status = 'track']) => {
  'engine_version': 'safety-1.0',
  'status': status,
  'evaluated_at': '2026-10-12T12:00:00Z',
  'guidance': status == 'urgent'
      ? 'SERVER URGENT GUIDANCE'
      : 'SERVER MONITORING GUIDANCE',
  'reasons': [],
  'evidence_status': {
    'risk_screen_complete': false,
    'stale_or_absent': true,
    'current_report_count': 0,
  },
  'limitations': ['Not a diagnosis.'],
};
http.Response clinical(
  http.Request r, {
  String owner = 'a',
  String status = 'track',
}) => jsonResponse(
  r.url.path.endsWith('/safety')
      ? safety(status)
      : {
          'schema_version': 'doctor-loop-2.0',
          'patient_id': owner,
          'state': 'not_requested',
          'latest_sequence': 0,
          'changed_at': null,
          'current_decision': null,
          'safety': safety(status),
        },
);
MockClient isolated(Future<http.Response> Function(http.Request) action) =>
    MockClient((r) {
      expectSync(r.url.host, 'flutter-tests.invalid');
      return action(r);
    });
Future<void> login(String owner) async {
  await api.login(email: '$owner@example.invalid', password: 'Synthetic123!');
  await api.readSafetyAcceptance();
}

void prepare(ObservationController c, ObservationDraft value) {
  final g = api.sessionGeneration;
  c.begin(generation: g);
  c.edit(value, generation: g);
  expectSync(c.review(generation: g), isTrue);
}

String? field(http.Request r, String name) => RegExp(
  'name="$name"\\r\\n\\r\\n(.*?)\\r\\n--',
  dotAll: true,
).firstMatch(r.body)?.group(1);
ObservationDraft posted(http.Request r) {
  final report = jsonDecode(field(r, 'report')!) as Map<String, dynamic>;
  final s = report['safety'] as Map<String, dynamic>?;
  return ObservationDraft(
    change: report['overall_change'] as String,
    moment: field(r, 'time_of_day'),
    symptoms: (report['symptoms'] as List).cast<String>(),
    routine: report['routine_status'] as String?,
    notes: field(r, 'notes') ?? '',
    severity: s?['severity'] as String?,
    pain: s?['pain'] as String?,
    flags: {
      for (final k in safetyQuestions.keys)
        if (s?[k] != null) k: s![k] as bool,
    },
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() => api.init());
  test('unanswered optional health fields are omitted, never false/zero', () {
    final d = draft();
    expect(d.report, {'overall_change': 'same', 'symptoms': []});
    expect(d.submittedNotes, isNull);
    final partial = draft(flags: {'rapid_spread': false}, severity: 'mild');
    expect(partial.report['safety'], {
      'severity': 'mild',
      'rapid_spread': false,
    });
    expect(
      (partial.report['safety'] as Map).containsKey('breathing_difficulty'),
      isFalse,
    );
    expect(
      ObservationRecord.fromApi(
        record(value: partial),
        owner: 'a',
      ).matches(partial),
      isTrue,
    );
  });
  for (final change in observationChanges) {
    test(
      'supported $change observation and explicit safety values round trip',
      () {
        final d = draft(
          change: change,
          routine: 'partial',
          flags: {'breathing_difficulty': true, 'rapid_spread': false},
          severity: 'moderate',
          pain: 'mild',
          notes: 'Own note',
        );
        expect(d.validation, isNull);
        expect(
          ObservationRecord.fromApi(record(value: d), owner: 'a').matches(d),
          isTrue,
        );
      },
    );
  }
  test('validation and unknown stored fields do not become defaults', () {
    expect(ObservationDraft().validation, isNotNull);
    expect(draft(change: 'future').validation, isNotNull);
    expect(draft(notes: 'x' * 1501).validation, isNotNull);
    final row = record();
    (row['observation']['user_reported'] as Map)['overall_change'] = 'future';
    final saved = ObservationRecord.fromApi(row, owner: 'a');
    expect(saved.report!.unsupported, isTrue);
    expect(saved.matches(draft()), isFalse);
    expect(
      ObservationRecord.fromApi({
        ...record(),
        'ai_vision_analysis': null,
      }, owner: 'a').kind,
      ObservationKind.unsupported,
    );
  });
  for (final invalid in [
    'owner',
    'timestamp',
    'metrics',
    'provenance',
    'simulation',
  ]) {
    test('invalid observation receipt rejected: $invalid', () {
      final r = record();
      switch (invalid) {
        case 'owner':
          r['user_id'] = 'foreign';
        case 'timestamp':
          r['created_at'] = '2026-02-30T12:00:00Z';
        case 'metrics':
          r['hydration_score'] = 0;
        case 'provenance':
          r['observation']['provenance']['report'] = 'ai_inferred';
        case 'simulation':
          r['ai_vision_analysis'] = <String, dynamic>{
            'measurement_source': 'none',
            'simulated': true,
          };
      }
      expect(
        () => ObservationRecord.fromApi(r, owner: 'a'),
        throwsFormatException,
      );
    });
  }
  test('manual metrics and image estimates retain distinct provenance', () {
    for (final source in ['manual', 'image_proxy']) {
      final r = {
        ...record(),
        'hydration_score': 80,
        'redness_score': 10,
        'texture_score': 60,
        'ai_vision_analysis': {'measurement_source': source},
      };
      final v = ObservationRecord.fromApi(r, owner: 'a');
      expect(
        v.kind,
        source == 'manual'
            ? ObservationKind.manual
            : ObservationKind.imageEstimate,
      );
      expect(v.matches(draft()), isFalse);
      expect(v.scores['hydration'], 80);
    }
  });

  for (final code in [400, 403, 404, 409, 422, 500, 503]) {
    test(
      'POST $code has a distinct rejection/uncertain outcome and never auto-retries',
      () async {
        final c = ObservationController(api);
        var posts = 0;
        await http.runWithClient(
          () async {
            await login('a');
            prepare(c, draft());
            expect(await c.submit(generation: api.sessionGeneration), isFalse);
            expect(
              c.phase,
              code < 500
                  ? ObservationPhase.rejected
                  : ObservationPhase.uncertain,
            );
            expect(c.saved, isNull);
            expect(posts, 1);
            expect(await c.submit(generation: api.sessionGeneration), isFalse);
            expect(posts, 1);
            c.dispose();
            await api.init();
          },
          () => isolated((r) async {
            if (r.url.path.endsWith('/auth/login')) return auth('a');
            if (r.url.path.endsWith('/users/me')) return user('a');
            posts++;
            return http.Response('synthetic private body', code);
          }),
        );
      },
    );
  }
  for (final failure in [
    'timeout',
    'offline',
    'malformed',
    'wrong_owner',
    'wrong_fields',
    'defaulted_safety',
  ]) {
    test('$failure POST cannot confirm or blindly resend', () async {
      final c = ObservationController(api);
      var posts = 0;
      await http.runWithClient(
        () async {
          await login('a');
          prepare(c, draft());
          expect(await c.submit(generation: api.sessionGeneration), isFalse);
          expect(c.phase, ObservationPhase.uncertain);
          expect(c.saved, isNull);
          expect(c.message, isNot(contains('private payload')));
          expect(await c.submit(generation: api.sessionGeneration), isFalse);
          expect(posts, 1);
          c.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          posts++;
          if (failure == 'timeout') throw TimeoutException('private payload');
          if (failure == 'offline') {
            throw http.ClientException('private payload');
          }
          if (failure == 'malformed') return http.Response('{', 201);
          final v = record(
            owner: failure == 'wrong_owner' ? 'foreign' : 'a',
            value: draft(change: failure == 'wrong_fields' ? 'worse' : 'same'),
          );
          if (failure == 'defaulted_safety') {
            v['observation']['user_reported']['safety'] = {
              'rapid_spread': false,
            };
          }
          return jsonResponse(v, 201);
        }),
      );
    });
  }
  test(
    'review is required, rapid repeated taps send only one POST, response confirms exact fields',
    () async {
      final c = ObservationController(api);
      var posts = 0;
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await login('a');
          final g = api.sessionGeneration;
          c.begin(generation: g);
          c.edit(draft(), generation: g);
          expect(await c.submit(generation: g), isFalse);
          expect(posts, 0);
          expect(c.review(generation: g), isTrue);
          final first = c.submit(generation: g);
          final second = c.submit(generation: g);
          await Future<void>.delayed(Duration.zero);
          expect(posts, 1);
          expect(c.phase, ObservationPhase.submitting);
          expect(c.saved, isNull);
          pending.complete(jsonResponse(record(), 201));
          expect(await first, isTrue);
          expect(await second, isFalse);
          expect(c.saved!.id, 'server-record');
          expect(c.phase, ObservationPhase.confirmed);
          expect(await c.submit(generation: g), isFalse);
          expect(posts, 1);
          c.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          posts++;
          expect(r.body, isNot(contains('hydration_score')));
          expect(r.body, isNot(contains('idempotency_key')));
          expect(jsonDecode(field(r, 'report')!), draft().report);
          return pending.future;
        }),
      );
    },
  );
  for (final knownId in [false, true]) {
    for (final historyEmpty in [false, true]) {
      test(
        'safe GET reconciliation known ID=$knownId empty=$historyEmpty never retries POST',
        () async {
          final c = ObservationController(api);
          var posts = 0, gets = 0;
          await http.runWithClient(
            () async {
              await login('a');
              prepare(c, draft());
              await c.submit(generation: api.sessionGeneration);
              expect(c.phase, ObservationPhase.uncertain);
              final confirmed = await c.reconcile(
                generation: api.sessionGeneration,
              );
              expect(confirmed, knownId && !historyEmpty);
              expect(
                c.phase,
                confirmed
                    ? ObservationPhase.confirmed
                    : ObservationPhase.uncertain,
              );
              expect(posts, 1);
              expect(gets, 1);
              if (confirmed) {
                expect(c.saved!.id, 'server-record');
              } else {
                expect(c.saved, isNull);
              }
              c.dispose();
              await api.init();
            },
            () => isolated((r) async {
              if (r.url.path.endsWith('/auth/login')) return auth('a');
              if (r.url.path.endsWith('/users/me')) return user('a');
              if (r.method == 'POST') {
                posts++;
                if (!knownId) throw TimeoutException('uncertain');
                return jsonResponse({
                  'id': 'server-record',
                  'user_id': 'a',
                }, 201);
              }
              gets++;
              return jsonResponse(historyEmpty ? [] : [record()]);
            }),
          );
        },
      );
    }
  }
  for (final code in [401, 403, 503]) {
    test('history $code is not empty successful history', () async {
      final c = ObservationController(api);
      await http.runWithClient(
        () async {
          await login('a');
          expect(
            await c.loadHistory(generation: api.sessionGeneration),
            isFalse,
          );
          expect(c.rows, isNull);
          if (code == 401) {
            expect(api.isAuthenticated, isFalse);
          } else {
            expect(c.historyPhase, ObservationHistoryPhase.failed);
          }
          c.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          return http.Response('', code);
        }),
      );
    });
  }
  test(
    'history preserves server ordering, stable identity and stale failure without merging receipt',
    () async {
      final c = ObservationController(api);
      var fail = false;
      await http.runWithClient(
        () async {
          await login('a');
          expect(
            await c.loadHistory(generation: api.sessionGeneration),
            isTrue,
          );
          expect(c.rows!.map((r) => r.id), ['second', 'first']);
          fail = true;
          expect(
            await c.loadHistory(generation: api.sessionGeneration),
            isFalse,
          );
          expect(c.historyStale, isTrue);
          expect(c.rows!.length, 2);
          c.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          return fail
              ? http.Response('', 503)
              : jsonResponse([record(id: 'second'), record(id: 'first')]);
        }),
      );
    },
  );
  test(
    'duplicate IDs and foreign history cannot populate account state',
    () async {
      final c = ObservationController(api);
      var foreign = false;
      await http.runWithClient(
        () async {
          await login('a');
          expect(
            await c.loadHistory(generation: api.sessionGeneration),
            isFalse,
          );
          expect(c.rows, isNull);
          foreign = true;
          expect(
            await c.loadHistory(generation: api.sessionGeneration),
            isFalse,
          );
          expect(c.rows, isNull);
          c.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          return jsonResponse(
            foreign ? [record(owner: 'b')] : [record(), record()],
          );
        }),
      );
    },
  );
  for (final operation in ['write', 'history']) {
    for (final switchAccount in [false, true]) {
      for (final code in [201, 401]) {
        test(
          'late $operation/$code cannot confirm, navigate or invalidate account switch=$switchAccount',
          () async {
            final c = ObservationController(api);
            final pending = Completer<http.Response>();
            var owner = 'a', hold = true;
            await http.runWithClient(
              () async {
                await login('a');
                final oldGeneration = api.sessionGeneration;
                prepare(c, draft(notes: 'OLD PRIVATE DRAFT'));
                final old = operation == 'write'
                    ? c.submit(generation: oldGeneration)
                    : c.loadHistory(generation: oldGeneration);
                await Future<void>.delayed(Duration.zero);
                await api.logout();
                hold = false;
                if (switchAccount) {
                  owner = 'b';
                  await login('b');
                  c.begin(generation: api.sessionGeneration);
                  c.edit(
                    draft(notes: 'NEW DRAFT'),
                    generation: api.sessionGeneration,
                  );
                  await c.loadHistory(generation: api.sessionGeneration);
                }
                pending.complete(
                  code == 401
                      ? http.Response('', 401)
                      : jsonResponse(
                          operation == 'write'
                              ? record(value: draft(notes: 'OLD PRIVATE DRAFT'))
                              : [record()],
                          operation == 'write' ? 201 : 200,
                        ),
                );
                expect(await old, isFalse);
                expect(api.isAuthenticated, switchAccount);
                expect(c.saved, isNull);
                if (switchAccount) {
                  expect(c.rows!.single.id, 'new-owner-record');
                  expect(c.draft.notes, 'NEW DRAFT');
                  c.edit(draft(notes: 'late edit'), generation: oldGeneration);
                  expect(c.draft.notes, 'NEW DRAFT');
                  expect(c.review(generation: oldGeneration), isFalse);
                } else {
                  expect(c.rows, isNull);
                  expect(c.draft.notes, isEmpty);
                }
                c.dispose();
                await api.init();
              },
              () => isolated((r) async {
                if (r.url.path.endsWith('/auth/login')) return auth(owner);
                if (r.url.path.endsWith('/users/me')) return user(owner);
                if (r.url.path.endsWith('/auth/logout')) {
                  return http.Response('', 204);
                }
                if (hold) return pending.future;
                return jsonResponse([
                  record(owner: owner, id: 'new-owner-record'),
                ]);
              }),
            );
          },
        );
      }
    }
  }
  test('overlapping history refreshes ignore older responses', () async {
    final c = ObservationController(api);
    final pending = Completer<http.Response>();
    var first = true;
    await http.runWithClient(
      () async {
        await login('a');
        final old = c.loadHistory(generation: api.sessionGeneration);
        await Future<void>.delayed(Duration.zero);
        first = false;
        expect(await c.loadHistory(generation: api.sessionGeneration), isTrue);
        pending.complete(jsonResponse([record(id: 'older')]));
        expect(await old, isFalse);
        expect(c.rows!.single.id, 'newer');
        c.dispose();
        await api.init();
      },
      () => isolated((r) async {
        if (r.url.path.endsWith('/auth/login')) return auth('a');
        if (r.url.path.endsWith('/users/me')) return user('a');
        return first ? pending.future : jsonResponse([record(id: 'newer')]);
      }),
    );
  });

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      for (final reduced in [false, true]) {
        testWidgets(
          'interactive reviewed journey dark=$dark large=$large reduced=$reduced',
          (tester) async {
            tester.view.physicalSize = const Size(390, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final state = DermaireState();
            var posts = 0;
            var saved = false;
            await http.runWithClient(
              () async {
                await login('a');
                await tester.pumpWidget(
                  MaterialApp(
                    theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                    locale: const Locale('en'),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(large ? 2 : 1),
                        disableAnimations: reduced,
                      ),
                      child: child!,
                    ),
                    home: CameraScreen(state: state),
                  ),
                );
                await tester.pumpAndSettle();
                Future<void> tap(Finder f) async {
                  await tester.scrollUntilVisible(
                    f,
                    220,
                    scrollable: find.byType(Scrollable).first,
                  );
                  await tester.pumpAndSettle();
                  await tester.tap(f);
                  await tester.pumpAndSettle();
                }

                await tap(find.byKey(const Key('reviewObservation')));
                expect(
                  find.text('Choose your overall skin change.'),
                  findsOneWidget,
                );
                expect(posts, 0);
                await tap(find.byKey(const Key('change_same')));
                await tap(find.byKey(const Key('moment_Morning')));
                await tap(find.byKey(const Key('symptom_dryness')));
                await tap(find.byKey(const Key('routine_partial')));
                await tap(find.byKey(const Key('reviewObservation')));
                expect(posts, 0);
                expect(find.text('Review before saving'), findsOneWidget);
                expect(find.text('Your reported change: same'), findsOneWidget);
                await tap(find.byKey(const Key('submitObservation')));
                expect(posts, 1);
                expect(
                  find.byKey(const Key('observationReceipt')),
                  findsOneWidget,
                );
                expect(find.text('Observation saved'), findsOneWidget);
                await tester.scrollUntilVisible(
                  find.text('SERVER URGENT GUIDANCE'),
                  -220,
                  scrollable: find.byType(Scrollable).first,
                );
                await tester.pumpAndSettle();
                expect(
                  tester.getTopLeft(find.text('SERVER URGENT GUIDANCE')).dy,
                  lessThan(
                    tester.getTopLeft(find.text('Observation saved')).dy,
                  ),
                );
                expect(state.todayCheckedIn, isFalse);
                expect(state.baseline.completedDays, 0);
                expect(
                  find.textContaining('no measurements recorded'),
                  findsOneWidget,
                );
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox());
                state.dispose();
                await api.init();
              },
              () => isolated((r) async {
                if (r.url.path.endsWith('/auth/login')) return auth('a');
                if (r.url.path.endsWith('/users/me')) return user('a');
                if (r.url.path.endsWith('/checkins') && r.method == 'POST') {
                  posts++;
                  saved = true;
                  final d = posted(r);
                  expect(d.report.containsKey('safety'), isFalse);
                  expect(r.body, isNot(contains('hydration_score')));
                  return jsonResponse(record(value: d), 201);
                }
                if (r.url.path.endsWith('/safety') ||
                    r.url.path.endsWith('/doctor/review-status')) {
                  return clinical(r, status: saved ? 'urgent' : 'track');
                }
                if (r.url.path.endsWith('/baseline')) {
                  return jsonResponse({
                    'status': 'collecting',
                    'required_days': 5,
                    'completed_days': 0,
                    'checkin_ids': [],
                    'metrics': {},
                    'today_checked_in': false,
                  });
                }
                if (r.url.path.endsWith('/home')) {
                  return jsonResponse({
                    'as_of': DateTime.now().toUtc().toIso8601String(),
                    'date': DateTime.now()
                        .toUtc()
                        .toIso8601String()
                        .split('T')
                        .first,
                    'today_checked_in': false,
                    'experiment': null,
                    'journal': [],
                  });
                }
                return http.Response('', 503);
              }),
            );
          },
        );
      }
    }
  }
  testWidgets(
    'real 30s uncertain timeout disables retry and clears private draft on logout',
    (tester) async {
      final state = DermaireState();
      final pending = Completer<http.Response>();
      var posts = 0;
      await http.runWithClient(
        () async {
          await login('a');
          prepare(state.observations, draft(notes: 'PRIVATE DRAFT'));
          await tester.pumpWidget(
            MaterialApp(home: CameraScreen(state: state)),
          );
          await tester.pumpAndSettle();
          final submit = state.observations.submit(
            generation: api.sessionGeneration,
          );
          await tester.pump();
          expect(find.text('Submitting your observation…'), findsOneWidget);
          expect(find.text('Observation saved'), findsNothing);
          await tester.pump(const Duration(seconds: 31));
          expect(await submit, isFalse);
          await tester.pumpAndSettle();
          expect(find.text('Save outcome uncertain'), findsOneWidget);
          expect(find.byKey(const Key('submitObservation')), findsNothing);
          await tester.scrollUntilVisible(
            find.byKey(const Key('reconcileObservation')),
            180,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('reconcileObservation')));
          await tester.pumpAndSettle();
          expect(posts, 1);
          expect(state.observations.phase, ObservationPhase.uncertain);
          pending.complete(
            jsonResponse(record(value: draft(notes: 'PRIVATE DRAFT')), 201),
          );
          await tester.pumpAndSettle();
          expect(find.text('Observation saved'), findsNothing);
          await api.logout();
          await tester.pumpAndSettle();
          expect(state.observations.draft.notes, isEmpty);
          expect(find.textContaining('PRIVATE DRAFT'), findsNothing);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          if (r.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }
          if (r.url.path.endsWith('/checkins')) {
            if (r.method == 'POST') {
              posts++;
              return pending.future;
            }
            return jsonResponse([record(value: draft(notes: 'PRIVATE DRAFT'))]);
          }
          return clinical(r);
        }),
      );
    },
  );
  testWidgets(
    'optional safety selections are explicit and unchanged on review/edit',
    (tester) async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login('a');
          await tester.pumpWidget(
            MaterialApp(home: CameraScreen(state: state)),
          );
          await tester.pumpAndSettle();
          Future<void> tap(Finder f) async {
            await tester.scrollUntilVisible(
              f,
              180,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            await tester.tap(f);
            await tester.pumpAndSettle();
          }

          await tap(find.byKey(const Key('change_better')));
          await tap(find.byKey(const Key('moment_Morning')));
          await tap(find.text('Optional safety observations'));
          await tap(find.byKey(const Key('flag_rapid_spread_false')));
          await tap(find.byKey(const Key('severity_mild')));
          expect(state.observations.draft.flags['rapid_spread'], isFalse);
          expect(
            state.observations.draft.flags['breathing_difficulty'],
            isNull,
          );
          await tap(find.byKey(const Key('reviewObservation')));
          expect(find.text('Rapid spread: No'), findsOneWidget);
          expect(find.text('Breathing difficulty: Unknown'), findsOneWidget);
          await tap(find.byKey(const Key('editObservation')));
          expect(state.observations.draft.severity, 'mild');
          expect(state.observations.draft.flags['rapid_spread'], isFalse);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          expect(r.method, 'GET');
          return clinical(r);
        }),
      );
    },
  );
  testWidgets(
    'expired session during submission clears draft and rejects the late save',
    (tester) async {
      final state = DermaireState();
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await login('a');
          prepare(state.observations, draft(notes: 'PRIVATE EXPIRED DRAFT'));
          final old = state.observations.submit(
            generation: api.sessionGeneration,
          );
          await tester.pump(const Duration(seconds: 2));
          expect(api.isAuthenticated, isFalse);
          expect(state.observations.saved, isNull);
          expect(state.observations.draft.notes, isEmpty);
          pending.complete(
            jsonResponse(
              record(value: draft(notes: 'PRIVATE EXPIRED DRAFT')),
              201,
            ),
          );
          expect(await old, isFalse);
          state.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a', ttl: 1);
          if (r.url.path.endsWith('/users/me')) return user('a');
          return pending.future;
        }),
      );
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'actual server history keeps observation/metrics/proxy and UTC distinction with dark=$dark large text',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = DermaireState();
        final rows = [
          record(id: 'observation'),
          {
            ...record(id: 'manual'),
            'ai_vision_analysis': {'measurement_source': 'manual'},
            'hydration_score': 50,
            'redness_score': 20,
            'texture_score': 60,
          },
          {
            ...record(id: 'proxy'),
            'ai_vision_analysis': {'measurement_source': 'image_proxy'},
            'hydration_score': 60,
            'redness_score': 30,
            'texture_score': 70,
          },
        ];
        await http.runWithClient(
          () async {
            await login('a');
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('en'),
                theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: TimelineScreen(state: state),
              ),
            );
            await tester.pumpAndSettle();
            expect(state.observations.rows!.map((r) => r.kind), [
              ObservationKind.reportOnly,
              ObservationKind.manual,
              ObservationKind.imageEstimate,
            ]);
            expect(
              find.textContaining('2026-10-12 12:00:00 UTC'),
              findsWidgets,
            );
            await tester.scrollUntilVisible(
              find.textContaining('User-entered tracking metrics'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              find.textContaining('User-entered tracking metrics'),
              findsOneWidget,
            );
            await tester.scrollUntilVisible(
              find.textContaining('Nonclinical image estimates'),
              200,
              scrollable: find.byType(Scrollable).first,
            );
            expect(
              find.textContaining('Nonclinical image estimates'),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            state.dispose();
            await api.init();
          },
          () => isolated((r) async {
            if (r.url.path.endsWith('/auth/login')) return auth('a');
            if (r.url.path.endsWith('/users/me')) return user('a');
            return jsonResponse(rows);
          }),
        );
      },
    );
  }
}
