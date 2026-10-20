import 'dart:async';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/doctor/doctor_context_page.dart';
import 'package:dermaire_app/doctor/doctor_clinical_controller.dart';
import 'package:dermaire_app/doctor/doctor_clinical_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_clinical_reviews_test.dart' as clinical;
import 'm6_doctor_fixture.dart' as fixture;
import 'wave_q_domain_readers_test.dart' as readers;

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final kind in ['notes', 'reviews']) {
    for (final delayed in [false, true]) {
      test(
        '$kind original clinical context never adopts replacement grant delayed=$delayed',
        () async {
          final w = readers.ClinicalReaderWire();
          await w.run(() async {
            final v = await clinical.editor(w);
            Future<bool>? write;
            if (delayed) {
              w.writeDelay = Completer<http.Response>();
              write = clinical.submit(v.$3, kind);
              await Future<void>.delayed(Duration.zero);
              expect(w.posts, 1);
            }
            w.selectedGrant = 'replacement-grant';
            expect(await v.$2.refresh(), true);
            expect(v.$2.grant!.id, 'replacement-grant');
            expect(v.$3.current, false);
            expect(v.$3.notes, isEmpty);
            expect(v.$3.review, isNull);
            if (delayed) {
              final row = kind == 'notes'
                  ? {
                      ...w.note('Explicit clinician follow-up context.'),
                      ...w.payloads.single,
                      'id': 'late-note',
                    }
                  : w.action(w.payloads.single);
              w.writeDelay!.complete(fixture.json(row, 201));
              expect(await write, false);
              expect(api.integrationIntents, isEmpty);
              expect(api.pendingDoctorReceipts, isEmpty);
              expect(api.quarantinedOperations, hasLength(1));
              expect(
                api.quarantinedOperations.single.scope['access_id'],
                'grant-patient-1',
              );
            }
            final before = w.posts;
            expect(await clinical.submit(v.$3, kind), false);
            expect(await v.$3.refresh(), false);
            expect(w.posts, before);
            // A deliberately opened new editor may bind the newly verified grant.
            final fresh = DoctorClinicalController(v.$2);
            expect(await fresh.refresh(), true);
            fresh.dispose();
            clinical.clean(v);
            await api.init();
          });
        },
      );
    }
  }
  for (final dark in [false, true]) {
    for (final editor in [false, true]) {
      testWidgets(
        'old page blocks replacement but same grant resumes editor=$editor dark=$dark',
        (t) async {
          t.view.physicalSize = const Size(320, 1200);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final w = readers.ClinicalReaderWire();
          await w.run(() async {
            final v = await clinical.editor(w);
            Widget page() => editor
                ? DoctorClinicalScreen(connection: v.$2)
                : DoctorContextPage(
                    connection: v.$2,
                    child: const Scaffold(
                      body: Text('Private original context'),
                    ),
                  );
            Widget app(Key key) => MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (_, child) => MediaQuery(
                data: const MediaQueryData(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: KeyedSubtree(key: key, child: page()),
            );
            await t.pumpWidget(app(const ValueKey('original')));
            await t.pumpAndSettle();
            final content = find.text(
              editor ? 'Notes & reviews' : 'Private original context',
            );
            expect(content, findsOneWidget);
            expect(await v.$2.refresh(), true);
            await t.pumpAndSettle();
            expect(content, findsOneWidget);
            w.selectedGrant = 'replacement-grant';
            expect(await v.$2.refresh(), true);
            await t.pumpAndSettle();
            expect(content, findsNothing);
            expect(
              find.textContaining(
                editor ? 'Patient access ended' : 'Patient context changed',
              ),
              findsOneWidget,
            );
            // Explicitly create a new route/widget; the old page is never rebound.
            await t.pumpWidget(app(const ValueKey('newly-opened')));
            await t.pumpAndSettle();
            expect(content, findsOneWidget);
            expect(t.takeException(), isNull);
            await t.pumpWidget(const SizedBox());
            clinical.clean(v);
            await api.init();
          });
        },
      );
    }
  }
}
