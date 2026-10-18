import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/navigation/patient_navigation.dart';
import 'package:dermaire_app/navigation/patient_care_actions.dart';
import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_state_integration_test.dart' as f;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'center action and six accessible destinations dark=$dark large=$large',
        (t) async {
          await t.binding.setSurfaceSize(Size(large ? 320 : 390, 900));
          addTearDown(() => t.binding.setSurfaceSize(null));
          var selected = 0, observed = 0;
          final semantics = t.ensureSemantics();

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
              home: Scaffold(
                bottomNavigationBar: PatientNavigation(
                  selected: 0,
                  labels: AppShell.labels,
                  icons: AppShell.icons,
                  onSelect: (i) => selected = i,
                  onObserve: () => observed++,
                ),
              ),
            ),
          );
          final camera = find.byKey(const Key('centralObservationAction'));
          expect(t.getCenter(camera).dx, closeTo((large ? 320 : 390) / 2, 1));
          await t.tap(camera);
          expect(observed, 1);
          for (var i = 0; i < 6; i++) {
            await t.tap(find.byKey(ValueKey('patientDestination$i')));
            expect(selected, i);
            expect(find.byTooltip(AppShell.labels[i]), findsOneWidget);
          }
          expect(t.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
    testWidgets(
      'Home care navigation returns to current server projections dark=$dark',
      (t) async {
        final fixture = f.Fixture();
        final requests = <String>[];
        await http.runWithClient(
          () async {
            await fixture.ready();
            await t.pumpWidget(
              MaterialApp(
                theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                home: Scaffold(body: PatientCareActions(state: fixture.state)),
              ),
            );
            await t.tap(find.text('Connected care'));
            await t.pumpAndSettle();
            final before = fixture.home.calls;
            await t.tap(find.text('Care conversations'));
            await t.pumpAndSettle();
            expect(find.byType(CareThreadsScreen), findsOneWidget);
            expect(
              find.text('No current consented conversations returned.'),
              findsOneWidget,
            );
            Navigator.of(t.element(find.byType(CareThreadsScreen))).pop();
            await t.pumpAndSettle();
            expect(fixture.home.calls, greaterThan(before));
            expect(
              requests.where(
                (x) => x.startsWith('POST') && !x.endsWith('/auth/login'),
              ),
              isEmpty,
            );
            await t.pumpWidget(const SizedBox.shrink());
            fixture.state.dispose();
            await ApiService.instance.init();
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            requests.add('${r.method} ${r.url.path}');
            if (r.url.path.endsWith('/messaging/threads')) {
              return http.Response('{"items":[],"next_after":null}', 200);
            }
            if (r.url.path.endsWith('/doctor/access')) {
              return http.Response('[]', 200);
            }
            return fixture.transport(r);
          }),
        );
      },
    );
  }
  testWidgets('account data does not claim an export request was queued', (
    t,
  ) async {
    final s = DermaireState();
    await t.pumpWidget(MaterialApp(home: AccountDataScreen(state: s)));
    expect(
      find.textContaining('Nothing has been exported or queued'),
      findsOneWidget,
    );
    expect(find.textContaining('being generated'), findsNothing);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('accessibility shows actual device scale and reduced motion', (
    t,
  ) async {
    final s = DermaireState();
    await t.pumpWidget(
      MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: const TextScaler.linear(2),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: AccessibilityScreen(state: s),
      ),
    );
    expect(find.textContaining('200%'), findsOneWidget);
    expect(
      find.text('Reduced motion is enabled by your device.'),
      findsOneWidget,
    );
    await t.scrollUntilVisible(find.text('Use dark appearance'), 300);
    await t.tap(find.text('Use dark appearance'));
    await t.pumpAndSettle();
    expect(s.themeMode, ThemeMode.dark);
    await t.pumpWidget(const SizedBox.shrink());
    s.dispose();
  });
  testWidgets('methodology states upload and unavailable model truthfully', (
    t,
  ) async {
    await t.pumpWidget(const MaterialApp(home: HowItWorksScreen()));
    expect(find.textContaining('stored on Azure'), findsOneWidget);
    await t.scrollUntilVisible(
      find.textContaining('models may be unavailable'),
      300,
    );
    expect(find.textContaining('models may be unavailable'), findsOneWidget);
    expect(find.textContaining('extracted on your device'), findsNothing);
  });
  test('invalid tab cannot corrupt the patient IndexedStack', () {
    final s = DermaireState();
    s.selectTab(-1);
    s.selectTab(6);
    expect(s.selectedTab, 0);
    s.dispose();
  });
}
