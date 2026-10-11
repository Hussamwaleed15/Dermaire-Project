import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/entry/entry_motion.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/main.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = ApiService.instance;
http.Response auth([String id = 'a']) => http.Response(
  jsonEncode({
    'access_token': 'synthetic-$id',
    'expires_in': 3600,
    'user_id': id,
    'role': 'patient',
  }),
  200,
);
http.Response receipt([String id = 'a']) => http.Response(
  jsonEncode({
    'id': id,
    'safety_accepted': true,
    'full_name': 'Synthetic',
    'email': '$id@example.invalid',
    'role': 'patient',
    'skin_concerns': [],
  }),
  200,
);
MockClient isolated(Future<http.Response> Function(http.Request) handler) =>
    MockClient((r) {
      expectSync(r.url.host, 'flutter-tests.invalid');
      return handler(r);
    });

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  test('approved brand tokens have readable normal-text contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return (x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05));
    }

    for (final t in [EntryTokens.light, EntryTokens.dark]) {
      for (final pair in [
        (t.ink, t.canvas),
        (t.secondary, t.canvas),
        (t.ink, t.card),
        (t.secondary, t.card),
        (t.onAction, t.action),
        (t.onAction, t.pressed),
      ]) {
        expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
      }
    }
    expect(EntryTokens.dark.canvas, const Color(0xFF17191E));
    expect(EntryTokens.dark.card, const Color(0xFF24272D));
    expect(DermaireTheme.dark.colorScheme.onPrimary, const Color(0xFF17191E));
  });

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
      for (final arabic in [false, true]) {
        for (final scale in [1.0, 2.0]) {
          testWidgets(
            '$screen dark=$dark ar=$arabic scale=$scale keyboard-safe reduced',
            (tester) async {
              tester.view.physicalSize = const Size(390, 844);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              // Bundled fonts, never downloaded. Optional render exports are review artifacts.
              if (const bool.fromEnvironment('ENTRY_PREVIEWS')) {
                await (FontLoader('MaterialIcons')..addFont(
                      rootBundle.load('fonts/MaterialIcons-Regular.otf'),
                    ))
                    .load();
                const arabicFont = String.fromEnvironment('ENTRY_ARABIC_FONT');
                if (arabicFont.isNotEmpty) {
                  final bytes = await tester.runAsync(
                    () => File(arabicFont).readAsBytes(),
                  );
                  await (FontLoader('Noto Sans Arabic')
                        ..addFont(Future.value(ByteData.sublistView(bytes!))))
                      .load();
                }
                for (final font in ['Karla', 'Fraunces']) {
                  final loader = FontLoader(font)
                    ..addFont(
                      rootBundle.load('assets/fonts/$font-Variable.ttf'),
                    );
                  await loader.load();
                }
              }
              final state = DermaireState();
              final pending = Completer<http.Response>();
              final boundary = GlobalKey();
              var calls = 0;
              await http.runWithClient(
                () async {
                  if (['loading', 'success', 'error'].contains(screen)) {
                    await api.login(
                      email: 'synthetic@example.invalid',
                      password: 'Synthetic123!',
                    );
                  }
                  final page = switch (screen) {
                    'welcome' => WelcomeScreen(state: state),
                    'signin' => SignInScreen(state: state),
                    'signup' => CreateAccountScreen(state: state),
                    'safety' => SafetyResponsibilityScreen(state: state),
                    _ => PatientEntryGate(state: state),
                  };
                  await tester.pumpWidget(
                    MaterialApp(
                      theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                      locale: Locale(arabic ? 'ar' : 'en'),
                      supportedLocales: const [Locale('en'), Locale('ar')],
                      localizationsDelegates:
                          GlobalMaterialLocalizations.delegates,
                      builder: (context, child) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          textScaler: TextScaler.linear(scale),
                          disableAnimations: true,
                        ),
                        child: child!,
                      ),
                      home: RepaintBoundary(key: boundary, child: page),
                    ),
                  );
                  if (const bool.fromEnvironment('ENTRY_PREVIEWS')) {
                    await tester.runAsync(
                      () => precacheImage(
                        const AssetImage('assets/images/dermaire-logo.webp'),
                        tester.element(find.byType(Scaffold).first),
                      ),
                    );
                  }
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  expect(find.byType(AppShell), findsNothing);
                  expect(find.byType(CircularProgressIndicator), findsNothing);
                  final rootContext = tester.element(
                    find.byType(page.runtimeType),
                  );
                  expect(
                    Directionality.of(rootContext),
                    arabic ? TextDirection.rtl : TextDirection.ltr,
                  );
                  expect(EntryMotion.reduced(rootContext), isTrue);
                  final controls = find.byWidgetPredicate(
                    (w) =>
                        w is FilledButton ||
                        w is OutlinedButton ||
                        w is TextButton ||
                        w is IconButton,
                  );
                  for (final element in controls.evaluate()) {
                    expect(
                      tester.getSize(find.byWidget(element.widget)).height,
                      greaterThanOrEqualTo(48),
                    );
                  }
                  // Every footer remains reachable, even at 200%.
                  final primary = find.byType(FilledButton);
                  if (primary.evaluate().isNotEmpty) {
                    await tester.ensureVisible(primary.last);
                    await tester.pumpAndSettle();
                    expect(primary.last.hitTestable(), findsOneWidget);
                  }
                  if (const bool.fromEnvironment('ENTRY_PREVIEWS') &&
                      ((!arabic && scale == 1) || (arabic && scale == 2))) {
                    // Show initial layout; actions at 200% can be reached by scrolling.
                    final scroll = find.byType(SingleChildScrollView);
                    if (scroll.evaluate().isNotEmpty) {
                      await tester.drag(scroll.first, const Offset(0, 5000));
                      await tester.pumpAndSettle();
                    }
                    final render =
                        boundary.currentContext!.findRenderObject()!
                            as RenderRepaintBoundary;
                    await tester.runAsync(() async {
                      final image = await render.toImage(pixelRatio: 1.5);
                      final bytes = await image.toByteData(
                        format: ui.ImageByteFormat.png,
                      );
                      final file = File(
                        'build/entry-previews/${screen}_${dark ? 'dark' : 'light'}_${arabic ? 'ar200' : 'en'}.png',
                      );
                      await file.parent.create(recursive: true);
                      await file.writeAsBytes(bytes!.buffer.asUint8List());
                      image.dispose();
                    });
                  }
                  if (screen == 'signin' || screen == 'signup') {
                    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
                    await tester.pumpAndSettle();
                    await tester.ensureVisible(primary.last);
                    await tester.pumpAndSettle();
                    expect(primary.last.hitTestable(), findsOneWidget);
                    expect(tester.takeException(), isNull);
                    tester.view.resetViewInsets();
                  }
                  if (screen == 'loading') pending.complete(receipt());
                  await tester.pumpWidget(const SizedBox());
                  await api.init();
                },
                () => isolated((r) async {
                  calls++;
                  if (r.url.path.endsWith('/auth/login')) return auth();
                  if (screen == 'loading') return pending.future;
                  if (screen == 'error') return http.Response('', 503);
                  return receipt();
                }),
              );
              if (!['loading', 'success', 'error'].contains(screen)) {
                expect(calls, 0);
              }
              state.dispose();
            },
          );
        }
      }
    }
  }

  for (final switchAccount in [false, true]) {
    testWidgets(
      'success callback cannot enter after logout/switch=$switchAccount',
      (tester) async {
        final state = DermaireState();
        await http.runWithClient(
          () async {
            await api.login(
              email: 'a@example.invalid',
              password: 'Synthetic123!',
            );
            await tester.pumpWidget(
              MaterialApp(home: PatientEntryGate(state: state)),
            );
            await tester.pumpAndSettle();
            expect(find.byType(AppShell), findsNothing);
            final button = tester.widget<FilledButton>(
              find.byKey(const Key('continueEntry')),
            );
            await api.logout();
            if (switchAccount) {
              await api.login(
                email: 'b@example.invalid',
                password: 'Synthetic123!',
              );
            }
            button.onPressed!();
            await tester.pumpAndSettle();
            expect(find.byType(AppShell), findsNothing);
            expect(api.hasConfirmedSafetyAcceptance, isFalse);
            await tester.pumpWidget(const SizedBox());
            await api.init();
          },
          () => isolated((r) async {
            if (r.url.path.endsWith('/auth/login')) {
              return auth(r.body.contains('b@example') ? 'b' : 'a');
            }
            if (r.url.path.endsWith('/auth/logout')) {
              return http.Response('', 204);
            }
            return receipt();
          }),
        );
        state.dispose();
      },
    );
  }

  testWidgets(
    'language switch activates SDK Arabic RTL without authorizing entry',
    (tester) async {
      await tester.pumpWidget(const DermaireApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('languageToggle')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('ar'),
      );
      expect(find.text('صورة أوضح لبشرتك.'), findsOneWidget);
      expect(api.hasConfirmedSafetyAcceptance, isFalse);
      await tester.pumpWidget(const SizedBox());
      await api.init();
    },
  );

  for (final google in [false, true]) {
    for (final failure in ['401', '403', '503', 'offline', 'timeout']) {
      testWidgets('safe auth error/retry google=$google failure=$failure', (
        tester,
      ) async {
        final state = DermaireState();
        var failRequest = true;
        var authCalls = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: SignInScreen(
                  state: state,
                  googleSignIn: () async => 'synthetic-google-token',
                ),
              ),
            );
            await tester.pumpAndSettle();
            Future<void> submit() async {
              if (google) {
                await tester.tap(find.text('Continue with Google'));
              } else {
                await tester.enterText(
                  find.byKey(const Key('signInEmail')),
                  'synthetic@example.invalid',
                );
                await tester.enterText(
                  find.byKey(const Key('signInPassword')),
                  'Synthetic123!',
                );
                await tester.tap(find.byKey(const Key('signInButton')));
              }
              await tester.pumpAndSettle();
            }

            await submit();
            expect(find.byType(AppShell), findsNothing);
            expect(find.text('We couldn’t complete this step'), findsOneWidget);
            expect(
              find.textContaining('sensitive synthetic response'),
              findsNothing,
            );
            expect(api.hasConfirmedSafetyAcceptance, isFalse);
            expect(authCalls, 1);
            failRequest = false;
            await tester.tap(find.byKey(const Key('signInButton')));
            await tester.pumpAndSettle();
            expect(
              authCalls,
              1,
            ); // Retry restores form; it never repeats credentials implicitly.
            if (!google) {
              expect(
                tester
                    .widget<TextFormField>(find.byKey(const Key('signInEmail')))
                    .controller!
                    .text,
                'synthetic@example.invalid',
              );
            }
            await submit();
            expect(find.byType(AppShell), findsNothing);
            expect(find.text('You’re ready to continue'), findsOneWidget);
            expect(authCalls, 2);
            expect(api.hasConfirmedSafetyAcceptance, isTrue);
            await tester.tap(find.byKey(const Key('continueEntry')));
            await tester.pumpAndSettle();
            expect(find.byType(AppShell), findsOneWidget);
            await tester.pumpWidget(const SizedBox());
            await api.init();
          },
          () => isolated((r) async {
            if (r.url.path.endsWith('/auth/login') ||
                r.url.path.endsWith('/auth/google')) {
              authCalls++;
              if (failRequest) {
                if (failure == 'offline') {
                  throw http.ClientException('sensitive synthetic response');
                }
                if (failure == 'timeout') {
                  throw TimeoutException('sensitive synthetic response');
                }
                return http.Response(
                  '{"detail":"sensitive synthetic response"}',
                  int.parse(failure),
                );
              }
              return auth();
            }
            if (r.url.path.endsWith('/users/me')) return receipt();
            return http.Response('{}', 200);
          }),
        );
        state.dispose();
      });
    }
  }

  testWidgets(
    'scoped entry routes and press motion respect both accessibility flags',
    (tester) async {
      for (final reduce in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: Builder(
                builder: (context) {
                  final route = entryRoute<void>(context, const SizedBox());
                  expect(
                    route.transitionDuration,
                    reduce ? Duration.zero : const Duration(milliseconds: 240),
                  );
                  route.dispose();
                  return EntryPress(
                    child: FilledButton(
                      onPressed: () {},
                      child: const Text('Continue'),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(FilledButton)),
        );
        await tester.pump();
        expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          reduce ? 1 : .985,
        );
        await gesture.up();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(accessibleNavigation: true),
            child: Builder(
              builder: (context) {
                expect(EntryMotion.reduced(context), isTrue);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
    },
  );
}
