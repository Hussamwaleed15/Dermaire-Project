import 'dart:async';
import 'dart:convert';

import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/main.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('welcome supports dark mode and opens create account', (
    tester,
  ) async {
    await tester.pumpWidget(const DermaireApp());
    await tester.pumpAndSettle();

    expect(find.text('Dermaire'), findsOneWidget);
    expect(find.text('Start my skin experiment'), findsOneWidget);

    await tester.tap(find.byKey(const Key('themeToggle')));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await tester.tap(find.byKey(const Key('startExperimentButton')));
    await tester.pumpAndSettle();
    expect(find.text('Create account'), findsWidgets);
    expect(find.text('Sign up with Google'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
  });

  testWidgets('account creation validates fields and gates safety acceptance', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const DermaireApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('startExperimentButton')));
        await tester.pumpAndSettle();

        await tester.drag(find.byType(ListView).last, const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('createAccountButton')));
        await tester.pump();
        expect(find.text('Enter a valid email address'), findsOneWidget);
        expect(
          find.text('Use 8+ characters with upper, lower and a number'),
          findsOneWidget,
        );

        await tester.enterText(
          find.byKey(const Key('createEmail')),
          'salma@example.com',
        );
        await tester.enterText(
          find.byKey(const Key('createPassword')),
          'HealthySkin9!',
        );
        await tester.enterText(
          find.byKey(const Key('confirmPassword')),
          'HealthySkin9!',
        );
        await tester.tap(find.byKey(const Key('createAccountButton')));
        await tester.pumpAndSettle();

        expect(find.text('Safety & responsibility'), findsOneWidget);
        final continueButton = tester.widget<FilledButton>(
          find.byKey(const Key('acceptSafetyButton')),
        );
        expect(continueButton.onPressed, isNull);

        await tester.drag(
          find.byKey(const Key('safetyScroll')),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        final enabledButton = tester.widget<FilledButton>(
          find.byKey(const Key('acceptSafetyButton')),
        );
        expect(enabledButton.onPressed, isNotNull);

        await tester.tap(find.byKey(const Key('acceptSafetyButton')));
        await tester.pumpAndSettle();
        expect(find.text('Account created'), findsOneWidget);

        await tester.tap(find.text('Start my skin experiment'));
        await tester.pumpAndSettle();
        expect(find.text('Tell us about your skin'), findsOneWidget);
        for (final concern in [
          'Acne',
          'Redness',
          'Texture',
          'Dryness',
          'Oiliness',
          'Other',
        ]) {
          expect(find.text(concern), findsOneWidget);
        }
      },
      () => MockClient((request) async {
        if (request.url.path.endsWith('/auth/register')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['email'], 'salma@example.com');
          expect(body['accept_safety'], isTrue);
          return http.Response('{"access_token":"test-token"}', 201);
        }
        return http.Response('{}', 200);
      }),
    );
  });

  testWidgets('forgot password sends a code and returns to sign in', (
    tester,
  ) async {
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const DermaireApp());
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('existingAccountButton')));
        await tester.pumpAndSettle();

        expect(find.text('Sign in'), findsWidgets);
        expect(find.text('Continue with Google'), findsOneWidget);
        await tester.tap(find.text('Forgot password?'));
        await tester.pumpAndSettle();
        expect(find.text('Forgot password'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('resetEmail')),
          'salma@example.com',
        );
        await tester.tap(find.text('Send reset code'));
        await tester.pumpAndSettle();
        expect(find.textContaining('If an account exists'), findsOneWidget);
        await tester.tap(find.text('Back to sign in'));
        await tester.pumpAndSettle();

        expect(find.byType(SignInScreen), findsOneWidget);
      },
      () => MockClient((request) async {
        expect(request.url.path, endsWith('/auth/forgot-password'));
        expect(jsonDecode(request.body)['email'], 'salma@example.com');
        return http.Response(
          '{"message":"If an account exists, a code was sent."}',
          200,
        );
      }),
    );
  });

  testWidgets('registration failure preserves safety gate and permits retry', (
    tester,
  ) async {
    final state = DermaireState();
    final pending = Completer<http.Response>();
    var requests = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: SafetyResponsibilityScreen(
              state: state,
              email: 'salma@example.com',
              password: 'HealthySkin9!',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const Key('safetyScroll')),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('acceptSafetyButton')),
        );
        button.onPressed!();
        button.onPressed!();
        await tester.pump();
        expect(requests, 1);
        expect(find.text('Please wait...'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('acceptSafetyButton')))
              .onPressed,
          isNull,
        );
        pending.complete(
          http.Response('{"message":"Email already registered"}', 409),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AccountCreatedScreen), findsNothing);
        expect(find.textContaining('Email already registered'), findsOneWidget);
        expect(state.safetyAccepted, isFalse);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('dermaire_safety_accepted'), isNull);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('acceptSafetyButton')))
              .onPressed,
          isNotNull,
        );
      },
      () => MockClient((request) {
        requests++;
        return pending.future;
      }),
    );
  });

  testWidgets('safety-only flow proceeds without registration', (tester) async {
    final state = DermaireState();
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(home: SafetyResponsibilityScreen(state: state)),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byKey(const Key('safetyScroll')),
          const Offset(0, -3000),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('acceptSafetyButton')));
        await tester.pumpAndSettle();
        expect(find.byType(AccountCreatedScreen), findsOneWidget);
        expect(state.safetyAccepted, isTrue);
      },
      () => MockClient((request) async {
        fail('The safety-only flow must not make an HTTP request');
      }),
    );
  });
}
