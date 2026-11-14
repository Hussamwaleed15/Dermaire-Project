import 'package:dermaire_app/capture/capture_history_screen.dart';
import 'package:dermaire_app/capture/measurement_history_screen.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/plans/plan_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_comparison_test.dart' as w;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  for (final target in ['baseline', 'follow-up', 'history']) {
    testWidgets(
      'patient plan opens original $target without associating records',
      (t) async {
        final wire = w.ComparisonWire();
        wire.plan = {
          ...wire.plan,
          'followup_capture_id': 'followup-1',
          'state': 'captured',
          'revision': 3,
        };
        await wire.run(() async {
          await wire.login();
          final state = DermaireState();
          await t.pumpWidget(
            MaterialApp(
              home: ClinicalPlanScreen(id: 'plan-1', state: state),
            ),
          );
          await t.pumpAndSettle();
          final key = target == 'history'
              ? 'planMeasurementHistory'
              : 'planCaptureDetails:${target == 'baseline' ? 'baseline-1' : 'followup-1'}';
          final button = find.byKey(Key(key));
          await t.scrollUntilVisible(
            button,
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          await t.tap(button);
          await t.pumpAndSettle();
          if (target == 'history') {
            expect(find.byType(MeasurementHistoryScreen), findsOneWidget);
          } else {
            final screen = t.widget<CaptureDetailScreen>(
              find.byType(CaptureDetailScreen),
            );
            expect(
              screen.id,
              target == 'baseline' ? 'baseline-1' : 'followup-1',
            );
            expect(screen.state, same(state));
          }
          expect(wire.sends, isEmpty);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          state.dispose();
          await ApiService.instance.init();
        });
      },
    );
  }
  testWidgets(
    'doctor has no patient-only history or owner capture navigation',
    (t) async {
      final wire = w.ComparisonWire(doctor: true);
      await wire.run(() async {
        await wire.login();
        final state = DermaireState();
        await t.pumpWidget(
          MaterialApp(
            home: ClinicalPlanScreen(id: 'plan-1', state: state),
          ),
        );
        await t.pumpAndSettle();
        await t.drag(find.byType(Scrollable).first, const Offset(0, -1400));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('planMeasurementHistory')), findsNothing);
        expect(
          find.byKey(const Key('planCaptureDetails:baseline-1')),
          findsNothing,
        );
        expect(wire.sends, isEmpty);
        await t.pumpWidget(const SizedBox());
        state.dispose();
        await ApiService.instance.init();
      });
    },
  );
}
