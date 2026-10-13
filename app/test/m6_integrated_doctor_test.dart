import 'dart:async';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/capture/private_capture_image.dart';
import 'package:dermaire_app/capture/capture_history_models.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/doctor_portal.dart';
import 'package:dermaire_app/doctor/doctor_clinical_ui.dart';
import 'package:dermaire_app/doctor/doctor_evidence_ui.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;
import 'guided_capture_test.dart' as g;
import 'm6_clinical_records_test.dart' as e;
import 'm6_clinical_reviews_test.dart' as r;

final api = ApiService.instance;

class JourneyWire extends r.ClinicalWire {
  JourneyWire() {
    accepted = false;
  }
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    if (request.url.path.endsWith('/auth/google')) {
      requests.add(request);
      return f.json({
        'access_token': 'reused-doctor-token',
        'user_id': owner,
        'role': role,
        'expires_in': 3600,
      });
    }
    return super.call(request);
  }
}

Future<void> scroll(WidgetTester t, Finder finder) => t.scrollUntilVisible(
  finder.hitTestable(),
  200,
  scrollable: find.byType(Scrollable).first,
);
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  test(
    'decoded image memory is bounded across separate doctor scopes',
    () async {
      final wire = r.ClinicalWire();
      await wire.run(() async {
        await wire.login();
        final bytes = g.pngBytes(width: 1600, height: 1600);
        final decoders = List.generate(
          5,
          (_) => PrivateCaptureImages(
            api,
            reader: (_, _) async => PrivateImageBytes(bytes, 'image/png'),
            authorization: (_) => api.canReadDoctorWorkspace,
          ),
        );
        for (final images in decoders.take(4)) {
          await images.load(
            'synthetic',
            api.sessionGeneration,
            1600,
            active: () => true,
          );
        }
        expect(decoders.first.decodedPixels, 10240000);
        await expectLater(
          decoders.last.load(
            'synthetic',
            api.sessionGeneration,
            1600,
            active: () => true,
          ),
          throwsFormatException,
        );
        for (final images in decoders) {
          images.dispose();
        }
        expect(decoders.first.decodedPixels, 0);
      });
    },
  );
  for (final lifecycle in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('clinical $lifecycle clears confirmed model before resuming', (
      t,
    ) async {
      final wire = r.ClinicalWire();
      await wire.run(() async {
        final v = await r.editor(wire);
        await t.pumpWidget(
          MaterialApp(home: DoctorClinicalScreen(connection: v.$2)),
        );
        await t.pumpAndSettle();
        // Inactive is the frame-capable transition before the platform pauses frames.
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        await t.pump();
        t.binding.handleAppLifecycleStateChanged(lifecycle);
        expect(find.text('Notes & reviews'), findsNothing);
        expect(wire.posts, 0);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpAndSettle();
        expect(find.text('Notes & reviews'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        r.clean(v);
        await api.logout();
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'clinical choice controls preserve authorized draft dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final wire = r.ClinicalWire();
        await wire.run(() async {
          final v = await r.editor(wire);
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: DoctorClinicalScreen(connection: v.$2),
            ),
          );
          await t.pumpAndSettle();
          await scroll(t, find.byKey(const Key('clinicalNote')));
          await t.enterText(
            find.byKey(const Key('clinicalNote')),
            'Keep this draft while choosing priority.',
          );
          await scroll(t, find.widgetWithText(ChoiceChip, 'urgent').first);
          await t.tap(find.widgetWithText(ChoiceChip, 'urgent').first);
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const Key('clinicalNote')).hitTestable(),
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            t
                .widget<TextField>(find.byKey(const Key('clinicalNote')))
                .controller!
                .text,
            'Keep this draft while choosing priority.',
          );
          expect(wire.posts, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          r.clean(v);
          await api.logout();
        });
      },
    );
  }
  for (final kind in ['clinical', 'evidence']) {
    testWidgets('same $kind widget binds a new doctor/patient connection', (
      t,
    ) async {
      final wire = kind == 'clinical' ? r.ClinicalWire() : e.EvidenceWire();
      await wire.run(() async {
        if (wire is r.ClinicalWire) {
          final a = await r.editor(wire);
          await t.pumpWidget(
            MaterialApp(home: DoctorClinicalScreen(connection: a.$2)),
          );
          await t.pumpAndSettle();
          await api.init();
          wire.owner = 'doctor-b';
          wire.patient = 'patient-b';
          final b = await r.editor(wire);
          await t.pumpWidget(
            MaterialApp(home: DoctorClinicalScreen(connection: b.$2)),
          );
          await t.pumpAndSettle();
          await scroll(t, find.byKey(const Key('addClinicalNote')));
          expect(
            t
                .widget<FilledButton>(find.byKey(const Key('addClinicalNote')))
                .onPressed,
            isNotNull,
          );
          expect(
            wire.requests.any(
              (q) => q.url.path.endsWith('/doctor/patients/patient-b/reviews'),
            ),
            true,
          );
          await t.pumpWidget(const SizedBox());
          r.clean(a);
          r.clean(b);
        } else if (wire is e.EvidenceWire) {
          final a = await e.records(wire);
          await t.pumpWidget(
            MaterialApp(home: DoctorEvidenceScreen(connection: a.$2)),
          );
          await t.pumpAndSettle();
          await api.init();
          wire.owner = 'doctor-b';
          wire.patient = 'patient-b';
          final b = await e.records(wire);
          final before = wire.requests.length;
          await t.pumpWidget(
            MaterialApp(home: DoctorEvidenceScreen(connection: b.$2)),
          );
          await t.pumpAndSettle();
          expect(
            wire.requests
                .skip(before)
                .any(
                  (q) => q.url.path.endsWith(
                    '/doctor/patients/patient-b/timeline',
                  ),
                ),
            true,
          );
          expect(find.byType(RawImage), findsNothing);
          await t.pumpWidget(const SizedBox());
          e.cleanup(a);
          e.cleanup(b);
        }
        await api.logout();
        expect(t.takeException(), isNull);
      });
    });
  }
  testWidgets('disposed connection closes existing doctor pixels', (t) async {
    final wire = e.EvidenceWire();
    await wire.run(() async {
      final v = await e.records(wire);
      await t.pumpWidget(
        MaterialApp(home: DoctorEvidenceScreen(connection: v.$2)),
      );
      await t.pumpAndSettle();
      await scroll(t, find.text('Open private image'));
      await t.tap(find.text('Open private image'));
      await t.pump();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await t.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);
      v.$2.dispose();
      await t.pumpAndSettle();
      expect(find.byType(RawImage), findsNothing);
      await t.pumpWidget(const SizedBox());
      v.$3.dispose();
      v.$1.dispose();
      await api.logout();
    });
  });
  for (final google in [false, true]) {
    testWidgets(
      'real mocked doctor entry google=$google must accept and stays out of patient APIs',
      (t) async {
        final wire = JourneyWire();
        final state = DermaireState();
        await wire.run(() async {
          await t.pumpWidget(
            MaterialApp(
              home: google
                  ? SignInScreen(
                      state: state,
                      googleSignIn: () async => 'synthetic-google-token',
                    )
                  : DoctorSignInScreen(state: state),
            ),
          );
          if (google) {
            await t.tap(find.text('Continue with Google'));
          } else {
            await t.enterText(
              find.byKey(const Key('doctorEmail')),
              'doctor@example.invalid',
            );
            await t.enterText(
              find.byKey(const Key('doctorPassword')),
              'synthetic',
            );
            await t.tap(find.byKey(const Key('doctorSignIn')));
          }
          await t.pumpAndSettle();
          expect(find.byType(SafetyResponsibilityScreen), findsOneWidget);
          expect(find.byType(DoctorPortalScreen), findsNothing);
          expect(api.canReadDoctorWorkspace, false);
          await t.drag(
            find.byKey(const Key('safetyScroll')),
            const Offset(0, -2000),
          );
          await t.pumpAndSettle();
          await scroll(t, find.byKey(const Key('acceptSafetyButton')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(const Key('acceptSafetyButton')));
          await t.pumpAndSettle();
          expect(find.byType(DoctorPortalScreen), findsOneWidget);
          expect(find.byType(AppShell), findsNothing);
          expect(
            wire.requests
                .where((q) => q.url.path.endsWith('/auth/accept-safety'))
                .length,
            1,
          );
          expect(
            wire.requests.any(
              (q) => [
                '/api/v1/home',
                '/api/v1/products',
                '/api/v1/baseline',
                '/api/v1/chat',
              ].contains(q.url.path),
            ),
            false,
          );
          await scroll(t, find.text('Real Patient'));
          await t.tap(find.text('Real Patient'));
          await t.pumpAndSettle();
          expect(find.byType(PatientDetailScreen), findsOneWidget);
          await scroll(t, find.text('Notes and clinical reviews'));
          await t.tap(find.text('Notes and clinical reviews'));
          await t.pumpAndSettle();
          expect(find.byType(DoctorClinicalScreen), findsOneWidget);
          await scroll(t, find.byKey(const Key('clinicalNote')));
          await t.enterText(
            find.byKey(const Key('clinicalNote')),
            'Integrated clinical record from a verified doctor.',
          );
          await scroll(t, find.byKey(const Key('addClinicalNote')));
          await t.tap(find.byKey(const Key('addClinicalNote')));
          await t.pumpAndSettle();
          expect(wire.posts, 1);
          expect(wire.saved.single['patient_visible'], false);
          await t.pumpWidget(const SizedBox());
          await api.logout();
        });
        state.dispose();
      },
    );
  }
  for (final kind in ['clinical', 'evidence']) {
    for (final mode in ['covered', 'background', 'logout', 'switch account']) {
      testWidgets('$kind $mode clears old drafts and data', (t) async {
        final nav = GlobalKey<NavigatorState>();
        if (kind == 'clinical') {
          final wire = r.ClinicalWire();
          await wire.run(() async {
            final v = await r.editor(wire);
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: nav,
                home: DoctorClinicalScreen(connection: v.$2),
              ),
            );
            await t.pumpAndSettle();
            await scroll(t, find.byKey(const Key('clinicalNote')));
            await t.enterText(
              find.byKey(const Key('clinicalNote')),
              'Private draft that must be cleared.',
            );
            if (mode == 'covered') {
              nav.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Other route')),
                ),
              );
              await t.pumpAndSettle();
              nav.currentState!.pop();
            }
            if (mode == 'background') {
              t.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              await t.pump();
              t.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            }
            if (mode == 'logout') await api.logout();
            if (mode == 'switch account') {
              await api.init();
              wire.owner = 'doctor-b';
              await wire.login();
            }
            await t.pumpAndSettle();
            expect(
              find.text('Private draft that must be cleared.'),
              findsNothing,
            );
            expect(wire.posts, 0);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            r.clean(v);
            await api.logout();
          });
        } else {
          final wire = e.EvidenceWire();
          await wire.run(() async {
            final v = await e.records(wire);
            await t.pumpWidget(
              MaterialApp(
                navigatorKey: nav,
                home: DoctorEvidenceScreen(connection: v.$2),
              ),
            );
            await t.pumpAndSettle();
            await scroll(t, find.text('Open private image'));
            await t.tap(find.text('Open private image'));
            await t.pump();
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)),
            );
            await t.pumpAndSettle();
            expect(find.byType(RawImage), findsOneWidget);
            if (mode == 'covered') {
              nav.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Other route')),
                ),
              );
              await t.pumpAndSettle();
              nav.currentState!.pop();
            }
            if (mode == 'background') {
              t.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
              await t.pump();
              expect(find.byType(RawImage), findsNothing);
              t.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.resumed,
              );
            }
            if (mode == 'logout') await api.logout();
            if (mode == 'switch account') {
              await api.init();
              wire.owner = 'doctor-b';
              await wire.login();
            }
            await t.pumpAndSettle();
            expect(find.byType(RawImage), findsNothing);
            expect(wire.imageReads, 1);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            e.cleanup(v);
            await api.logout();
          });
        }
      });
    }
  }
  for (final mode in ['covered', 'background']) {
    testWidgets('late note while $mode has no resend or old success', (
      t,
    ) async {
      final wire = r.ClinicalWire(), nav = GlobalKey<NavigatorState>();
      await wire.run(() async {
        final v = await r.editor(wire);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: DoctorClinicalScreen(connection: v.$2),
          ),
        );
        await t.pumpAndSettle();
        await scroll(t, find.byKey(const Key('clinicalNote')));
        await t.enterText(
          find.byKey(const Key('clinicalNote')),
          'A late clinical note belongs to this patient.',
        );
        wire.writeDelay = Completer();
        await scroll(t, find.byKey(const Key('addClinicalNote')));
        await t.tap(find.byKey(const Key('addClinicalNote')));
        await t.pump();
        expect(wire.posts, 1);
        if (mode == 'covered') {
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Other route')),
            ),
          );
          await t.pumpAndSettle();
        } else {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
          await t.pump();
        }
        final row = {
          ...wire.note('A late clinical note belongs to this patient.'),
          ...wire.payloads.single,
          'id': 'note-1',
        };
        wire.saved.add(row);
        wire.writeDelay!.complete(f.json(row, 201));
        await t.pump();
        expect(wire.posts, 1);
        if (mode == 'covered') {
          nav.currentState!.pop();
        } else {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        await t.pumpAndSettle();
        expect(wire.posts, 1);
        expect(
          find.text('Clinical record confirmed by server readback.'),
          findsNothing,
        );
        await scroll(t, find.byKey(const Key('clinicalNote')));
        expect(
          t
              .widget<TextField>(find.byKey(const Key('clinicalNote')))
              .controller!
              .text,
          isEmpty,
        );
        await t.pumpWidget(const SizedBox());
        r.clean(v);
        await api.logout();
      });
    });
  }
  for (final mode in ['back to patient', 'grant denied', 'session ended']) {
    test(
      'return to previous patient $mode requires new server access',
      () async {
        final wire = r.ClinicalWire();
        await wire.run(() async {
          final v = await r.editor(wire);
          v.$1.selectPatient('not-authorized');
          expect(v.$2.confirmed, false);
          if (mode == 'grant denied') wire.mode = 'revoked';
          if (mode == 'session ended') await api.logout();
          expect(await v.$2.resumeAccess(), mode == 'back to patient');
          expect(v.$2.confirmed, mode == 'back to patient');
          r.clean(v);
        });
      },
    );
  }
  for (final dark in [false, true]) {
    testWidgets(
      'integrated doctor detail dark=$dark at 320px/200% readable and labeled',
      (t) async {
        t.view.physicalSize = const Size(320, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final wire = r.ClinicalWire();
        await wire.run(() async {
          final v = await r.editor(wire);
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: PatientDetailScreen(
                controller: v.$1,
                patient: v.$1.visible.single,
              ),
            ),
          );
          await t.pumpAndSettle();
          await scroll(t, find.text('Notes and clinical reviews'));
          final semantics = t.ensureSemantics();
          expect(t, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
          expect(t.takeException(), isNull);
          expect(wire.posts, 0);
          expect(find.text('Send message'), findsNothing);
          await t.pumpWidget(const SizedBox());
          r.clean(v);
          await api.logout();
        });
      },
    );
  }
  testWidgets('workspace background returns through profile and live list', (
    t,
  ) async {
    final wire = r.ClinicalWire();
    await wire.run(() async {
      await wire.login();
      await t.pumpWidget(
        const MaterialApp(
          home: DoctorPortalScreen(
            session: AccessSession(userId: 'doctor-1', role: UserRole.doctor),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Real Patient'), findsOneWidget);
      final before = wire.requests.length;
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.text('Real Patient'), findsNothing);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pumpAndSettle();
      expect(find.text('Real Patient'), findsOneWidget);
      expect(wire.requests.length, greaterThan(before));
      await t.pumpWidget(const SizedBox());
      await api.logout();
    });
  });
}
