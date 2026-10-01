import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/doctor_portal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.logout();
  });
  final valid = {
    'access_token': 'doctor-token',
    'user_id': 'doctor-1',
    'role': 'doctor',
    'expires_in': 3600,
  };
  final cases = <String, Map<String, dynamic>>{
    'doctor': valid,
    'patient': {...valid, 'role': 'patient'},
    'admin': {...valid, 'role': 'admin'},
    'support': {...valid, 'role': 'support'},
    'missing user': {...valid, 'user_id': null},
    'missing role': {...valid, 'role': null},
    'expired': {...valid, 'expires_in': 0},
    'no token': {...valid, 'access_token': null},
    'unauthorized': {},
    'network': {},
    'patients failure': valid,
    'malformed patients': valid,
  };
  for (final entry in cases.entries) {
    testWidgets('Doctor sign-in ${entry.key}', (tester) async {
      var loginCalls = 0;
      String? submittedPassword;
      String? patientPath;
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(home: DoctorSignInScreen()),
          );
          await tester.enterText(
            find.byKey(const Key('doctorEmail')),
            'verified@example.com',
          );
          await tester.enterText(
            find.byKey(const Key('doctorPassword')),
            '  Actual Password  ',
          );
          final button = tester.widget<FilledButton>(
            find.byKey(const Key('doctorSignIn')),
          );
          button.onPressed!();
          button.onPressed!();
          await tester.pump();
          expect(loginCalls, 1);
          expect(submittedPassword, '  Actual Password  ');
          expect(
            tester
                .widget<FilledButton>(find.byKey(const Key('doctorSignIn')))
                .onPressed,
            isNull,
          );
          if (entry.key == 'network') {
            pending.completeError(http.ClientException('Offline'));
          } else {
            pending.complete(
              http.Response(
                jsonEncode(entry.value),
                entry.key == 'unauthorized' ? 401 : 200,
              ),
            );
          }
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpAndSettle();
          final succeeds = entry.key == 'doctor';
          expect(
            find.byType(DoctorPortalScreen),
            succeeds ? findsOneWidget : findsNothing,
          );
          expect(ApiService.instance.isAuthenticated, succeeds);
          expect(
            patientPath,
            [
                  'doctor',
                  'patients failure',
                  'malformed patients',
                ].contains(entry.key)
                ? endsWith('/doctor/patients')
                : isNull,
          );
          expect(find.text('Salma Ahmed'), findsNothing);
          if (succeeds) {
            final portal = tester.widget<DoctorPortalScreen>(
              find.byType(DoctorPortalScreen),
            );
            expect(portal.session.userId, 'doctor-1');
            expect(portal.session.role, UserRole.doctor);
            expect(portal.session.authorizedPatientIds, isEmpty);
            expect(portal.session.expiresAt, isNotNull);
          }
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('/auth/login')) {
            loginCalls++;
            submittedPassword = jsonDecode(request.body)['password'] as String;
            return pending.future;
          }
          patientPath = request.url.path;
          if (entry.key == 'patients failure') return http.Response('{}', 403);
          if (entry.key == 'malformed patients') {
            return http.Response('[{}]', 200);
          }
          return http.Response('[]', 200);
        }),
      );
    });
  }

  test('Workspace uses real server patient IDs and notes', () {
    const session = AccessSession(
      userId: 'doctor-1',
      role: UserRole.doctor,
      authorizedPatientIds: {'real-patient'},
    );
    final controller = DoctorWorkspaceController(
      session,
      patientData: [
        {
          'patient_id': 'real-patient',
          'full_name': 'Real Patient',
          'last_check_in': '2026-10-01',
          'active_experiment': 'Baseline',
          'priority': 'routine',
          'active_products_count': 0,
          'notes': [
            {'content': 'Confirmed existing note.'},
          ],
        },
      ],
    );
    expect(controller.visible.single.id, 'real-patient');
    expect(controller.notes['real-patient'], ['Confirmed existing note.']);
    expect(controller.audit, isEmpty);
    controller.dispose();
  });

  for (final kind in ['success', 'failure', 'network', 'malformed']) {
    test('Clinical note $kind requires server confirmation', () async {
      const session = AccessSession(
        userId: 'doctor-1',
        role: UserRole.doctor,
        authorizedPatientIds: {'patient-1'},
      );
      final controller = DoctorWorkspaceController(session);
      const patient = DoctorPatient(
        id: 'patient-1',
        name: 'Patient',
        lastCheckIn: 'Today',
        experiment: 'Baseline',
        priority: PatientPriority.routine,
        activeProducts: 0,
      );
      final saved = await http.runWithClient(
        () => controller.addNote(patient, 'A real clinical note.'),
        () => MockClient((_) async {
          if (kind == 'network') throw http.ClientException('Offline');
          return http.Response(
            jsonEncode({
              'id': 'note-1',
              'patient_id': 'patient-1',
              'content': 'A real clinical note.',
              'created_at': kind == 'malformed'
                  ? 'invalid'
                  : '2026-10-01T10:00:00Z',
            }),
            kind == 'failure' ? 403 : 201,
          );
        }),
      );
      expect(saved, kind == 'success');
      expect(controller.notes.isNotEmpty, kind == 'success');
      expect(controller.audit.isNotEmpty, kind == 'success');
      expect(controller.loading, isFalse);
      controller.dispose();
    });
  }
}
