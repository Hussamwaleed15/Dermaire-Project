import 'dart:async';
import 'dart:convert';

import 'package:dermaire_app/clinical/clinical_models.dart';
import 'package:dermaire_app/clinical/clinical_controller.dart';
import 'package:dermaire_app/clinical/clinical_ui.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/main.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = ApiService.instance;
Map<String, dynamic> safety({
  String status = 'track',
  String guidance =
      'Synthetic server guidance. Missing information does not establish safety.',
  bool absent = false,
}) => {
  'engine_version': 'safety-1.0',
  'status': status,
  'evaluated_at': '2026-10-12T12:00:00Z',
  'guidance': guidance,
  'reasons': [
    {
      'code': 'synthetic_reason',
      'state': status,
      'summary': 'Synthetic recorded reason',
      'evidence': [],
    },
  ],
  'limitations': [
    'Not a diagnosis or a replacement for a doctor.',
    'Missing flags are unknown.',
  ],
  'evidence_status': {
    'current_report_count': absent ? 0 : 1,
    'risk_screen_complete': !absent,
    'stale_or_absent': absent,
  },
};
Map<String, dynamic> decision({
  String owner = 'a',
  String state = 'reviewed',
  String? recommendation = 'doctor_review',
}) => {
  'id': 'synthetic-decision',
  'sequence': 1,
  'patient_id': owner,
  'doctor_id': 'synthetic-clinician',
  'access_id': 'synthetic-grant',
  'state': state,
  'recommendation': recommendation,
  'rationale': recommendation == null
      ? null
      : 'Synthetic clinician instruction: arrange follow-up.',
  'patient_visible': true,
  'created_at': '2026-10-12T11:00:00',
  'provenance': 'clinician_authored',
  'safety_at_review': safety(),
  'diverges_from_current_safety': false,
  'lower_than_current_safety': false,
  'urgent_safety_preserved': false,
};
Map<String, dynamic> review({
  String owner = 'a',
  String state = 'not_requested',
  Map<String, dynamic>? action,
  Map<String, dynamic>? evaluation,
}) => {
  'schema_version': 'doctor-loop-2.0',
  'patient_id': owner,
  'state': state,
  'latest_sequence': action == null ? 0 : 1,
  'changed_at': action == null ? null : '2026-10-12T11:00:00',
  'changed_by': action == null ? null : 'synthetic-clinician',
  'current_decision': action,
  'safety': evaluation ?? safety(),
  'history': [],
  'notes': [],
  'access': [],
};
http.Response response(Map<String, dynamic> value) =>
    http.Response(jsonEncode(value), 200);
http.Response auth(String owner, {String role = 'patient'}) => response({
  'access_token': 'synthetic-token',
  'expires_in': 3600,
  'user_id': owner,
  'role': role,
});
http.Response user(
  String owner, {
  bool accepted = true,
  String role = 'patient',
}) => response({
  'id': owner,
  'safety_accepted': accepted,
  'role': role,
  'full_name': 'Synthetic $owner',
  'email': '$owner@example.invalid',
  'skin_concerns': [],
});
MockClient isolated(Future<http.Response> Function(http.Request) action) =>
    MockClient((request) {
      expectSync(request.url.host, 'flutter-tests.invalid');
      return action(request);
    });
Future<void> login({
  String owner = 'a',
  String role = 'patient',
  bool consent = true,
}) async {
  await api.login(
    email: '$owner@example.invalid',
    password: 'Synthetic123!',
    requiredRole: role,
  );
  if (consent) await api.readSafetyAcceptance();
}

void main() {
  setUp(() async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final status in [
    'track',
    'low_risk_self_care',
    'doctor_review',
    'urgent',
    'future_status',
  ]) {
    test(
      'typed safety preserves canonical status $status without clearance',
      () {
        final value = SafetyAssessment.fromApi(safety(status: status));
        expect(value.rawStatus, status);
        expect(value.supported, status != 'future_status');
        expect(value.level == SafetyLevel.unknown, status == 'future_status');
        expect(value.guidance, safety()['guidance']);
        expect(value.reasons.single.summary, 'Synthetic recorded reason');
        expect(
          () => value.limitations.add('fabricated'),
          throwsUnsupportedError,
        );
      },
    );
  }
  for (final state in [
    'not_requested',
    'pending',
    'in_review',
    'reviewed',
    'follow_up_needed',
    'future_workflow',
  ]) {
    test('typed workflow $state does not manufacture a decision', () {
      final value = ClinicianReview.fromApi(review(state: state), owner: 'a');
      expect(value.rawState, state);
      expect(value.decision, isNull);
      expect(value.supported, state != 'future_workflow');
      expect(value.changedAt, isNull);
    });
  }
  test('absent evidence remains unknown, never no-risk', () {
    final value = SafetyAssessment.fromApi(safety(absent: true));
    expect(value.level, SafetyLevel.track);
    expect(value.currentReportCount, 0);
    expect(value.riskScreenComplete, isFalse);
    final missing = SafetyAssessment.fromApi({
      ...safety(),
      'evidence_status': {},
    });
    expect(missing.riskScreenComplete, isNull);
    expect(missing.staleOrAbsent, isNull);
  });
  for (final violation in [
    'owner',
    'private',
    'sequence',
    'provenance',
    'rationale',
  ]) {
    test('unverified current decision rejected: $violation', () {
      final action = decision();
      switch (violation) {
        case 'owner':
          action['patient_id'] = 'foreign';
        case 'private':
          action['patient_visible'] = false;
        case 'sequence':
          action['sequence'] = 2;
        case 'provenance':
          action['provenance'] = 'ai_inferred';
        case 'rationale':
          action['rationale'] = null;
      }
      expect(
        () => ClinicianReview.fromApi(
          review(state: 'reviewed', action: action),
          owner: 'a',
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'review owner, version, timestamps and null recommendations are explicit',
    () {
      expect(
        () => ClinicianReview.fromApi(review(owner: 'foreign'), owner: 'a'),
        throwsFormatException,
      );
      final version = ClinicianReview.fromApi({
        ...review(),
        'schema_version': 'future-version',
      }, owner: 'a');
      expect(version.supported, isFalse);
      final value = ClinicianReview.fromApi(
        review(state: 'reviewed', action: decision(recommendation: null)),
        owner: 'a',
      );
      expect(value.decision!.level, isNull);
      expect(
        value.decision!.createdAt.toIso8601String(),
        '2026-10-12T11:00:00.000Z',
      );
      expect(
        () => SafetyAssessment.fromApi({...safety(), 'evaluated_at': null}),
        throwsFormatException,
      );
      expect(
        () => SafetyAssessment.fromApi({
          ...safety(),
          'evidence_status': {'risk_screen_complete': 'true'},
        }),
        throwsFormatException,
      );
    },
  );

  for (final target in ['safety', 'doctor/review-status']) {
    for (final failure in ['401', '403', '503', 'offline', 'timeout']) {
      test(
        '$target $failure fails honestly, retains only stale memory and retries',
        () async {
          var fail = false;
          final controller = ClinicalController(api);
          await http.runWithClient(
            () async {
              await login();
              expect(await controller.refresh(), isTrue);
              fail = true;
              expect(await controller.refresh(), isFalse);
              if (failure == '401') {
                expect(api.isAuthenticated, isFalse);
                expect(controller.safety.value, isNull);
                expect(controller.review.value, isNull);
              } else {
                if (target == 'safety') {
                  expect(controller.safety.phase, ClinicalPhase.failed);
                  expect(controller.safety.stale, isTrue);
                  expect(controller.review.phase, ClinicalPhase.ready);
                } else {
                  expect(controller.review.phase, ClinicalPhase.failed);
                  expect(controller.review.stale, isTrue);
                  expect(controller.safety.phase, ClinicalPhase.ready);
                }
              }
              expect(
                controller.safety.error ?? controller.review.error,
                isNot(contains('synthetic-secret')),
              );
              fail = false;
              if (!api.isAuthenticated) await login();
              expect(await controller.refresh(), isTrue);
              expect(controller.safety.stale, isFalse);
              expect(controller.review.stale, isFalse);
              controller.dispose();
              await api.init();
            },
            () => isolated((r) async {
              if (r.url.path.endsWith('/auth/login')) return auth('a');
              if (r.url.path.endsWith('/users/me')) return user('a');
              if (fail && r.url.path.endsWith('/$target')) {
                if (failure == 'offline') {
                  throw http.ClientException('synthetic-secret');
                }
                if (failure == 'timeout') {
                  throw TimeoutException('synthetic-secret');
                }
                return http.Response('synthetic-secret', int.parse(failure));
              }
              return response(
                r.url.path.endsWith('/safety') ? safety() : review(),
              );
            }),
          );
        },
      );
    }
  }
  for (final fixture in ['', '{}', 'null', '[1]', '{']) {
    test(
      'malformed/empty response $fixture is not an empty clinical success',
      () async {
        final controller = ClinicalController(api);
        await http.runWithClient(
          () async {
            await login();
            expect(await controller.refresh(), isFalse);
            expect(controller.safety.value, isNull);
            expect(controller.review.value, isNull);
            expect(controller.safety.phase, ClinicalPhase.failed);
            controller.dispose();
            await api.init();
          },
          () => isolated((r) async {
            if (r.url.path.endsWith('/auth/login')) return auth('a');
            if (r.url.path.endsWith('/users/me')) return user('a');
            return http.Response(fixture, 200);
          }),
        );
      },
    );
  }
  for (final mode in ['unauthenticated', 'unaccepted', 'doctor']) {
    test('patient read guard rejects $mode before clinical HTTP', () async {
      var clinicalCalls = 0;
      final controller = ClinicalController(api);
      await http.runWithClient(
        () async {
          if (mode != 'unauthenticated') {
            await login(
              owner: 'a',
              role: mode == 'doctor' ? 'doctor' : 'patient',
            );
          }
          expect(controller.allowed, isFalse);
          expect(await controller.refresh(), isFalse);
          await expectLater(
            api.getPatientSafety(generation: api.sessionGeneration),
            throwsA(isA<ClinicalRequestException>()),
          );
          expect(clinicalCalls, 0);
          controller.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) {
            return auth('a', role: mode == 'doctor' ? 'doctor' : 'patient');
          }
          if (r.url.path.endsWith('/users/me')) {
            return user(
              'a',
              accepted: mode != 'unaccepted',
              role: mode == 'doctor' ? 'doctor' : 'patient',
            );
          }
          clinicalCalls++;
          return response(safety());
        }),
      );
    });
  }
  for (final target in ['safety', 'doctor/review-status']) {
    for (final switchAccount in [false, true]) {
      for (final code in [200, 401]) {
        test(
          'late $target/$code cannot revive logout or switch=$switchAccount even with reused token',
          () async {
            final pending = Completer<http.Response>();
            var owner = 'a';
            var held = true;
            final controller = ClinicalController(api);
            await http.runWithClient(
              () async {
                await login();
                final old = controller.refresh();
                await Future<void>.delayed(Duration.zero);
                await api.logout();
                held = false;
                if (switchAccount) {
                  owner = 'b';
                  await login(owner: 'b');
                  expect(await controller.refresh(), isTrue);
                }
                pending.complete(
                  code == 401
                      ? http.Response('', 401)
                      : response(
                          target == 'safety'
                              ? safety(
                                  status: 'urgent',
                                  guidance: 'OLD ACCOUNT',
                                )
                              : review(state: 'reviewed', action: decision()),
                        ),
                );
                expect(await old, isFalse);
                expect(api.isAuthenticated, switchAccount);
                if (switchAccount) {
                  expect(controller.review.value!.patientId, 'b');
                  expect(controller.safety.value!.guidance, 'NEW ACCOUNT');
                } else {
                  expect(controller.safety.value, isNull);
                  expect(controller.review.value, isNull);
                }
                controller.dispose();
                await api.init();
              },
              () => isolated((r) async {
                if (r.url.path.endsWith('/auth/login')) return auth(owner);
                if (r.url.path.endsWith('/users/me')) return user(owner);
                if (r.url.path.endsWith('/auth/logout')) {
                  return http.Response('', 204);
                }
                if (held && r.url.path.endsWith('/$target')) {
                  return pending.future;
                }
                return response(
                  r.url.path.endsWith('/safety')
                      ? safety(guidance: 'NEW ACCOUNT')
                      : review(owner: owner),
                );
              }),
            );
          },
        );
      }
    }
  }
  test('newer refresh wins independently over both late old reads', () async {
    final a = Completer<http.Response>(), b = Completer<http.Response>();
    var old = true;
    final controller = ClinicalController(api);
    await http.runWithClient(
      () async {
        await login();
        final first = controller.refresh();
        await Future<void>.delayed(Duration.zero);
        old = false;
        expect(await controller.refresh(), isTrue);
        a.complete(response(safety(status: 'urgent', guidance: 'OLD')));
        b.complete(response(review(state: 'reviewed', action: decision())));
        expect(await first, isFalse);
        expect(controller.safety.value!.guidance, 'LATEST');
        expect(controller.review.value!.decision, isNull);
        controller.dispose();
        await api.init();
      },
      () => isolated((r) async {
        if (r.url.path.endsWith('/auth/login')) return auth('a');
        if (r.url.path.endsWith('/users/me')) return user('a');
        if (old) return r.url.path.endsWith('/safety') ? a.future : b.future;
        return response(
          r.url.path.endsWith('/safety')
              ? safety(guidance: 'LATEST')
              : review(),
        );
      }),
    );
  });

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      for (final reduced in [false, true]) {
        testWidgets(
          'accessible clinical detail dark=$dark large=$large reduced=$reduced',
          (tester) async {
            tester.view.physicalSize = const Size(360, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final controller = ClinicalController(api);
            await http.runWithClient(
              () async {
                await login();
                await controller.refresh();
                await tester.pumpWidget(
                  MaterialApp(
                    theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                    locale: const Locale('en'),
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        disableAnimations: reduced,
                        textScaler: TextScaler.linear(large ? 2 : 1),
                      ),
                      child: child!,
                    ),
                    home: ClinicalStatusScreen(controller: controller),
                  ),
                );
                await tester.pumpAndSettle();
                if (large) {
                  await tester.scrollUntilVisible(
                    find.text('Urgent medical assessment recommended'),
                    180,
                  );
                }
                expect(
                  find.text('Urgent medical assessment recommended'),
                  findsOneWidget,
                );
                expect(find.byIcon(Icons.emergency_outlined), findsOneWidget);
                expect(
                  find.byWidgetPredicate(
                    (w) => w is Semantics && w.properties.liveRegion == true,
                  ),
                  findsWidgets,
                );
                expect(
                  find.text(
                    'No current patient-visible clinician decision. This does not mean clinician approval.',
                  ),
                  findsOneWidget,
                );
                expect(find.textContaining('Chat with doctor'), findsNothing);
                expect(find.text('Doctor approved'), findsNothing);
                final refresh = find.byKey(const Key('refreshClinicalStatus'));
                await tester.ensureVisible(refresh);
                await tester.pumpAndSettle();
                expect(refresh.hitTestable(), findsOneWidget);
                expect(tester.takeException(), isNull);
                await tester.pumpWidget(const SizedBox());
                controller.dispose();
                await api.init();
              },
              () => isolated((r) async {
                if (r.url.path.endsWith('/auth/login')) return auth('a');
                if (r.url.path.endsWith('/users/me')) return user('a');
                return response(
                  r.url.path.endsWith('/safety')
                      ? safety(status: 'urgent')
                      : review(evaluation: safety(status: 'urgent')),
                );
              }),
            );
          },
        );
      }
    }
  }

  for (final scenario in [
    'clinician_first',
    'urgent_engine',
    'embedded_urgent',
    'unsupported_urgent',
    'no_assessment',
    'unknown',
    'private_latest',
  ]) {
    testWidgets('source precedence and honest clinical view: $scenario', (
      tester,
    ) async {
      final controller = ClinicalController(api);
      var engine = safety();
      var status = review();
      switch (scenario) {
        case 'clinician_first':
          status = review(
            state: 'follow_up_needed',
            action: decision(state: 'follow_up_needed'),
          );
        case 'urgent_engine':
          engine = safety(status: 'urgent');
          status = review(
            state: 'reviewed',
            action: {
              ...decision(recommendation: 'track'),
              'lower_than_current_safety': true,
              'urgent_safety_preserved': true,
            },
            evaluation: engine,
          );
        case 'embedded_urgent':
          status = review(evaluation: safety(status: 'urgent'));
        case 'unsupported_urgent':
          engine = {
            ...safety(status: 'urgent'),
            'engine_version': 'future-engine',
          };
          status = review(evaluation: engine);
        case 'no_assessment':
          engine = safety(absent: true);
          status = review(evaluation: engine);
        case 'unknown':
          engine = {
            ...safety(status: 'future_status'),
            'engine_version': 'future-engine',
          };
          status = review(state: 'future_workflow', evaluation: engine);
        case 'private_latest':
          status = {
            ...review(state: 'follow_up_needed'),
            'latest_sequence': 2,
            'changed_at': '2026-10-12T11:00:00',
            'history': [decision()..['rationale'] = 'OLD VISIBLE DECISION'],
          };
      }
      await http.runWithClient(
        () async {
          await login();
          await controller.refresh();
          await tester.pumpWidget(
            MaterialApp(
              theme: DermaireTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(
                  child: ClinicalHomePanel(controller: controller),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          switch (scenario) {
            case 'clinician_first':
              expect(
                tester.getTopLeft(find.text('Clinician review')).dy,
                lessThan(tester.getTopLeft(find.text('Safety Engine')).dy),
              );
            case 'urgent_engine':
              expect(
                tester.getTopLeft(find.text('Safety Engine')).dy,
                lessThan(tester.getTopLeft(find.text('Clinician review')).dy),
              );
              expect(
                find.text(
                  'The server preserves Safety Engine guidance independently of this clinician recommendation.',
                ),
                findsOneWidget,
              );
            case 'embedded_urgent':
              expect(
                tester
                    .getTopLeft(
                      find.text('Safety Engine · clinician-status read'),
                    )
                    .dy,
                lessThan(tester.getTopLeft(find.text('Safety Engine')).dy),
              );
            case 'unsupported_urgent':
              expect(
                find.text('Unsupported safety format — server reports urgent'),
                findsOneWidget,
              );
              expect(find.byIcon(Icons.emergency_outlined), findsOneWidget);
            case 'no_assessment':
              expect(
                find.text(
                  'Current symptom assessment unavailable: evidence is absent or outdated.',
                ),
                findsOneWidget,
              );
            case 'unknown':
              expect(find.text('Unsupported safety status'), findsOneWidget);
              expect(find.text('Unsupported review status'), findsOneWidget);
            case 'private_latest':
              expect(find.textContaining('OLD VISIBLE'), findsNothing);
              expect(
                find.textContaining('No current patient-visible'),
                findsOneWidget,
              );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          return response(r.url.path.endsWith('/safety') ? engine : status);
        }),
      );
    });
  }

  testWidgets(
    'real 20s timeout, retry, stale labelling and late response stay honest',
    (tester) async {
      final controller = ClinicalController(api);
      var holding = false;
      var fail = false;
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await login();
          await controller.refresh();
          await tester.pumpWidget(
            MaterialApp(home: ClinicalStatusScreen(controller: controller)),
          );
          await tester.pumpAndSettle();
          holding = true;
          final waiting = controller.refresh();
          await tester.pump();
          expect(find.textContaining('Previously retrieved'), findsWidgets);
          await tester.pump(const Duration(seconds: 21));
          expect(await waiting, isFalse);
          await tester.pumpAndSettle();
          expect(find.textContaining('timed out'), findsOneWidget);
          holding = false;
          fail = true;
          await tester.ensureVisible(
            find.byKey(const Key('refreshClinicalStatus')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('refreshClinicalStatus')));
          await tester.pumpAndSettle();
          expect(find.textContaining('unavailable'), findsWidgets);
          expect(controller.safety.stale, isTrue);
          fail = false;
          await tester.ensureVisible(
            find.byKey(const Key('refreshClinicalStatus')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('refreshClinicalStatus')));
          await tester.pumpAndSettle();
          expect(controller.safety.stale, isFalse);
          pending.complete(
            response(safety(status: 'urgent', guidance: 'LATE PAYLOAD')),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('LATE PAYLOAD'), findsNothing);
          await api.logout();
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Synthetic server guidance'),
            findsNothing,
          );
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          if (r.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }
          if (r.url.path.endsWith('/safety')) {
            if (holding) return pending.future;
            if (fail) return http.Response('', 503);
            return response(safety());
          }
          return response(review());
        }),
      );
    },
  );
  testWidgets(
    'Home keeps navigation/check-in data unchanged and opens real read-only detail',
    (tester) async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login();
          await state.clinical.refresh();
          await state.productController.load();
          await tester.pumpWidget(MaterialApp(home: AppShell(state: state)));
          await tester.pumpAndSettle();
          expect(AppShell.labels, [
            'Home',
            'Experiment',
            'Products',
            'Rewards',
            'Reports',
            'Profile',
          ]);
          expect(state.home.current, isNull);
          expect(state.todayCheckedIn, isFalse);
          await tester.ensureVisible(find.byKey(const Key('clinicalDetails')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('clinicalDetails')));
          await tester.pumpAndSettle();
          expect(find.byType(ClinicalStatusScreen), findsOneWidget);
          expect(find.text('Server workflow: pending'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          await api.init();
        },
        () => isolated((r) async {
          if (r.url.path.endsWith('/auth/login')) return auth('a');
          if (r.url.path.endsWith('/users/me')) return user('a');
          if (r.url.path.endsWith('/products') ||
              r.url.path.endsWith('/experiments')) {
            return http.Response('[]', 200);
          }
          return response(
            r.url.path.endsWith('/safety')
                ? safety()
                : review(state: 'pending'),
          );
        }),
      );
    },
  );
  testWidgets(
    'initial pending reads expose urgent engine immediately before clinician read completes',
    (tester) async {
      final controller = ClinicalController(api);
      final s = Completer<http.Response>(), r = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await login();
          await tester.pumpWidget(
            MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
              home: ClinicalStatusScreen(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Safety guidance loading'), findsOneWidget);
          expect(find.text('Clinician status loading'), findsOneWidget);
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(
            tester
                .widget<OutlinedButton>(
                  find.byKey(const Key('refreshClinicalStatus')),
                )
                .onPressed,
            isNull,
          );
          s.complete(response(safety(status: 'urgent')));
          await tester.pumpAndSettle();
          expect(
            find.text('Urgent medical assessment recommended'),
            findsOneWidget,
          );
          expect(find.text('Clinician status loading'), findsOneWidget);
          r.complete(response(review(evaluation: safety(status: 'urgent'))));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await api.init();
        },
        () => isolated((q) async {
          if (q.url.path.endsWith('/auth/login')) return auth('a');
          if (q.url.path.endsWith('/users/me')) return user('a');
          return q.url.path.endsWith('/safety') ? s.future : r.future;
        }),
      );
    },
  );

  testWidgets(
    'app resume marks memory stale and refreshes without switching English or credentials',
    (tester) async {
      var hold = false;
      final s = Completer<http.Response>(), r = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const DermaireApp());
          await tester.pumpAndSettle();
          final state = tester
              .widget<WelcomeScreen>(find.byType(WelcomeScreen))
              .state;
          await login();
          await state.clinical.refresh();
          hold = true;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          expect(state.clinical.safety.stale, isTrue);
          expect(state.clinical.loading, isTrue);
          s.complete(response(safety(guidance: 'REFRESHED AFTER RESUME')));
          r.complete(response(review()));
          await tester.pumpAndSettle();
          expect(
            state.clinical.safety.value!.guidance,
            'REFRESHED AFTER RESUME',
          );
          expect(state.clinical.safety.stale, isFalse);
          expect(
            tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
            const Locale('en'),
          );
          await tester.pumpWidget(const SizedBox());
          await api.init();
        },
        () => isolated((q) async {
          if (q.url.path.endsWith('/auth/login')) return auth('a');
          if (q.url.path.endsWith('/users/me')) return user('a');
          if (hold) return q.url.path.endsWith('/safety') ? s.future : r.future;
          return response(q.url.path.endsWith('/safety') ? safety() : review());
        }),
      );
    },
  );

  test(
    'verified profile change refreshes guidance without interpreting health fields locally',
    () async {
      final state = DermaireState();
      var updated = false;
      var reads = 0;
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await state.clinical.refresh();
          expect(reads, 2);
          updated = true;
          await state.account.hydrate(reuseConsent: false);
          await Future<void>.delayed(Duration.zero);
          expect(reads, 4);
          expect(
            state.clinical.safety.value!.guidance,
            'AFTER PROFILE READBACK',
          );
          state.dispose();
          await api.init();
        },
        () => isolated((q) async {
          if (q.url.path.endsWith('/auth/login')) return auth('a');
          if (q.url.path.endsWith('/users/me')) return user('a');
          reads++;
          return response(
            q.url.path.endsWith('/safety')
                ? safety(
                    guidance: updated
                        ? 'AFTER PROFILE READBACK'
                        : 'BEFORE PROFILE READBACK',
                  )
                : review(),
          );
        }),
      );
    },
  );

  testWidgets(
    'confirmed report-only check-in refreshes clinical reads without fabricating metrics or Home completion',
    (tester) async {
      final state = DermaireState();
      var recorded = false;
      await http.runWithClient(
        () async {
          await login();
          await state.clinical.refresh();
          await tester.pumpWidget(
            MaterialApp(home: CameraScreen(state: state)),
          );
          await tester.pumpAndSettle();
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>).first,
              )
              .onChanged!('same');
          await tester.pump();
          await tester.scrollUntilVisible(
            find.text('Save check-in'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Save check-in'));
          await tester.pumpAndSettle();
          expect(recorded, isTrue);
          expect(find.byType(CheckInCompleteScreen), findsOneWidget);
          expect(state.clinical.safety.value!.level, SafetyLevel.doctorReview);
          expect(state.home.current, isNull);
          expect(state.baseline.completedDays, isNull);
          expect(state.todayCheckedIn, isFalse);
          await tester.scrollUntilVisible(
            find.text('Clinician review recommended'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Clinician review recommended'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          state.dispose();
          await api.init();
        },
        () => isolated((q) async {
          if (q.url.path.endsWith('/auth/login')) return auth('a');
          if (q.url.path.endsWith('/users/me')) return user('a');
          if (q.url.path.endsWith('/checkins') && q.method == 'POST') {
            recorded = true;
            expect(q.body, contains('overall_change'));
            expect(q.body, isNot(contains('hydration_score')));
            return http.Response(
              jsonEncode({
                'id': 'synthetic-observation',
                'created_at': '2026-10-12T12:00:00Z',
                'ai_vision_analysis': {'measurement_source': 'none'},
                'observation': {
                  'schema_version': 1,
                  'user_reported': {
                    'overall_change': 'same',
                    'symptoms': [],
                    'routine_status': null,
                  },
                  'daily_context_date': '2026-10-12',
                  'daily_context_id': null,
                  'provenance': {'report': 'user_reported'},
                },
              }),
              201,
            );
          }
          if (q.url.path.endsWith('/safety')) {
            return response(
              safety(status: recorded ? 'doctor_review' : 'track'),
            );
          }
          if (q.url.path.endsWith('/doctor/review-status')) {
            return response(
              review(
                evaluation: safety(
                  status: recorded ? 'doctor_review' : 'track',
                ),
              ),
            );
          }
          return http.Response('', 503);
        }),
      );
    },
  );
  test(
    'invalid or timezone-free safety timestamps cannot invent record dates',
    () {
      for (final invalid in [
        '2026-02-30T12:00:00Z',
        '2026-13-01T12:00:00Z',
        '2026-10-12T24:00:00Z',
        '2026-10-12T12:00:00',
        '2026-10-12T12:00:00+29:00',
      ]) {
        expect(
          () =>
              SafetyAssessment.fromApi({...safety(), 'evaluated_at': invalid}),
          throwsFormatException,
        );
      }
    },
  );
}
