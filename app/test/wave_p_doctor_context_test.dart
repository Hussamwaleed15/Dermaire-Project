import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/doctor/doctor_context_page.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_clinical_reviews_test.dart' as clinical;
import 'm6_doctor_fixture.dart' as f;
import 'wave_messaging_test.dart' as messaging;
import 'wave_plans_test.dart' as plans;
import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/plans/plan_ui.dart';

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  for (final kind in ['notes', 'reviews']) {
    test(
      '$kind grant loss retains minimum original identity without draft',
      () async {
        final wire = clinical.ClinicalWire();
        await wire.run(() async {
          final v = await clinical.editor(wire);
          try {
            wire.writeDelay = Completer<http.Response>();
            final write = clinical.submit(v.$3, kind);
            await Future<void>.delayed(Duration.zero);
            final original = api.integrationIntents.values.single;
            v.$1.selectPatient('not-authorized');
            expect(api.integrationIntents, isEmpty);
            expect(api.pendingDoctorReceipts, isEmpty);
            final identity = api.quarantinedOperations.single;
            expect(identity.key, original.key);
            expect(identity.scope['access_id'], 'grant-patient-1');
            final metadata = jsonEncode(identity.scope);
            expect(metadata, isNot(contains('Explicit clinician')));
            expect(metadata, isNot(contains('Clinician review remains')));
            final row = kind == 'notes'
                ? {
                    ...wire.note('Explicit clinician follow-up context.'),
                    ...wire.payloads.single,
                    'id': 'note-1',
                    'doctor_id': wire.owner,
                  }
                : wire.action(wire.payloads.single);
            wire.writeDelay!.complete(f.json(row, 201));
            expect(await write, false);
            expect(api.pendingDoctorReceipts, isEmpty);
            expect(api.integrationIntents, isEmpty);
            expect(
              api.quarantinedOperations.single.scope['resource_id'],
              row['id'],
            );
            expect(v.$3.notes, isEmpty);
            expect(wire.posts, 1);
          } finally {
            clinical.clean(v);
          }
        });
      },
    );
  }

  testWidgets(
    'context loss removes private subtree and does not reselect patient',
    (tester) async {
      final wire = clinical.ClinicalWire();
      await wire.run(() async {
        final v = await clinical.editor(wire);
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: DoctorContextPage(
                connection: v.$2,
                child: const Scaffold(
                  body: Text('Synthetic private patient content'),
                ),
              ),
            ),
          );
          expect(
            find.text('Synthetic private patient content'),
            findsOneWidget,
          );
          v.$1.selectPatient('not-authorized');
          await tester.pump();
          expect(find.text('Synthetic private patient content'), findsNothing);
          expect(
            find.textContaining('Patient context changed'),
            findsOneWidget,
          );
          expect(v.$2.confirmed, false);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          clinical.clean(v);
          await api.init();
        }
      });
    },
  );
  for (final messages in [true, false]) {
    testWidgets(
      'patient filter change rebuilds ${messages ? 'conversations' : 'plans'} without A data',
      (tester) async {
        final f.DoctorWire wire = messages
            ? messaging.MessageWire(doctor: true)
            : plans.PlanWire(doctor: true);
        await wire.run(() async {
          try {
            await wire.login();
            Widget screen(String patient) => MaterialApp(
              home: messages
                  ? CareThreadsScreen(patient: patient)
                  : ClinicalPlansScreen(patient: patient),
            );
            await tester.pumpWidget(screen('patient-1'));
            await tester.pumpAndSettle();
            final marker = messages
                ? find.text('Patient account patient-1')
                : find.text('Review current skin tolerance');
            expect(marker, findsOneWidget);
            await tester.pumpWidget(screen('patient-2'));
            await tester.pumpAndSettle();
            expect(marker, findsNothing);
            expect(
              find.textContaining(
                messages
                    ? 'No current consented conversations'
                    : 'No authorized clinical plans',
              ),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            await api.init();
          }
        });
      },
    );
  }
}
