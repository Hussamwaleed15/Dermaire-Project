import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'routine_authority_test.dart' as r;

void main() {
  for (final schedule in ['AM', 'PM', 'BOTH']) {
    for (final dark in [false, true]) {
      testWidgets('slot $schedule is not a scheduled reminder dark=$dark', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var platformCalls = 0;
        const permission = MethodChannel(
          'flutter.baseflow.com/permissions/methods',
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          permission,
          (_) async {
            platformCalls++;
            return 0;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            permission,
            null,
          ),
        );
        final repo = r.Repository()
          ..entries = [
            {...r.entry(), 'schedule': schedule},
          ];
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: RoutineScreen(repository: repo),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('they do not set a clock time'),
          findsOneWidget,
        );
        expect(
          find.textContaining('No reminders are scheduled'),
          findsOneWidget,
        );
        expect(find.byType(TimePickerDialog), findsNothing);
        expect(find.text('Enable reminders'), findsNothing);
        expect(repo.history, isEmpty);
        expect(platformCalls, 0);
        await tester.scrollUntilVisible(find.text('Morning'), 150);
        await tester.scrollUntilVisible(find.text('Evening'), 150);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
