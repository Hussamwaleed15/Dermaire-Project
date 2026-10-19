import 'package:dermaire_app/doctor/doctor_clinical_ui.dart';
import '../m6_clinical_reviews_test.dart' as clinical;
import 'package:dermaire_app/clinical/clinical_snapshot_ui.dart';
import 'package:dermaire_app/doctor/doctor_evidence_ui.dart';
import 'package:dermaire_app/capture/private_capture_image.dart';
import '../wave_snapshot_test.dart' as snapshot;
import '../m6_clinical_records_test.dart' as evidence;
import 'package:dermaire_app/agent/server_agent_ui.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/doctor_portal.dart';
import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/notifications/inbox_ui.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../m6_doctor_fixture.dart' as base;
import '../wave_agent_test.dart' as agent;
import '../wave_inbox_test.dart' as inbox;
import '../wave_messaging_test.dart' as messages;
import '../wave_plans_test.dart' as plans;

/// Deterministic actual-widget journey. Not backend E2E or device evidence.
Future<void> connectedCareWorkflow(
  WidgetTester t, {
  required bool doctor,
  required bool dark,
  required bool large,
}) async {
  await t.binding.setSurfaceSize(Size(large ? 320 : 390, 1200));
  addTearDown(() => t.binding.setSurfaceSize(null));
  final api = ApiService.instance, oldBase = ApiService.instance.baseUrl;
  SharedPreferences.setMockInitialValues({});
  api.baseUrl = 'https://flutter-tests.invalid/api/v1';
  await api.init();
  final identity = base.DoctorWire()
    ..owner = doctor ? 'doctor-1' : 'patient-1'
    ..role = doctor ? 'doctor' : 'patient'
    ..accepted = false;
  final m = messages.MessageWire(doctor: doctor);
  m.messages.add(m.message(1, 'Synthetic original participant message'));
  final n = inbox.InboxWire(doctor: doctor)..pageSize = 50;
  final p = plans.PlanWire(doctor: doctor);
  final a = agent.AgentWire(doctor: doctor);
  final e = evidence.EvidenceWire();
  final clinician = clinical.ClinicalWire();
  final state = DermaireState();
  final reads = <String>[];
  Future<void> tap(Finder finder) async {
    bool found() {
      try {
        return finder.evaluate().isNotEmpty;
      } on StateError {
        return false;
      }
    }

    if (!found()) {
      final scrollable = find.byType(Scrollable).hitTestable().first;
      final scroll = t.state<ScrollableState>(scrollable);
      scroll.position.jumpTo(scroll.position.minScrollExtent);
      await t.pumpAndSettle();
      for (var tries = 0; !found() && tries < 60; tries++) {
        await t.drag(scrollable, const Offset(0, -250));
        await t.pumpAndSettle();
      }
    }
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
  }

  Future<void> back(Type screen) async {
    Navigator.of(t.element(find.byType(screen))).pop();
    await t.pumpAndSettle();
  }

  Future<void> root(String patientLabel, String doctorLabel) =>
      tap(find.text(doctor ? doctorLabel : patientLabel).first);
  await http.runWithClient(
    () async {
      try {
        await identity.login();
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(large ? 2 : 1),
                disableAnimations: large,
              ),
              child: child!,
            ),
            home: PatientEntryGate(state: state),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(AppShell), findsNothing);
        expect(find.byType(DoctorPortalScreen), findsNothing);
        expect(api.hasConfirmedSafetyAcceptance, false);
        await t.drag(
          find.byKey(const Key('safetyScroll')),
          const Offset(0, -10000),
        );
        await t.pumpAndSettle();
        await tap(find.byKey(const Key('acceptSafetyButton')));
        expect(api.hasConfirmedSafetyAcceptance, true);
        if (!doctor) {
          await tap(find.byKey(const Key('continueEntry')));
          expect(find.byType(AppShell), findsOneWidget);
          state.selectTab(5);
          await t.pumpAndSettle();
        } else {
          expect(find.byType(DoctorPortalScreen), findsOneWidget);
        }
        await root('Care conversations', 'Care conversations');
        await tap(
          find.text(
            doctor ? 'Patient account patient-1' : 'Doctor account doctor-1',
          ),
        );
        expect(find.byType(CareConversationScreen), findsOneWidget);
        await tap(find.text('Acknowledge visible messages read'));
        expect(doctor ? m.doctorRead : m.patientRead, 1);
        final composer = find.byKey(const Key('careMessageBody'));
        await t.ensureVisible(composer);
        await t.enterText(
          composer,
          'Synthetic new message after safety confirmation',
        );
        await tap(find.byKey(const Key('careMessageSend')));
        expect(m.posts, 1);
        expect(m.messages.length, 2);
        expect(api.integrationIntents, isEmpty);
        await back(CareConversationScreen);
        await back(CareThreadsScreen);
        await root('Follow-ups & comparison plans', 'Clinical plans');
        await tap(find.text('Clinician follow-up'));
        expect(find.byType(ClinicalPlanScreen), findsOneWidget);
        if (!doctor) {
          await tap(find.byType(Checkbox));
          await tap(find.byKey(const Key('acceptClinicalPlan')));
          expect(p.plan['state'], 'scheduled');
          expect(api.integrationIntents, isEmpty);
        }
        await back(ClinicalPlanScreen);
        await back(ClinicalPlansScreen);
        await root('Notification inbox', 'Notification inbox');
        await tap(find.text('Mark read').first);
        expect(n.notices.first['unread'], false);
        await tap(find.text('Open care conversations'));
        expect(find.byType(CareThreadsScreen), findsOneWidget);
        await back(CareThreadsScreen);
        await back(NotificationInboxScreen);
        if (doctor) {
          await root('Patient Agent requests', 'Patient Agent requests');
          expect(find.byType(ClinicianRequestsScreen), findsOneWidget);
          await back(ClinicianRequestsScreen);
        } else {
          await root('Agent sessions & requests', 'Patient Agent requests');
          await tap(find.byKey(const Key('agentReadConsent')));
          await tap(find.text('Create consented session'));
          expect(a.writesAgent, 1);
          expect(a.model['invoked'], false);
          await back(ServerAgentScreen);
        }
        if (doctor) {
          await tap(find.text('Real Patient'));
          await tap(find.text('Read combined clinical snapshot'));
          expect(find.byType(ClinicalSnapshotScreen), findsOneWidget);
          expect(reads.any((p) => p.contains('/clinical-snapshot')), true);
          await back(ClinicalSnapshotScreen);
          await tap(find.text('Notes and clinical reviews'));
          expect(find.byType(DoctorClinicalScreen), findsOneWidget);
          final note = find.byKey(const Key('clinicalNote'));
          await t.scrollUntilVisible(
            note,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await t.ensureVisible(note);
          await t.enterText(
            note,
            'Synthetic connected clinician context for this patient.',
          );
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const Key('addClinicalNote')),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tap(find.byKey(const Key('addClinicalNote')));
          expect(clinician.posts, 1);
          expect(clinician.saved.single['patient_id'], 'patient-1');
          expect(api.integrationIntents, isEmpty);
          await tap(find.text('Open this patient’s care conversations'));
          expect(find.byType(CareThreadsScreen), findsOneWidget);
          expect(
            t.widget<CareThreadsScreen>(find.byType(CareThreadsScreen)).patient,
            'patient-1',
          );
          await tap(find.text('Patient account patient-1'));
          expect(find.byType(CareConversationScreen), findsOneWidget);
          await t.scrollUntilVisible(
            find.text('Synthetic original participant message'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.text('Synthetic original participant message'),
            findsOneWidget,
          );
          await back(CareConversationScreen);
          await back(CareThreadsScreen);
          await back(DoctorClinicalScreen);
          await tap(find.text('Patient clinical plans'));
          expect(
            t
                .widget<ClinicalPlansScreen>(find.byType(ClinicalPlansScreen))
                .patient,
            'patient-1',
          );
          await tap(find.text('Clinician follow-up'));
          expect(find.byType(ClinicalPlanScreen), findsOneWidget);
          await back(ClinicalPlanScreen);
          await back(ClinicalPlansScreen);
          await tap(find.text('Review clinical evidence'));
          expect(find.byType(DoctorEvidenceScreen), findsOneWidget);
          final dynamic portal = t.state(
            find.byType(DoctorPortalScreen, skipOffstage: false),
          );
          identity.listStatus = 403;
          await portal.controller.refresh();
          await t.pumpAndSettle();
          expect(portal.controller.patients, isEmpty);
          expect(find.byType(PrivateCaptureImage), findsNothing);
          await back(DoctorEvidenceScreen);
          await back(PatientDetailScreen);
        }
        expect(reads.any((p) => p.contains('/messaging/')), true);
        expect(reads.any((p) => p.contains('/clinical-plans')), true);
        expect(reads.any((p) => p.contains('/notifications')), true);
        expect(reads.any((p) => p.contains('/agent/')), true);
        await api.logout();
        await t.pumpAndSettle();
        expect(api.integrationIntents, isEmpty);
        expect(api.integrationReferences, isEmpty);
        expect(
          find.text('Synthetic original participant message'),
          findsNothing,
        );
        identity.owner = doctor ? 'doctor-2' : 'patient-2';
        identity.accepted = false;
        await identity.login();
        await t.pumpWidget(
          MaterialApp(
            home: PatientEntryGate(key: ValueKey(identity.owner), state: state),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(AppShell), findsNothing);
        expect(find.byType(DoctorPortalScreen), findsNothing);
        expect(api.hasConfirmedSafetyAcceptance, false);
        expect(
          find.text('Synthetic new message after safety confirmation'),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        state.dispose();
        await api.init();
        api.baseUrl = oldBase;
      }
    },
    () => MockClient((request) async {
      if (request.url.host != 'flutter-tests.invalid') {
        throw StateError('Test HTTP host denied');
      }
      final path = request.url.path;
      reads.add(path);
      if (doctor && (path.endsWith('/notes') || path.endsWith('/reviews'))) {
        return clinician.call(request);
      }
      if (path.contains('/messaging/') || path.endsWith('/doctor/access')) {
        return m.call(request);
      }
      if (path.contains('/notifications')) return n.call(request);
      if (path.contains('/clinical-plans')) return p.call(request);
      if (path.contains('/clinical-snapshot')) {
        return base.json(snapshot.packet(doctor: doctor));
      }
      if (path.endsWith('/timeline') || path.contains('/captures/')) {
        return e.call(request);
      }
      if (path.contains('/agent/')) return a.call(request);
      return identity.call(request);
    }),
  );
}
