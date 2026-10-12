import 'dart:async';
import 'dart:convert';

import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/entry/entry_motion.dart';
import 'package:dermaire_app/main.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = ApiService.instance;
final arabicCharacters = RegExp(r'[\u0600-\u06FF]');
http.Response auth() => http.Response(
  jsonEncode({
    'access_token': 'synthetic-english-only',
    'expires_in': 3600,
    'user_id': 'synthetic-patient',
    'role': 'patient',
  }),
  200,
);
http.Response receipt() => http.Response(
  jsonEncode({
    'id': 'synthetic-patient',
    'safety_accepted': true,
    'role': 'patient',
    'full_name': 'Synthetic account',
    'email': 'synthetic@example.invalid',
    'skin_concerns': [],
  }),
  200,
);

void expectEnglish(WidgetTester tester) {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.locale, const Locale('en'));
  expect(app.supportedLocales, const [Locale('en')]);
  final context = tester.element(find.byType(Scaffold).first);
  expect(Localizations.localeOf(context), const Locale('en'));
  expect(Directionality.of(context), TextDirection.ltr);
  // These framework input/accessibility labels must also stay in English.
  expect(MaterialLocalizations.of(context).selectAllButtonLabel, 'Select all');
  expect(find.byKey(const Key('languageToggle')), findsNothing);
  expect(find.byIcon(Icons.translate), findsNothing);
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    expect(
      arabicCharacters.hasMatch(
        text.data ?? text.textSpan?.toPlainText() ?? '',
      ),
      isFalse,
    );
  }
  for (final field in tester.widgetList<TextFormField>(
    find.byType(TextFormField),
  )) {
    expect(field.controller, isNotNull); // Native text entry/autofill retained.
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  for (final screen in [
    'welcome',
    'signin',
    'signup',
    'safety',
    'loading',
    'success',
    'error',
  ]) {
    for (final dark in [false, true]) {
      testWidgets('Arabic device keeps $screen English with dark=$dark', (
        tester,
      ) async {
        tester.platformDispatcher.localeTestValue = const Locale('ar', 'EG');
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(tester.platformDispatcher.clearLocaleTestValue);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        SharedPreferences.setMockInitialValues({'dermaire_dark_mode': dark});
        final pending = Completer<http.Response>();
        var requests = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(const DermaireApp());
            await tester.pumpAndSettle();
            final state = tester
                .widget<WelcomeScreen>(find.byType(WelcomeScreen))
                .state;
            if (['loading', 'success', 'error'].contains(screen)) {
              await api.login(
                email: 'synthetic@example.invalid',
                password: 'Synthetic123!',
              );
            }
            final Widget page = switch (screen) {
              'welcome' => WelcomeScreen(state: state),
              'signin' => SignInScreen(state: state),
              'signup' => CreateAccountScreen(state: state),
              'safety' => SafetyResponsibilityScreen(state: state),
              _ => PatientEntryGate(state: state),
            };
            if (screen != 'welcome') {
              tester
                  .state<NavigatorState>(find.byType(Navigator))
                  .pushReplacement(
                    MaterialPageRoute<void>(builder: (_) => page),
                  );
              await tester.pumpAndSettle();
            }
            expectEnglish(tester);
            final context = tester.element(find.byType(Scaffold).first);
            expect(
              Theme.of(context).brightness,
              dark ? Brightness.dark : Brightness.light,
            );
            expect(
              EntryTokens.of(context).canvas,
              dark ? const Color(0xFF17191E) : const Color(0xFFFAF4EC),
            );
            expect(EntryMotion.reduced(context), isTrue);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            expect(find.byType(AppShell), findsNothing);
            switch (screen) {
              case 'welcome':
                expect(
                  find.text('A clearer view of your skin.'),
                  findsOneWidget,
                );
              case 'signin':
                expect(
                  find.text('Your journey continues here.'),
                  findsOneWidget,
                );
              case 'signup':
                expect(find.text('Create account'), findsOneWidget);
              case 'safety':
                expect(find.text('Safety & responsibility'), findsOneWidget);
                expect(
                  tester
                      .widget<FilledButton>(
                        find.byKey(const Key('acceptSafetyButton')),
                      )
                      .onPressed,
                  isNull,
                );
              case 'loading':
                expect(
                  find.text('Confirming your safety acceptance…'),
                  findsOneWidget,
                );
                expect(api.hasConfirmedSafetyAcceptance, isFalse);
              case 'success':
                expect(find.text('You’re ready to continue'), findsOneWidget);
                expect(api.hasConfirmedSafetyAcceptance, isTrue);
                expect(state.account.ready, isTrue);
              case 'error':
                expect(
                  find.text('We couldn’t complete this step'),
                  findsOneWidget,
                );
                expect(find.text('Try again'), findsOneWidget);
                expect(api.hasConfirmedSafetyAcceptance, isFalse);
            }
            expect(tester.takeException(), isNull);
            if (screen == 'loading') {
              pending.complete(receipt());
              await tester.pumpAndSettle();
              expectEnglish(tester);
              expect(find.text('You’re ready to continue'), findsOneWidget);
            }
            await tester.pumpWidget(const SizedBox());
            await api.init();
          },
          () => MockClient((request) async {
            expectSync(request.url.host, 'flutter-tests.invalid');
            requests++;
            if (request.url.path.endsWith('/auth/login')) return auth();
            if (screen == 'loading') return pending.future;
            if (screen == 'error') {
              return http.Response('synthetic unavailable', 503);
            }
            return receipt();
          }),
        );
        if (!['loading', 'success', 'error'].contains(screen)) {
          expect(requests, 0);
        }
      });
    }
  }

  testWidgets(
    'obsolete language-like preferences cannot restore Arabic or clear unrelated settings',
    (tester) async {
      tester.platformDispatcher.localeTestValue = const Locale('ar');
      addTearDown(tester.platformDispatcher.clearLocaleTestValue);
      // F1b-3 never persisted language. Seed plausible legacy keys to prove they
      // are ignored rather than introducing a fake migration/schema.
      SharedPreferences.setMockInitialValues({
        'dermaire_language': 'ar',
        'dermaire_locale': 'ar',
        'language': 'ar',
        'locale': 'ar',
        'dermaire_dark_mode': true,
        'unrelated_setting': 'keep',
      });
      await tester.pumpWidget(const DermaireApp());
      await tester.pumpAndSettle();
      expectEnglish(tester);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      await tester.tap(find.byKey(const Key('themeToggle')));
      await tester.pumpAndSettle();
      expectEnglish(tester);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getBool('dermaire_dark_mode'), isFalse);
      expect(preferences.getString('unrelated_setting'), 'keep');
      for (final key in [
        'dermaire_language',
        'dermaire_locale',
        'language',
        'locale',
      ]) {
        expect(preferences.getString(key), 'ar');
      }
      await tester.pumpWidget(const SizedBox());
      await api.init();
    },
  );

  testWidgets('live device locale changes preserve English framework and UI', (
    tester,
  ) async {
    tester.platformDispatcher.localeTestValue = const Locale('en', 'US');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    await tester.pumpWidget(const DermaireApp());
    await tester.pumpAndSettle();
    expectEnglish(tester);
    tester.platformDispatcher.localeTestValue = const Locale('ar', 'EG');
    await tester.pumpAndSettle();
    expectEnglish(tester);
    await tester.tap(find.byKey(const Key('existingAccountButton')));
    await tester.pumpAndSettle();
    expectEnglish(tester);
    expect(find.byKey(const Key('signInEmail')), findsOneWidget);
    expect(find.byKey(const Key('signInPassword')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await api.init();
  });
}
