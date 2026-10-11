import 'dart:async';
import 'dart:convert';

import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/entry/safety_consent_controller.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/main.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = ApiService.instance;
http.Response auth({String owner = 'patient-1', int ttl = 3600}) =>
    http.Response(
      jsonEncode({
        'access_token': 'synthetic-$owner',
        'expires_in': ttl,
        'user_id': owner,
        'role': 'patient',
      }),
      200,
    );
http.Response receipt(bool accepted, {String owner = 'patient-1'}) =>
    http.Response(
      jsonEncode({
        'id': owner,
        'safety_accepted': accepted,
        'safety_accepted_at': null,
        'full_name': 'Synthetic account',
        'email': '$owner@example.invalid',
        'role': 'patient',
        'skin_concerns': [],
        'profile_context': null,
      }),
      200,
    );
Future<Object?> authenticate(String flow) => switch (flow) {
  'google' => api.loginWithGoogle(idToken: 'synthetic-google-token'),
  'register' => api.register(
    email: 'synthetic@example.invalid',
    password: 'Synthetic123!',
    fullName: 'Synthetic',
  ),
  _ => api.login(email: 'synthetic@example.invalid', password: 'Synthetic123!'),
};
bool isAuth(http.Request request) => [
  '/auth/login',
  '/auth/google',
  '/auth/register',
].any(request.url.path.endsWith);
MockClient isolated(Future<http.Response> Function(http.Request) handler) =>
    MockClient((request) {
      expectSync(request.url.host, 'flutter-tests.invalid');
      return handler(request);
    });

Future<void> acceptInWidget(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('safetyScroll')),
    const Offset(0, -3000),
  );
  await tester.pumpAndSettle();
  final button = tester.widget<FilledButton>(
    find.byKey(const Key('acceptSafetyButton')),
  );
  button.onPressed!();
  button.onPressed!(); // A queued duplicate tap must not duplicate writes.
  await tester.pump();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'dermaire_safety_accepted': true});
    await api.init();
  });
  tearDown(() => api.init());

  test(
    'local preferences and token responses never establish acceptance',
    () async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await authenticate('password');
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('dermaire_safety_accepted', true);
          expectSync(state.safetyAccepted, isFalse);
          expectSync(await api.readSafetyAcceptance(), isFalse);
          expectSync(state.safetyAccepted, isFalse);
        },
        () => isolated(
          (request) async => isAuth(request) ? auth() : receipt(false),
        ),
      );
      state.dispose();
    },
  );

  test(
    'old accepted account with null timestamp enters from GET only',
    () async {
      var posts = 0;
      await http.runWithClient(
        () async {
          await authenticate('password');
          final consent = SafetyConsentController(api);
          expectSync(consent.confirmed, isFalse);
          await consent.refresh();
          expectSync(consent.confirmed, isTrue);
          expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
          expectSync(posts, 0);
          consent.dispose();
        },
        () => isolated((request) async {
          if (isAuth(request)) return auth();
          if (request.method == 'POST') posts++;
          return receipt(true);
        }),
      );
    },
  );

  for (final flow in ['password', 'google', 'register']) {
    for (final changeAccount in [false, true]) {
      test(
        'late $flow response cannot revive logout/switch=$changeAccount',
        () async {
          final pending = Completer<http.Response>();
          await http.runWithClient(
            () async {
              final first = authenticate(flow);
              final denied = expectLater(first, throwsA(isA<ApiException>()));
              // Allow request dispatch (the legacy-storage cleanup is asynchronous).
              await Future<void>.delayed(Duration.zero);
              if (changeAccount) {
                await api.login(
                  email: 'new@example.invalid',
                  password: 'Synthetic123!',
                );
              } else {
                await api.logout();
              }
              pending.complete(auth());
              await denied;
              expectSync(api.isAuthenticated, changeAccount);
              expectSync(
                api.authToken,
                changeAccount ? 'synthetic-patient-2' : isNull,
              );
              expectSync(api.hasConfirmedSafetyAcceptance, isFalse);
            },
            () => isolated((request) async {
              if (request.body.contains('new@example.invalid')) {
                return auth(owner: 'patient-2');
              }
              if (isAuth(request)) return pending.future;
              return http.Response('', 204);
            }),
          );
        },
      );
    }
  }

  for (final invalid in [
    '{}',
    '{',
    '[]',
    '{"id":"patient-1","safety_accepted":"true"}',
    '{"id":"other-user","safety_accepted":true}',
    '{"id":"patient-1","safety_accepted":null}',
  ]) {
    test('invalid owner/receipt cannot confirm: $invalid', () async {
      await http.runWithClient(
        () async {
          await authenticate('google');
          final consent = SafetyConsentController(api);
          await consent.refresh();
          expectSync(consent.phase, ConsentPhase.unavailable);
          expectSync(consent.confirmed, isFalse);
          expectSync(api.hasConfirmedSafetyAcceptance, isFalse);
          expectSync(consent.error, isNot(contains(invalid)));
          consent.dispose();
        },
        () => isolated(
          (request) async =>
              isAuth(request) ? auth() : http.Response(invalid, 200),
        ),
      );
    });
  }

  for (final operation in ['read', 'write', 'readback']) {
    for (final failure in ['401', '403', '503', 'offline', 'timeout']) {
      test(
        '$operation $failure cannot confirm; retry remains honest',
        () async {
          var fail = true;
          var wrote = false;
          await http.runWithClient(
            () async {
              await authenticate('password');
              final consent = SafetyConsentController(api);
              await consent.refresh();
              if (operation != 'read') await consent.accept();
              expectSync(consent.confirmed, isFalse);
              expectSync(api.hasConfirmedSafetyAcceptance, isFalse);
              expectSync(consent.error, isNotNull);
              if (failure == '401') {
                expectSync(consent.phase, ConsentPhase.ended);
                expectSync(api.isAuthenticated, isFalse);
              } else {
                expectSync(api.isAuthenticated, isTrue);
                fail = false;
                if (operation == 'read') {
                  await consent.refresh();
                } else {
                  await consent.accept();
                }
                expectSync(consent.confirmed, isTrue);
              }
              consent.dispose();
            },
            () => isolated((request) async {
              if (isAuth(request)) return auth();
              final write = request.url.path.endsWith('/auth/accept-safety');
              final shouldFail =
                  fail &&
                  (operation == 'read' ||
                      (operation == 'write' && write) ||
                      (operation == 'readback' && wrote && !write));
              if (shouldFail) {
                if (failure == 'offline') {
                  throw http.ClientException('synthetic offline');
                }
                if (failure == 'timeout') {
                  throw TimeoutException('synthetic timeout');
                }
                return http.Response('synthetic error', int.parse(failure));
              }
              if (write) {
                expectSync(jsonDecode(request.body), {'accepted': true});
                expectSync(
                  request.headers['Authorization'],
                  'Bearer synthetic-patient-1',
                );
                wrote = true;
                return receipt(true);
              }
              return receipt(!fail || wrote);
            }),
          );
        },
      );
    }
  }

  test('POST success and false GET never become accepted', () async {
    await http.runWithClient(
      () async {
        await authenticate('google');
        final consent = SafetyConsentController(api);
        await consent.refresh();
        await consent.accept();
        expectSync(consent.phase, ConsentPhase.required);
        expectSync(consent.error, contains('not confirmed'));
        expectSync(consent.confirmed, isFalse);
        consent.dispose();
      },
      () => isolated(
        (request) async =>
            isAuth(request) ? auth() : receipt(request.method == 'POST'),
      ),
    );
  });

  test(
    'failed readback retry reconciles without repeating acknowledged POST',
    () async {
      var posts = 0;
      var reads = 0;
      await http.runWithClient(
        () async {
          await authenticate('password');
          final consent = SafetyConsentController(api);
          await consent.refresh();
          await consent.accept();
          expectSync(consent.confirmed, isFalse);
          await consent.accept();
          expectSync(consent.confirmed, isTrue);
          expectSync(posts, 1);
          consent.dispose();
        },
        () => isolated((request) async {
          if (isAuth(request)) return auth();
          if (request.method == 'POST') {
            posts++;
            return receipt(true);
          }
          reads++;
          return reads == 2 ? http.Response('', 503) : receipt(reads > 2);
        }),
      );
    },
  );

  for (final operation in ['read', 'write', 'readback']) {
    for (final switchAccount in [false, true]) {
      test(
        'late $operation cannot authorize after logout/switch=$switchAccount',
        () async {
          final pending = Completer<http.Response>();
          var holding = true;
          var wrote = false;
          await http.runWithClient(
            () async {
              await authenticate('password');
              final consent = SafetyConsentController(api);
              Future<void> action;
              if (operation == 'read') {
                action = consent.refresh();
              } else {
                await consent.refresh();
                action = consent.accept();
              }
              await Future<void>.delayed(Duration.zero);
              holding = false;
              if (switchAccount) {
                await api.login(
                  email: 'new@example.invalid',
                  password: 'Synthetic123!',
                );
              } else {
                await api.logout();
              }
              pending.complete(receipt(true));
              await action;
              expectSync(consent.confirmed, isFalse);
              expectSync(consent.phase, ConsentPhase.ended);
              expectSync(api.hasConfirmedSafetyAcceptance, isFalse);
              expectSync(
                api.authToken,
                switchAccount ? 'synthetic-patient-2' : isNull,
              );
              consent.dispose();
            },
            () => isolated((request) async {
              if (isAuth(request)) {
                return auth(
                  owner: request.body.contains('new@example.invalid')
                      ? 'patient-2'
                      : 'patient-1',
                );
              }
              if (request.url.path.endsWith('/auth/logout')) {
                return http.Response('', 204);
              }
              final write = request.method == 'POST';
              if (holding &&
                  (operation == 'read' ||
                      (operation == 'write' && write) ||
                      (operation == 'readback' && wrote && !write))) {
                return pending.future;
              }
              if (write) wrote = true;
              return receipt(wrote);
            }),
          );
        },
      );
    }
  }

  for (final flow in ['password', 'google', 'google_signup']) {
    for (final alreadyAccepted in [false, true]) {
      testWidgets(
        '$flow entry requires GET, locally accepted=$alreadyAccepted',
        (tester) async {
          final state = DermaireState();
          final firstRead = Completer<http.Response>();
          final finalRead = Completer<http.Response>();
          var reads = 0;
          var posts = 0;
          await http.runWithClient(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  home: flow == 'google_signup'
                      ? CreateAccountScreen(
                          state: state,
                          googleSignIn: () async => 'synthetic-google-token',
                        )
                      : SignInScreen(
                          state: state,
                          googleSignIn: () async => 'synthetic-google-token',
                        ),
                ),
              );
              if (flow == 'password') {
                await tester.enterText(
                  find.byKey(const Key('signInEmail')),
                  'synthetic@example.invalid',
                );
                await tester.enterText(
                  find.byKey(const Key('signInPassword')),
                  'Synthetic123!',
                );
                await tester.tap(find.byKey(const Key('signInButton')));
              } else {
                await tester.tap(
                  find.text(
                    flow == 'google'
                        ? 'Continue with Google'
                        : 'Sign up with Google',
                  ),
                );
              }
              await tester.pump();
              await tester.pump(const Duration(seconds: 1));
              expectSync(find.byType(AppShell), findsNothing);
              expectSync(find.byType(AccountCreatedScreen), findsNothing);
              expectSync(
                find.textContaining('Confirming your safety acceptance'),
                findsOneWidget,
              );
              expectSync(state.safetyAccepted, isFalse);
              firstRead.complete(receipt(alreadyAccepted));
              await tester.pumpAndSettle();
              if (!alreadyAccepted) {
                expectSync(
                  find.byType(SafetyResponsibilityScreen),
                  findsOneWidget,
                );
                expectSync(
                  tester
                      .widget<FilledButton>(
                        find.byKey(const Key('acceptSafetyButton')),
                      )
                      .onPressed,
                  isNull,
                );
                await acceptInWidget(tester);
                expectSync(
                  find.byKey(const Key('acceptSafetyButton')),
                  findsNothing,
                );
                expectSync(find.byType(AppShell), findsNothing);
                expectSync(state.safetyAccepted, isFalse);
                finalRead.complete(receipt(true));
                await tester.pumpAndSettle();
                expectSync(posts, 1);
              } else {
                expectSync(posts, 0);
              }
              expectSync(state.safetyAccepted, isTrue);
              if (flow != 'google_signup') {
                expectSync(find.byType(AppShell), findsNothing);
                await tester.tap(find.byKey(const Key('continueEntry')));
                await tester.pumpAndSettle();
              }
              expectSync(
                find.byType(
                  flow == 'google_signup' ? AccountCreatedScreen : AppShell,
                ),
                findsOneWidget,
              );
              await api.init();
              await tester.pumpAndSettle();
              expectSync(find.byType(AppShell), findsNothing);
              await tester.pumpWidget(const SizedBox());
            },
            () => isolated((request) async {
              if (isAuth(request)) {
                await (await SharedPreferences.getInstance()).setBool(
                  'dermaire_safety_accepted',
                  true,
                );
                return auth();
              }
              if (request.url.path.endsWith('/auth/accept-safety')) {
                posts++;
                expectSync(jsonDecode(request.body), {'accepted': true});
                return receipt(true);
              }
              if (request.url.path.endsWith('/users/me')) {
                return ++reads == 1 ? firstRead.future : finalRead.future;
              }
              return http.Response('{}', 200);
            }),
          );
          state.dispose();
        },
      );
    }
  }

  for (final operation in ['read', 'write']) {
    testWidgets(
      'actual 20s $operation timeout permits reconciliation and ignores late result',
      (tester) async {
        final state = DermaireState();
        final pending = Completer<http.Response>();
        var timedOut = false;
        var posts = 0;
        await http.runWithClient(
          () async {
            await authenticate('google');
            await tester.pumpWidget(
              MaterialApp(home: PatientEntryGate(state: state)),
            );
            await tester.pump();
            if (operation == 'write') await acceptInWidget(tester);
            await tester.pump(const Duration(seconds: 21));
            timedOut = true;
            await tester.pumpAndSettle();
            expectSync(find.byType(AppShell), findsNothing);
            expectSync(state.safetyAccepted, isFalse);
            expectSync(
              find.textContaining('confirmed in time'),
              findsOneWidget,
            );
            if (operation == 'read') {
              await tester.tap(find.byKey(const Key('retrySafetyRead')));
            } else {
              await tester.tap(find.byKey(const Key('acceptSafetyButton')));
            }
            await tester.pumpAndSettle();
            expectSync(find.byType(AppShell), findsNothing);
            await tester.tap(find.byKey(const Key('continueEntry')));
            await tester.pumpAndSettle();
            expectSync(find.byType(AppShell), findsOneWidget);
            expectSync(state.safetyAccepted, isTrue);
            expectSync(posts, operation == 'write' ? 1 : 0);
            pending.complete(receipt(false));
            await tester.pumpAndSettle();
            expectSync(state.safetyAccepted, isTrue);
            await api.init();
            await tester.pumpWidget(const SizedBox());
          },
          () => isolated((request) async {
            if (isAuth(request)) return auth();
            if (request.url.path.endsWith('/auth/accept-safety')) {
              posts++;
              return pending.future;
            }
            if (request.url.path.endsWith('/users/me')) {
              if (timedOut) return receipt(true);
              return operation == 'read' ? pending.future : receipt(false);
            }
            return http.Response('{}', 200);
          }),
        );
        state.dispose();
      },
    );
  }

  testWidgets('logout during Google picker never calls auth endpoint', (
    tester,
  ) async {
    final state = DermaireState();
    final picker = Completer<String?>();
    var calls = 0;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: SignInScreen(state: state, googleSignIn: () => picker.future),
          ),
        );
        await tester.tap(find.text('Continue with Google'));
        await tester.pump();
        await api.logout();
        picker.complete('synthetic-google-token');
        await tester.pumpAndSettle();
        expectSync(api.isAuthenticated, isFalse);
        expectSync(find.byType(AppShell), findsNothing);
        expectSync(calls, 0);
        await tester.pumpWidget(const SizedBox());
      },
      () => isolated((request) async {
        calls++;
        return auth();
      }),
    );
    state.dispose();
  });

  testWidgets(
    'registration readback failure retries GET without registering again',
    (tester) async {
      final state = DermaireState();
      var registrations = 0;
      var reads = 0;
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: SafetyResponsibilityScreen(
                state: state,
                email: 'synthetic@example.invalid',
                password: 'Synthetic123!',
              ),
            ),
          );
          await acceptInWidget(tester);
          await tester.pumpAndSettle();
          expectSync(find.byType(AccountCreatedScreen), findsNothing);
          expectSync(state.safetyAccepted, isFalse);
          await tester.tap(find.byKey(const Key('retrySafetyRead')));
          await tester.pumpAndSettle();
          expectSync(find.byType(AccountCreatedScreen), findsOneWidget);
          expectSync(registrations, 1);
          expectSync(reads, 2);
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((request) async {
          if (isAuth(request)) {
            registrations++;
            expectSync(jsonDecode(request.body)['accept_safety'], isTrue);
            return auth();
          }
          return ++reads == 1 ? http.Response('', 503) : receipt(true);
        }),
      );
      state.dispose();
    },
  );
  test(
    'same token reused by a new session cannot accept an old read',
    () async {
      final pending = Completer<http.Response>();
      var reads = 0;
      await http.runWithClient(
        () async {
          await authenticate('password');
          final oldRead = api.readSafetyAcceptance();
          final denied = expectLater(oldRead, throwsA(isA<ApiException>()));
          await Future<void>.delayed(Duration.zero);
          await authenticate(
            'google',
          ); // Same synthetic token, different generation.
          expectSync(await api.readSafetyAcceptance(), isTrue);
          pending.complete(receipt(false));
          await denied;
          expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
        },
        () => isolated((request) async {
          if (isAuth(request)) return auth();
          return ++reads == 1 ? pending.future : receipt(true);
        }),
      );
    },
  );

  testWidgets(
    'expiry while receipt is pending removes entry and ignores success',
    (tester) async {
      final state = DermaireState();
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await authenticate('google');
          await tester.pumpWidget(
            MaterialApp(home: PatientEntryGate(state: state)),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 3));
          expectSync(api.isAuthenticated, isFalse);
          expectSync(find.byType(AppShell), findsNothing);
          pending.complete(receipt(true));
          await tester.pumpAndSettle();
          expectSync(state.safetyAccepted, isFalse);
          expectSync(find.byType(AppShell), findsNothing);
          expectSync(find.textContaining('expired'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated(
          (request) async => isAuth(request) ? auth(ttl: 2) : pending.future,
        ),
      );
      state.dispose();
    },
  );

  testWidgets(
    'fast account switch discards old private routes and verifies new user',
    (tester) async {
      final newRead = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await tester.pumpWidget(const DermaireApp());
          await tester.pumpAndSettle();
          await authenticate('password');
          final nav = tester.state<NavigatorState>(find.byType(Navigator));
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Old private page')),
            ),
          );
          await tester.pumpAndSettle();
          expectSync(find.text('Old private page'), findsOneWidget);
          // The auth result arrives before the main app's queued session reset.
          await api.login(
            email: 'new@example.invalid',
            password: 'Synthetic123!',
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expectSync(find.text('Old private page'), findsNothing);
          expectSync(find.byType(AppShell), findsNothing);
          expectSync(
            find.textContaining('Confirming your safety acceptance'),
            findsOneWidget,
          );
          newRead.complete(receipt(false, owner: 'patient-2'));
          await tester.pumpAndSettle();
          expectSync(find.byType(SafetyResponsibilityScreen), findsOneWidget);
          expectSync(api.hasConfirmedSafetyAcceptance, isFalse);
          await api.init();
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((request) async {
          if (isAuth(request)) {
            return auth(
              owner: request.body.contains('new@example.invalid')
                  ? 'patient-2'
                  : 'patient-1',
            );
          }
          if (request.url.path.endsWith('/users/me')) {
            expectSync(
              request.headers['Authorization'],
              'Bearer synthetic-patient-2',
            );
            return newRead.future;
          }
          return http.Response('{}', 200);
        }),
      );
    },
  );

  testWidgets('actual auth timeout cannot establish a late session', (
    tester,
  ) async {
    final state = DermaireState();
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(home: SignInScreen(state: state)));
      await tester.enterText(
        find.byKey(const Key('signInEmail')),
        'synthetic@example.invalid',
      );
      await tester.enterText(
        find.byKey(const Key('signInPassword')),
        'Synthetic123!',
      );
      await tester.tap(find.byKey(const Key('signInButton')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 21));
      await tester.pumpAndSettle();
      expectSync(api.isAuthenticated, isFalse);
      expectSync(find.byType(AppShell), findsNothing);
      expectSync(
        tester
            .widget<FilledButton>(find.byKey(const Key('signInButton')))
            .onPressed,
        isNotNull,
      );
      pending.complete(auth());
      await tester.pumpAndSettle();
      expectSync(api.isAuthenticated, isFalse);
      expectSync(find.byType(AppShell), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, () => isolated((request) async => pending.future));
    state.dispose();
  });

  for (final writing in [false, true]) {
    testWidgets(
      'sign-out from pending consent read/write=$writing cannot enter',
      (tester) async {
        final state = DermaireState();
        final pending = Completer<http.Response>();
        await http.runWithClient(
          () async {
            await authenticate('google');
            await tester.pumpWidget(
              MaterialApp(home: PatientEntryGate(state: state)),
            );
            await tester.pump();
            if (writing) await acceptInWidget(tester);
            await tester.tap(find.byKey(const Key('consentSignOut')));
            await tester.pumpAndSettle();
            expectSync(api.isAuthenticated, isFalse);
            expectSync(find.byType(WelcomeScreen), findsOneWidget);
            pending.complete(receipt(true));
            await tester.pumpAndSettle();
            expectSync(find.byType(AppShell), findsNothing);
            expectSync(state.safetyAccepted, isFalse);
            await tester.pumpWidget(const SizedBox());
          },
          () => isolated((request) async {
            if (isAuth(request)) return auth();
            if (request.url.path.endsWith('/auth/logout')) {
              return http.Response('', 204);
            }
            if (request.method == 'POST' || !writing) return pending.future;
            return receipt(false);
          }),
        );
        state.dispose();
      },
    );
  }
}
