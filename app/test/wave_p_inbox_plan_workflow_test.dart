import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/notifications/inbox_ui.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_comparison_test.dart' as comparison;
import 'wave_inbox_test.dart' as inbox;

void main() {
  final api = ApiService.instance;
  for (final dark in [false, true]) {
    for (final status in ['scheduled', 'cancelled', 'reviewed']) {
      testWidgets(
        'inbox → current comparison $status → capture availability → logout dark=$dark 320px200%',
        (t) async {
          t.view.physicalSize = const Size(320, 1500);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          SharedPreferences.setMockInitialValues({});
          await api.init();
          final p = comparison.ComparisonWire();
          p.plan = {...p.plan, 'state': status, 'revision': 8};
          final n = inbox.InboxWire();
          final state = DermaireState();
          await http.runWithClient(
            () async {
              try {
                await p.login();
                await t.pumpWidget(
                  MaterialApp(
                    theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                    builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(ctx).copyWith(
                        textScaler: const TextScaler.linear(2),
                        disableAnimations: true,
                      ),
                      child: child!,
                    ),
                    home: NotificationInboxScreen(state: state),
                  ),
                );
                await t.pumpAndSettle();
                final link = find.text('Open current plan');
                await t.scrollUntilVisible(
                  link,
                  250,
                  scrollable: find.byType(Scrollable).first,
                );
                await t.ensureVisible(link);
                await t.pumpAndSettle();
                await t.tap(link);
                await t.pumpAndSettle();
                final screen = t.widget<ClinicalPlanScreen>(
                  find.byType(ClinicalPlanScreen),
                );
                expect(identical(screen.state, state), true);
                await t.scrollUntilVisible(
                  find.text('Current revision: 8'),
                  250,
                  scrollable: find.byType(Scrollable).first,
                );
                expect(find.text('Current revision: 8'), findsOneWidget);
                expect(find.text('Your next step'), findsOneWidget);
                final capture = find.text('Take guided follow-up capture');
                if (status == 'scheduled') {
                  await t.scrollUntilVisible(
                    capture,
                    250,
                    scrollable: find.byType(Scrollable).first,
                  );
                  expect(capture, findsOneWidget);
                  final button = t.widget<FilledButton>(
                    find.ancestor(
                      of: capture,
                      matching: find.byType(FilledButton),
                    ),
                  );
                  expect(button.onPressed, isNotNull);
                } else {
                  expect(capture, findsNothing);
                  expect(
                    find.textContaining(
                      status == 'cancelled'
                          ? 'This plan is cancelled.'
                          : 'The clinician’s plan review is recorded.',
                    ),
                    findsOneWidget,
                  );
                }
                expect(p.sends, isEmpty);
                expect(n.sends, isEmpty);
                expect(t.takeException(), isNull);
                await api.logout();
                await t.pumpAndSettle();
                expect(find.text('Current revision: 8'), findsNothing);
                expect(capture, findsNothing);
                await t.pumpWidget(const SizedBox.shrink());
              } finally {
                state.dispose();
                await api.init();
              }
            },
            () => MockClient((r) {
              expect(r.url.host, 'flutter-tests.invalid');
              return r.url.path.contains('/notifications')
                  ? n.call(r)
                  : p.call(r);
            }),
          );
        },
      );
    }
  }
}
