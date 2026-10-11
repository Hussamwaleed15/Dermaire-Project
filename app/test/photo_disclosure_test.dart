import 'dart:typed_data';

import 'package:dermaire_app/capture/capture_controller.dart';
import 'package:dermaire_app/capture/capture_panel.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Finder get disclosure =>
    find.textContaining('Choosing a photo securely uploads');

void expectTruthfulDisclosure(WidgetTester tester) {
  expect(disclosure, findsOneWidget);
  final text = tester.widget<Text>(disclosure).data!;
  expect(
    text,
    contains('private Azure Blob Storage when storage is available'),
  );
  expect(text, contains('deleted when your account deletion completes'));
  expect(find.textContaining('stays on your device'), findsNothing);
  expect(
    find.textContaining('only skin measurements are ever sent'),
    findsNothing,
  );
  expect(
    find.textContaining('does not diagnose skin or create measurements'),
    findsNothing,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ApiService.instance.init());

  test('test origin is isolated and unmocked HTTP is denied', () async {
    expect(
      Uri.parse(ApiService.instance.baseUrl).host,
      'flutter-tests.invalid',
    );
    for (final url in [
      ApiService.instance.baseUrl,
      'https://dermaire-api.azurewebsites.net/api/v1',
    ]) {
      // The suite binding rejects before opening any socket, including when
      // a test accidentally supplies the production URL explicitly.
      final response = await http.get(Uri.parse(url));
      expect(response.statusCode, 400);
      expect(response.body, isEmpty);
    }
    await expectLater(
      ApiService.instance.forgotPassword(email: 'synthetic@example.invalid'),
      throwsA(isA<ApiException>()),
    );
  });

  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('welcome disclosure dark=$dark large/RTL=$large', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = DermaireState();
        var requests = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(large ? 2 : 1),
                    disableAnimations: true,
                  ),
                  child: Directionality(
                    textDirection: large
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: child!,
                  ),
                ),
                home: WelcomeScreen(state: state),
              ),
            );
            await tester.pumpAndSettle();
            expectTruthfulDisclosure(tester);
            await tester.ensureVisible(disclosure);
            await tester.pumpAndSettle();
            // At 200% this paragraph may exceed the viewport. Its centre need
            // not be visible; all lines remain in the same reachable scroll.
            expect(
              tester
                  .getRect(disclosure)
                  .overlaps(tester.getRect(find.byType(SingleChildScrollView))),
              isTrue,
            );
            expect(tester.takeException(), isNull);
            expect(requests, 0);
            await tester.ensureVisible(
              find.byKey(const Key('startExperimentButton')),
            );
            await tester.tap(find.byKey(const Key('startExperimentButton')));
            await tester.pumpAndSettle();
            expect(find.byType(CreateAccountScreen), findsOneWidget);
            expect(requests, 0);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((_) async {
            requests++;
            throw StateError('Disclosure must not send a request');
          }),
        );
        state.dispose();
      });
    }
  }

  for (final scenario in [
    'ready',
    'stored',
    'not_stored',
    'rejected',
    'failure',
  ]) {
    testWidgets('capture disclosure precedes photo action: $scenario', (
      tester,
    ) async {
      var uploads = 0;
      final controller = CaptureController((_, _) async {
        uploads++;
        if (scenario == 'failure') {
          throw http.ClientException('Synthetic offline');
        }
        final decision = scenario == 'rejected' ? 'rejected' : 'accepted';
        return {
          'id': 'synthetic-capture',
          'state': decision,
          'storage': scenario == 'stored' ? 'azure_blob' : 'not_persisted',
          'provenance': {'quality': 'server_computed'},
          'quality': {
            'version': 'capture-quality-1.0',
            'decision': decision,
            'reasons': <String>[],
          },
        };
      });
      if (scenario != 'ready') {
        await controller.check(Uint8List(1), 'synthetic.png');
      }
      final beforeRender = uploads;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CapturePanel(controller: controller),
            ),
          ),
        ),
      );
      expectTruthfulDisclosure(tester);
      expect(find.textContaining('are not a diagnosis'), findsOneWidget);
      expect(uploads, beforeRender);
      final photoAction = find.byType(FilledButton);
      expect(
        tester.getRect(disclosure).bottom,
        lessThanOrEqualTo(tester.getRect(photoAction).top),
      );
      expect(tester.widget<FilledButton>(photoAction).onPressed, isNotNull);
      if (scenario == 'stored') {
        expect(
          find.textContaining('Image stored on the server'),
          findsOneWidget,
        );
      } else {
        expect(find.textContaining('Image stored on the server'), findsNothing);
      }
      if (scenario == 'not_stored') {
        expect(find.textContaining('Image was not stored'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }
}
