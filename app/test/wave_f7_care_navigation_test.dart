import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as fixture;
import 'wave_messaging_test.dart' as messages;
import 'wave_q_navigation_privacy_test.dart' as navigation;

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() => api.init());
  for (final dark in [false, true]) {
    for (final doctor in [false, true]) {
      for (final messaging in [false, true]) {
        testWidgets(
          'care detail return re-reads current state doctor=$doctor messaging=$messaging dark=$dark',
          (t) async {
            t.view.physicalSize = const Size(320, 1500);
            t.view.devicePixelRatio = 1;
            addTearDown(t.view.resetPhysicalSize);
            addTearDown(t.view.resetDevicePixelRatio);
            final fixture.DoctorWire wire = messaging
                ? messages.MessageWire(doctor: doctor)
                : (navigation.ScheduleWire()
                    ..owner = doctor ? 'doctor-1' : 'patient-1'
                    ..role = doctor ? 'doctor' : 'patient');
            await wire.run(() async {
              await wire.login();
              await t.pumpWidget(
                navigation.themed(
                  messaging
                      ? const CareThreadsScreen()
                      : const ClinicalPlansScreen(),
                  dark,
                ),
              );
              await t.pumpAndSettle();
              final target = find.text(
                messaging
                    ? doctor
                          ? 'Patient account patient-1'
                          : 'Doctor account doctor-1'
                    : 'Clinician follow-up',
              );
              await t.ensureVisible(target);
              await t.pumpAndSettle();
              await t.tap(target);
              await t.pumpAndSettle();
              final detail = messaging
                  ? CareConversationScreen
                  : ClinicalPlanScreen;
              expect(find.byType(detail, skipOffstage: false), findsOneWidget);
              if (messaging) {
                final w = wire as messages.MessageWire;
                final field = find.byKey(const Key('careMessageBody'));
                await t.scrollUntilVisible(
                  field,
                  250,
                  scrollable: find.byType(Scrollable).first,
                );
                await t.ensureVisible(field);
                await t.enterText(
                  field,
                  'Synthetic current participant message.',
                );
                FocusManager.instance.primaryFocus?.unfocus();
                await t.pumpAndSettle();
                await navigation.tap(
                  t,
                  find.byKey(const Key('careMessageSend')),
                );
                expect(w.posts, 1);
                expect(w.messages, hasLength(1));
              } else if (doctor) {
                final field = find.byKey(const Key('planLocalDue'));
                await t.scrollUntilVisible(
                  field,
                  250,
                  scrollable: find.byType(Scrollable).first,
                );
                await t.ensureVisible(field);
                await t.enterText(field, '2027-01-12 11:00');
                FocusManager.instance.primaryFocus?.unfocus();
                await t.pumpAndSettle();
                await navigation.tap(
                  t,
                  find.byKey(const Key('submitPlanSchedule')),
                );
                expect((wire as navigation.ScheduleWire).sends, hasLength(1));
              } else {
                await navigation.tap(t, find.byType(Checkbox));
                await navigation.tap(
                  t,
                  find.byKey(const Key('acceptClinicalPlan')),
                );
                expect(
                  (wire as navigation.ScheduleWire).plan['state'],
                  'scheduled',
                );
              }
              expect(api.integrationIntents, isEmpty);
              Navigator.of(t.element(find.byType(detail))).pop();
              await t.pumpAndSettle();
              expect(find.byType(detail), findsNothing);
              expect(
                messaging
                    ? find.text('Latest recorded sequence: 1')
                    : find.text(
                        doctor
                            ? 'Status: proposed · revision 2'
                            : 'Status: scheduled · revision 2',
                      ),
                findsOneWidget,
              );
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox());
              await api.init();
            });
          },
        );
      }
    }
  }
}
