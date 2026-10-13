import 'dart:async';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/doctor_portal.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

final api = ApiService.instance;
const session = AccessSession(userId: 'doctor-1', role: UserRole.doctor);
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final role in ['doctor', 'patient', 'admin', 'support', 'unknown']) {
    test('profile-confirmed $role controls doctor resource access', () async {
      final wire = f.DoctorWire()..role = role;
      await wire.run(() async {
        await api.login(
          email: 'synthetic@example.invalid',
          password: 'synthetic',
        );
        expect(api.canReadDoctorWorkspace, false);
        await expectLater(
          api.getDoctorPatients(),
          throwsA(isA<ApiException>()),
        );
        await api.readSafetyAcceptance();
        expect(api.canReadDoctorWorkspace, role == 'doctor');
        final c = DoctorWorkspaceController(session, patientData: [wire.row]);
        expect(c.visible, isEmpty); // Supplied data/local IDs never hydrate.
        if (role == 'doctor') {
          await c.refresh();
          expect(c.visible.single.experiment, 'No active experiment recorded');
        } else {
          await c.refresh();
          expect(c.visible, isEmpty);
          expect(
            wire.requests.where((r) => r.url.path.contains('/doctor/')),
            isEmpty,
          );
        }
        c.dispose();
      });
    });
  }
  test(
    'server profile role mismatch cannot use doctor token declaration',
    () async {
      final wire = f.DoctorWire();
      await wire.run(() async {
        await api.login(
          email: 'synthetic@example.invalid',
          password: 'synthetic',
          requiredRole: 'doctor',
        );
        wire.role = 'patient';
        await api.readSafetyAcceptance();
        expect(api.canReadDoctorWorkspace, false);
        await expectLater(
          api.getDoctorPatients(),
          throwsA(isA<ApiException>()),
        );
      });
    },
  );
  for (final field in [
    'patient_id',
    'access',
    'priority',
    'active_products_count',
    'safety',
  ]) {
    test('doctor patient mapping rejects missing $field', () {
      final row = f.DoctorWire().row..[field] = null;
      expect(() => DoctorPatient.fromApi(row, 'doctor-1'), throwsA(anything));
    });
  }
  for (final status in ['pending', 'revoked', 'expired']) {
    test('$status grant never authorizes a clinical view', () {
      final wire = f.DoctorWire();
      final grant = DoctorGrant.fromApi(
        wire.grant(status),
        patient: wire.patient,
        doctor: wire.owner,
      );
      expect(grant.active(DateTime.utc(2026, 10, 1)), false);
    });
  }
  test('unknown or foreign grant fails closed', () {
    final wire = f.DoctorWire();
    expect(
      () => DoctorGrant.fromApi(
        wire.grant('unsupported'),
        patient: wire.patient,
        doctor: wire.owner,
      ),
      throwsFormatException,
    );
    expect(
      () => DoctorGrant.fromApi(
        wire.grant(),
        patient: 'other',
        doctor: wire.owner,
      ),
      throwsFormatException,
    );
    expect(
      () => DoctorGrant.fromApi(
        wire.grant(),
        patient: wire.patient,
        doctor: 'other',
      ),
      throwsFormatException,
    );
    expect(
      DoctorGrant.fromApi(
        wire.grant(),
        patient: wire.patient,
        doctor: wire.owner,
      ).active(DateTime.utc(2090)),
      false,
    );
  });
  for (final mode in [
    'logout',
    'switch reused token',
    'current401',
    'old401',
    'consent revoked',
    'dispose',
  ]) {
    test('workspace $mode rejects late list and note data', () async {
      final wire = f.DoctorWire();
      await wire.run(() async {
        await wire.login();
        final c = DoctorWorkspaceController(session);
        await c.refresh();
        wire.pending = Completer();
        final read = c.refresh();
        await Future<void>.delayed(Duration.zero);
        if (mode == 'logout') await api.logout();
        if (mode == 'switch reused token' || mode == 'old401') {
          await api.init();
          wire.owner = 'doctor-b';
          await wire.login();
        }
        if (mode == 'consent revoked') {
          wire.accepted = false;
          await api.readSafetyAcceptance();
        }
        if (mode == 'dispose') c.dispose();
        wire.pending!.complete(
          f.json([wire.row], mode.contains('401') ? 401 : 200),
        );
        await read;
        expect(c.visible, isEmpty);
        expect(c.notes, isEmpty);
        if (mode == 'switch reused token' || mode == 'old401') {
          expect(api.doctorOwner, 'doctor-b');
        }
        if (mode == 'current401' || mode == 'logout') {
          expect(api.isAuthenticated, false);
        }
        if (mode != 'dispose') c.dispose();
      });
    });
  }
  test('doctor profile refresh deduplicates pending lists', () async {
    final wire = f.DoctorWire();
    await wire.run(() async {
      await wire.login();
      final c = DoctorWorkspaceController(session);
      wire.pending = Completer();
      final first = c.refresh();
      await Future<void>.delayed(Duration.zero);
      await Future.wait(List.generate(8, (_) => c.refresh()));
      expect(
        wire.requests
            .where((r) => r.url.path.endsWith('/doctor/patients'))
            .length,
        1,
      );
      wire.pending!.complete(f.json([]));
      await first;
      expect(c.error, isNull);
      c.dispose();
    });
  });
  for (final code in [403, 503]) {
    test(
      'failed doctor profile $code hides data and permits verified GET recovery',
      () async {
        final wire = f.DoctorWire();
        await wire.run(() async {
          await wire.login();
          final c = DoctorWorkspaceController(session);
          await c.refresh();
          wire.profileStatus = code;
          expect(await c.refresh(), false);
          expect(c.current, false);
          expect(c.visible, isEmpty);
          expect(c.notes, isEmpty);
          expect(c.error, isNotNull);
          expect(c.authenticatedCurrent, true);
          wire.profileStatus = null;
          expect(await c.refresh(), true);
          expect(c.visible.single.id, 'patient-1');
          expect(wire.writes, 0);
          c.dispose();
        });
      },
    );
  }
  for (final code in [403, 429, 503]) {
    test('workspace $code is unavailable, not empty or safe', () async {
      final wire = f.DoctorWire()..listStatus = code;
      await wire.run(() async {
        await wire.login();
        final c = DoctorWorkspaceController(session);
        expect(await c.refresh(), false);
        expect(c.error, isNotNull);
        expect(c.patients, isEmpty);
        expect(c.retrievedAt, isNull);
        c.dispose();
      });
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'doctor workspace theme=$dark is real, accessible at 320px/200%',
      (t) async {
        t.view.physicalSize = const Size(320, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final wire = f.DoctorWire();
        await wire.run(() async {
          await wire.login();
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
              home: const DoctorPortalScreen(session: session),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Connected patients'), findsOneWidget);
          await t.scrollUntilVisible(
            find.textContaining('No active experiment recorded'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          expect(
            find.textContaining('No active experiment recorded'),
            findsOneWidget,
          );
          expect(find.text('Salma Ahmed'), findsNothing);
          final semantics = t.ensureSemantics();
          expect(t, meetsGuideline(labeledTapTargetGuideline));
          semantics.dispose();
          expect(t.takeException(), isNull);
          await api.init();
          await t.pumpAndSettle();
          expect(
            find.text('You are not authorized to view this workspace.'),
            findsOneWidget,
          );
          expect(find.text('Real Patient'), findsNothing);
          await t.pumpWidget(const SizedBox());
        });
      },
    );
  }
  testWidgets(
    'provisioned doctor must accept safety on server before workspace',
    (t) async {
      final wire = f.DoctorWire()..accepted = false;
      await wire.run(() async {
        await t.pumpWidget(const MaterialApp(home: DoctorSignInScreen()));
        await t.enterText(
          find.byKey(const Key('doctorEmail')),
          'doctor@example.invalid',
        );
        await t.enterText(find.byKey(const Key('doctorPassword')), 'synthetic');
        await t.tap(find.byKey(const Key('doctorSignIn')));
        await t.pumpAndSettle();
        expect(find.byType(SafetyResponsibilityScreen), findsOneWidget);
        expect(find.byType(DoctorPortalScreen), findsNothing);
        expect(
          wire.requests.where((r) => r.url.path.contains('/doctor/')),
          isEmpty,
        );
        expect(api.canReadDoctorWorkspace, false);
        await api.init();
        await t.pumpWidget(const SizedBox());
      });
    },
  );
  testWidgets(
    'forged local doctor route cannot display supplied patient records',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: DoctorPortalScreen(
            session: session,
            patientData: [f.DoctorWire().row],
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Real Patient'), findsNothing);
      expect(
        find.text('You are not authorized to view this workspace.'),
        findsOneWidget,
      );
    },
  );
}
