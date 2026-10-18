import 'package:dermaire_app/notifications/notification_availability.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'availability is honest, inert and readable dark=$dark scale=$scale',
        (tester) async {
          tester.view.physicalSize = const Size(320, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var permissionCalls = 0, requests = 0;
          const channel = MethodChannel(
            'flutter.baseflow.com/permissions/methods',
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            (call) async {
              permissionCalls++;
              return 1;
            },
          );
          addTearDown(
            () => tester.binding.defaultBinaryMessenger
                .setMockMethodCallHandler(channel, null),
          );
          await http.runWithClient(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      disableAnimations: true,
                    ),
                    child: child!,
                  ),
                  home: const NotificationAvailabilityScreen(),
                ),
              );
              await tester.pumpAndSettle();
              expect(
                find.text('Device delivery is unavailable'),
                findsOneWidget,
              );
              expect(find.byType(Switch), findsNothing);
              expect(find.byType(Checkbox), findsNothing);
              expect(find.text('Templates'), findsNothing);
              expect(
                find.textContaining('Your results are ready'),
                findsNothing,
              );
              await tester.scrollUntilVisible(
                find.textContaining(
                  'Notification permission has not been checked',
                ),
                150,
              );
              expect(tester.takeException(), isNull);
              expect(permissionCalls, 0);
              expect(requests, 0);
              final semantics = tester.ensureSemantics();
              expect(tester, meetsGuideline(labeledTapTargetGuideline));
              expect(tester, meetsGuideline(textContrastGuideline));
              semantics.dispose();
              await tester.pumpWidget(const SizedBox());
            },
            () => MockClient((request) async {
              expect(request.url.host, 'flutter-tests.invalid');
              requests++;
              return http.Response('unavailable', 503);
            }),
          );
        },
      );
    }
  }
}
