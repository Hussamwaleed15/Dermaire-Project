import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/account/account_controller.dart';
import 'package:dermaire_app/account/account_profile.dart';
import 'package:dermaire_app/account/account_summary.dart';
import 'package:dermaire_app/app_shell.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/onboarding_screens.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final api = ApiService.instance;
Map<String, dynamic> user({
  String owner = 'a',
  String? goal = 'Track changes',
}) => {
  'id': owner,
  'role': 'patient',
  'full_name': 'Synthetic $owner',
  'email': '$owner@example.invalid',
  'safety_accepted': true,
  'skin_type': 'dry',
  'selected_goal': goal,
  'skin_concerns': ['dryness'],
  'profile_context': {
    'age_band': 'prefer_not_to_say',
    'sex': null,
    'sensitivities_allergies': [],
    'primary_goals': ['Track changes'],
    'hormonal_disclosure': 'prefer_not_to_say',
    'hormonal_context': null,
  },
};
http.Response response(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);
http.Response auth({String owner = 'a', int ttl = 3600}) => response({
  'access_token': 'synthetic-$owner',
  'expires_in': ttl,
  'user_id': owner,
  'role': 'patient',
  'full_name': 'Token name must not hydrate',
});
bool isAuth(http.Request r) =>
    ['/auth/login', '/auth/google', '/auth/register'].any(r.url.path.endsWith);
MockClient isolated(Future<http.Response> Function(http.Request) handler) =>
    MockClient((r) {
      expectSync(r.url.host, 'flutter-tests.invalid');
      return handler(r);
    });
Future<void> login({String owner = 'a'}) async {
  await api.login(email: '$owner@example.invalid', password: 'Synthetic123!');
  await api.readSafetyAcceptance();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  test(
    'typed profile preserves omitted/null/empty/unknown values and is immutable',
    () {
      final raw = user()
        ..remove('skin_type')
        ..['selected_goal'] = ''
        ..['skin_concerns'] = null;
      final profile = AccountProfile.fromApi(raw, owner: 'a', role: 'patient');
      expectSync(profile.skinType, isNull);
      expectSync(profile.selectedGoal, '');
      expectSync(profile.skinConcerns, isNull);
      expectSync(profile.context!['sex'], isNull);
      expectSync(profile.context!['age_band'], 'prefer_not_to_say');
      expectSync(profile.context!['sensitivities_allergies'], isEmpty);
      expectSync(
        profile.context!.containsKey('medications_treatments'),
        isFalse,
      );
      (raw['profile_context'] as Map)['age_band'] = '25_34';
      expectSync(profile.context!['age_band'], 'prefer_not_to_say');
      expectSync(
        () => (profile.context!['primary_goals'] as List).add('changed'),
        throwsUnsupportedError,
      );
      expectSync(profile.partial, isTrue);
    },
  );

  test(
    'consent GET hydrates identity/role/profile once and ignores local/token data',
    () async {
      SharedPreferences.setMockInitialValues({
        'profile_completed': true,
        'profile': '{"full_name":"Local account"}',
      });
      final state = DermaireState();
      var reads = 0;
      await http.runWithClient(
        () async {
          await login();
          expectSync(state.userName, isEmpty);
          expectSync(await state.account.hydrate(), isTrue);
          expectSync(reads, 1);
          expectSync(state.userName, 'Synthetic a');
          expectSync(state.userEmail, 'a@example.invalid');
          expectSync(state.userRole, 'patient');
          expectSync(state.selectedGoal, 'Track changes');
          expectSync(state.skinConcerns, {'dryness'});
          expectSync(state.account.value!.context!['sex'], isNull);
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          reads++;
          return response(user());
        }),
      );
      state.dispose();
    },
  );

  for (final bad in ['owner', 'role', 'email', 'name', 'context', 'concerns']) {
    test(
      'invalid $bad cannot populate account; valid consent survives',
      () async {
        final state = DermaireState();
        final raw = user();
        var reads = 0;
        switch (bad) {
          case 'owner':
            raw['id'] = 'other';
          case 'role':
            raw['role'] = 'doctor';
          case 'email':
            raw.remove('email');
          case 'name':
            raw['full_name'] = 12;
          case 'context':
            raw['profile_context'] = false;
          case 'concerns':
            raw['skin_concerns'] = [false];
        }
        await http.runWithClient(
          () async {
            await login();
            expectSync(
              await state.account.hydrate(reuseConsent: false),
              isFalse,
            );
            expectSync(state.account.value, isNull);
            expectSync(state.userEmail, isEmpty);
            expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
            expectSync(
              state.account.error,
              'Account profile could not be verified. Please retry.',
            );
          },
          () => isolated((r) async {
            if (isAuth(r)) return auth();
            return response(++reads > 1 ? raw : user());
          }),
        );
        state.dispose();
      },
    );
  }

  for (final failure in [
    '401',
    '403',
    '500',
    '503',
    'offline',
    'timeout',
    'malformed',
  ]) {
    test(
      'hydration $failure is explicit and retry never fabricates an empty profile',
      () async {
        final state = DermaireState();
        var reads = 0;
        var fail = true;
        await http.runWithClient(
          () async {
            await login();
            await state.account.hydrate();
            expectSync(state.userName, isNotEmpty);
            expectSync(
              await state.account.hydrate(reuseConsent: false),
              isFalse,
            );
            expectSync(state.userName, isEmpty);
            expectSync(state.account.value, isNull);
            if (failure == '401') {
              expectSync(api.isAuthenticated, isFalse);
              expectSync(state.account.phase, AccountPhase.unauthorized);
            } else {
              expectSync(state.account.phase, AccountPhase.unavailable);
              expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
              expectSync(state.account.error, isNotNull);
              fail = false;
              expectSync(
                await state.account.hydrate(reuseConsent: false),
                isTrue,
              );
              expectSync(state.userName, 'Synthetic a');
            }
          },
          () => isolated((r) async {
            if (isAuth(r)) return auth();
            if (++reads == 1 || !fail) return response(user());
            if (failure == 'offline') {
              throw http.ClientException('synthetic offline');
            }
            if (failure == 'timeout') {
              throw TimeoutException('synthetic timeout');
            }
            if (failure == 'malformed') {
              return http.Response('synthetic invalid JSON', 200);
            }
            return http.Response('synthetic unavailable', int.parse(failure));
          }),
        );
        state.dispose();
      },
    );
  }

  for (final oldStatus in [200, 401, 403, 503]) {
    test('A to B late response $oldStatus cannot show A or clear B', () async {
      final state = DermaireState();
      final pending = Completer<http.Response>();
      var hold = false;
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          hold = true;
          final first = state.account.hydrate(reuseConsent: false);
          await Future<void>.delayed(Duration.zero);
          await api.logout();
          expectSync(state.userEmail, isEmpty);
          await login(owner: 'b');
          await state.account.hydrate();
          pending.complete(response(user(), oldStatus));
          await first;
          expectSync(state.userName, 'Synthetic b');
          expectSync(state.userEmail, 'b@example.invalid');
          expectSync(api.authToken, 'synthetic-b');
          expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
        },
        () => isolated((r) async {
          if (isAuth(r)) {
            return auth(
              owner: r.body.contains('b@example.invalid') ? 'b' : 'a',
            );
          }
          if (r.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }
          if (hold && r.headers['Authorization'] == 'Bearer synthetic-a') {
            return pending.future;
          }
          return response(
            user(
              owner: r.headers['Authorization'] == 'Bearer synthetic-b'
                  ? 'b'
                  : 'a',
            ),
          );
        }),
      );
      state.dispose();
    });
  }

  test('latest overlapping profile load wins within same session', () async {
    final state = DermaireState();
    final pending = Completer<http.Response>();
    var reads = 0;
    await http.runWithClient(
      () async {
        await login();
        await state.account.hydrate();
        final old = state.account.hydrate(reuseConsent: false);
        await Future<void>.delayed(Duration.zero);
        final newer = state.account.hydrate(reuseConsent: false);
        expectSync(await newer, isTrue);
        pending.complete(response(user(goal: 'Old goal')));
        await old;
        expectSync(state.selectedGoal, 'New goal');
        expectSync(api.currentUser!['selected_goal'], 'New goal');
      },
      () => isolated((r) async {
        if (isAuth(r)) return auth();
        return ++reads == 2
            ? pending.future
            : response(user(goal: reads == 3 ? 'New goal' : 'Initial goal'));
      }),
    );
    state.dispose();
  });

  test(
    'logout/login same account clears old data and obtains fresh profile',
    () async {
      final state = DermaireState();
      var name = 'First name';
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          expectSync(state.userName, 'First name');
          await api.logout();
          expectSync(state.account.value, isNull);
          name = 'Current name';
          await login();
          await state.account.hydrate();
          expectSync(state.userName, 'Current name');
          final prefs = await SharedPreferences.getInstance();
          expectSync(prefs.getKeys(), isEmpty);
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          if (r.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }
          return response(user()..['full_name'] = name);
        }),
      );
      state.dispose();
    },
  );

  for (final failure in [
    '401',
    '403',
    '503',
    'offline',
    'timeout',
    'malformed',
    'owner',
  ]) {
    test(
      'PATCH $failure is unconfirmed and never replaces visible profile',
      () async {
        final state = DermaireState();
        await http.runWithClient(
          () async {
            await login();
            await state.account.hydrate();
            expectSync(
              await state.account.save({'selected_goal': 'Changed'}),
              ProfileSaveResult.unconfirmed,
            );
            expectSync(
              state.selectedGoal,
              failure == '401' ? isEmpty : 'Track changes',
            );
            expectSync(state.account.saving, isFalse);
          },
          () => isolated((r) async {
            if (isAuth(r)) return auth();
            if (r.method != 'PATCH') return response(user());
            if (failure == 'offline') {
              throw http.ClientException('synthetic offline');
            }
            if (failure == 'timeout') {
              throw TimeoutException('synthetic timeout');
            }
            if (failure == 'malformed') {
              return http.Response('synthetic invalid JSON', 200);
            }
            if (failure == 'owner') return response(user(owner: 'b'));
            return http.Response('synthetic failure', int.parse(failure));
          }),
        );
        state.dispose();
      },
    );
  }

  for (final failedReadback in [false, true]) {
    test(
      'confirmed PATCH/readback synchronization unavailable=$failedReadback',
      () async {
        final state = DermaireState();
        var wrote = false;
        var posts = 0;
        await http.runWithClient(
          () async {
            await login();
            await state.account.hydrate();
            final save = state.account.save({
              'skin_type': null,
              'selected_goal': '',
              'profile_context': {'sex': null, 'primary_goals': []},
            });
            expectSync(
              await state.account.save({'selected_goal': 'duplicate'}),
              ProfileSaveResult.unconfirmed,
            );
            expectSync(
              await save,
              failedReadback
                  ? ProfileSaveResult.savedReadbackUnavailable
                  : ProfileSaveResult.saved,
            );
            expectSync(posts, 1);
            expectSync(state.account.value!.skinType, isNull);
            expectSync(state.selectedGoal, '');
            expectSync(state.account.value!.context!['sex'], isNull);
            expectSync(state.account.value!.context!['primary_goals'], isEmpty);
            if (failedReadback) {
              expectSync(state.account.error, contains('Profile saved'));
              expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
            } else {
              expectSync(state.userName, 'Readback name');
            }
          },
          () => isolated((r) async {
            if (isAuth(r)) return auth();
            if (r.method == 'PATCH') {
              posts++;
              wrote = true;
              expectSync(jsonDecode(r.body)['profile_context'], {
                'sex': null,
                'primary_goals': [],
              });
              return response(
                user(goal: '')
                  ..['skin_type'] = null
                  ..['profile_context'] = {'sex': null, 'primary_goals': []},
              );
            }
            if (wrote && failedReadback) return http.Response('', 503);
            return response(
              wrote
                  ? (user(goal: '')
                      ..['full_name'] = 'Readback name'
                      ..['skin_type'] = null
                      ..['profile_context'] = {
                        'sex': null,
                        'primary_goals': [],
                      })
                  : user(),
            );
          }),
        );
        state.dispose();
      },
    );
  }

  test(
    'deleted account clears profile immediately after confirmed 204',
    () async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          expectSync(await api.deleteAccount(), isTrue);
          expectSync(state.userName, isEmpty);
          expectSync(state.userEmail, isEmpty);
          expectSync(state.userRole, isNull);
          expectSync(state.account.value, isNull);
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          return r.method == 'DELETE'
              ? http.Response('', 204)
              : response(user());
        }),
      );
      state.dispose();
    },
  );

  for (final flow in ['password', 'google', 'register']) {
    testWidgets(
      '$flow entry hydrates one GET and displays authenticated profile',
      (tester) async {
        final state = DermaireState();
        var reads = 0;
        await http.runWithClient(
          () async {
            await tester.pumpWidget(
              MaterialApp(
                home: flow == 'register'
                    ? SafetyResponsibilityScreen(
                        state: state,
                        email: 'a@example.invalid',
                        password: 'Synthetic123!',
                      )
                    : SignInScreen(
                        state: state,
                        googleSignIn: () async => 'synthetic-google',
                      ),
              ),
            );
            if (flow == 'password') {
              await tester.enterText(
                find.byKey(const Key('signInEmail')),
                'a@example.invalid',
              );
              await tester.enterText(
                find.byKey(const Key('signInPassword')),
                'Synthetic123!',
              );
              await tester.tap(find.byKey(const Key('signInButton')));
            } else if (flow == 'google') {
              await tester.tap(find.text('Continue with Google'));
            } else {
              await tester.drag(
                find.byKey(const Key('safetyScroll')),
                const Offset(0, -3000),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const Key('acceptSafetyButton')));
            }
            await tester.pumpAndSettle();
            expectSync(reads, 1);
            expectSync(state.userName, 'Synthetic a');
            expectSync(state.userRole, 'patient');
            if (flow != 'register') {
              expectSync(find.byType(AppShell), findsNothing);
              await tester.tap(find.byKey(const Key('continueEntry')));
              await tester.pumpAndSettle();
            }
            expectSync(
              find.byType(flow == 'register' ? AccountCreatedScreen : AppShell),
              findsOneWidget,
            );
            await api.init();
            await tester.pumpWidget(const SizedBox());
          },
          () => isolated((r) async {
            if (isAuth(r)) return auth();
            if (r.url.path.endsWith('/users/me')) {
              reads++;
              return response(user());
            }
            return http.Response('{}', 200);
          }),
        );
        state.dispose();
      },
    );
  }

  testWidgets(
    'empty optional profile remains valid and visible without completion inference',
    (tester) async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: AccountSummary(account: state.account)),
            ),
          );
          expectSync(find.text('Synthetic a'), findsOneWidget);
          expectSync(find.text('Skin type: Not shared'), findsOneWidget);
          expectSync(state.account.phase, AccountPhase.partial);
          expectSync(state.account.ready, isTrue);
          expectSync(
            state.account.value!.context!['age_band'],
            'prefer_not_to_say',
          );
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          return response(
            user(goal: null)
              ..['skin_type'] = null
              ..['skin_concerns'] = [],
          );
        }),
      );
      state.dispose();
    },
  );

  for (final expire in [false, true]) {
    testWidgets(
      'logout/expiry during pending hydration invalidates visible data expiry=$expire',
      (tester) async {
        final state = DermaireState();
        final pending = Completer<http.Response>();
        var reads = 0;
        await http.runWithClient(
          () async {
            await login();
            await state.account.hydrate();
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(body: AccountSummary(account: state.account)),
              ),
            );
            final request = state.account.hydrate(reuseConsent: false);
            await tester.pump();
            expectSync(find.text('Synthetic a'), findsNothing);
            if (expire) {
              await tester.pump(const Duration(seconds: 3));
            } else {
              await api.logout();
            }
            pending.complete(response(user()));
            await request;
            await tester.pumpAndSettle();
            expectSync(state.account.value, isNull);
            expectSync(state.userName, isEmpty);
            expectSync(find.text('Synthetic a'), findsNothing);
            await tester.pumpWidget(const SizedBox());
          },
          () => isolated((r) async {
            if (isAuth(r)) return auth(ttl: expire ? 2 : 3600);
            if (r.url.path.endsWith('/auth/logout')) {
              return http.Response('', 204);
            }
            return ++reads == 1 ? response(user()) : pending.future;
          }),
        );
        state.dispose();
      },
    );
  }

  testWidgets(
    'real hydration timeout hides data, preserves consent and allows retry',
    (tester) async {
      final state = DermaireState();
      final pending = Completer<http.Response>();
      var reads = 0;
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: AccountSummary(account: state.account)),
            ),
          );
          final request = state.account.hydrate(reuseConsent: false);
          await tester.pump();
          await tester.pump(const Duration(seconds: 21));
          await request;
          await tester.pumpAndSettle();
          expectSync(state.account.value, isNull);
          expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
          expectSync(
            find.text('Profile loading timed out. Please retry.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Retry profile'));
          await tester.pumpAndSettle();
          expectSync(state.userName, 'Synthetic a');
          pending.complete(response(user(owner: 'b')));
          await tester.pumpAndSettle();
          expectSync(state.userName, 'Synthetic a');
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          return ++reads == 2 ? pending.future : response(user());
        }),
      );
      state.dispose();
    },
  );

  testWidgets(
    'profile editor clears A draft and cannot expose B after account switch',
    (tester) async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await tester.pumpWidget(
            MaterialApp(home: SkinProfileScreen(state: state, editing: true)),
          );
          await tester.enterText(
            find.byKey(const ValueKey('skin_concerns')),
            'Private draft A',
          );
          await api.logout();
          await login(owner: 'b');
          await state.account.hydrate();
          await tester.pumpAndSettle();
          expectSync(find.text('Private draft A'), findsNothing);
          expectSync(find.byKey(const Key('saveProfile')), findsNothing);
          expectSync(find.text('Synthetic b'), findsNothing);
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((r) async {
          if (isAuth(r)) {
            return auth(
              owner: r.body.contains('b@example.invalid') ? 'b' : 'a',
            );
          }
          if (r.url.path.endsWith('/auth/logout')) {
            return http.Response('', 204);
          }
          return response(
            user(
              owner: r.headers['Authorization'] == 'Bearer synthetic-b'
                  ? 'b'
                  : 'a',
            ),
          );
        }),
      );
      state.dispose();
    },
  );

  test('fresh profile false consent cannot bypass the F1b-1 gate', () async {
    final state = DermaireState();
    var reads = 0;
    await http.runWithClient(
      () async {
        await login();
        await state.account.hydrate();
        expectSync(await state.account.hydrate(reuseConsent: false), isFalse);
        expectSync(api.hasConfirmedSafetyAcceptance, isFalse);
        expectSync(state.account.value, isNull);
      },
      () => isolated((r) async {
        if (isAuth(r)) return auth();
        return response(user()..['safety_accepted'] = ++reads == 1);
      }),
    );
    state.dispose();
  });

  test(
    'failed replacement login erases the previous hydrated account',
    () async {
      final state = DermaireState();
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await expectLater(
            api.login(email: 'fail@example.invalid', password: 'Synthetic123!'),
            throwsA(isA<ApiException>()),
          );
          expectSync(state.userName, isEmpty);
          expectSync(state.userEmail, isEmpty);
          expectSync(state.account.value, isNull);
          expectSync(api.isAuthenticated, isFalse);
        },
        () => isolated((r) async {
          if (isAuth(r)) {
            return r.body.contains('fail@example.invalid')
                ? response({'message': 'Invalid credentials'}, 401)
                : auth();
          }
          return response(user());
        }),
      );
      state.dispose();
    },
  );

  test(
    'old GET cannot override confirmed PATCH and subsequent readback',
    () async {
      final state = DermaireState();
      final pending = Completer<http.Response>();
      var reads = 0;
      var wrote = false;
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          final old = api.readAccountProfile(reuseConsent: false);
          final denied = expectLater(
            old,
            throwsA(isA<ProfileRequestException>()),
          );
          await Future<void>.delayed(Duration.zero);
          expectSync(
            await state.account.save({'selected_goal': 'New server goal'}),
            ProfileSaveResult.saved,
          );
          pending.complete(response(user(goal: 'Old goal')));
          await denied;
          expectSync(state.selectedGoal, 'New server goal');
          expectSync(api.currentUser!['selected_goal'], 'New server goal');
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          if (r.method == 'PATCH') {
            wrote = true;
            return response(user(goal: 'New server goal'));
          }
          return ++reads == 2
              ? pending.future
              : response(
                  user(goal: wrote ? 'New server goal' : 'Initial goal'),
                );
        }),
      );
      state.dispose();
    },
  );

  test('late PATCH after account switch cannot update B', () async {
    final state = DermaireState();
    final pending = Completer<http.Response>();
    await http.runWithClient(
      () async {
        await login();
        await state.account.hydrate();
        final save = state.account.save({'selected_goal': 'Old A write'});
        await Future<void>.delayed(Duration.zero);
        await api.logout();
        await login(owner: 'b');
        await state.account.hydrate();
        pending.complete(response(user(goal: 'Old A write')));
        await save;
        expectSync(state.userEmail, 'b@example.invalid');
        expectSync(state.selectedGoal, 'Track changes');
        expectSync(state.account.saving, isFalse);
      },
      () => isolated((r) async {
        if (isAuth(r)) {
          return auth(owner: r.body.contains('b@example.invalid') ? 'b' : 'a');
        }
        if (r.url.path.endsWith('/auth/logout')) return http.Response('', 204);
        if (r.method == 'PATCH') return pending.future;
        return response(
          user(
            owner: r.headers['Authorization'] == 'Bearer synthetic-b'
                ? 'b'
                : 'a',
          ),
        );
      }),
    );
    state.dispose();
  });

  testWidgets(
    'unverified identity blocks entry and retries profile without losing consent',
    (tester) async {
      final state = DermaireState();
      var reads = 0;
      var accepts = 0;
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
          expectSync(api.hasConfirmedSafetyAcceptance, isTrue);
          expectSync(find.byType(AppShell), findsNothing);
          expectSync(state.userName, isEmpty);
          await tester.tap(find.byKey(const Key('retryAccountProfile')));
          await tester.pumpAndSettle();
          expectSync(find.byType(AppShell), findsNothing);
          await tester.tap(find.byKey(const Key('continueEntry')));
          await tester.pumpAndSettle();
          expectSync(find.byType(AppShell), findsOneWidget);
          expectSync(state.userName, 'Synthetic a');
          expectSync(accepts, 0);
          expectSync(reads, 2);
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          if (r.url.path.endsWith('/auth/accept-safety')) {
            accepts++;
            return response(user());
          }
          if (r.url.path.endsWith('/users/me')) {
            return response(++reads == 1 ? (user()..remove('email')) : user());
          }
          return http.Response('{}', 200);
        }),
      );
      state.dispose();
    },
  );

  testWidgets(
    'confirmed save with failed readback keeps editor and retries GET only',
    (tester) async {
      final state = DermaireState();
      var posts = 0;
      var reads = 0;
      var wrote = false;
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await tester.pumpWidget(
            MaterialApp(home: SkinProfileScreen(state: state, editing: true)),
          );
          await tester.enterText(
            find.byKey(const ValueKey('skin_concerns')),
            'updated',
          );
          await tester.scrollUntilVisible(
            find.byKey(const Key('saveProfile')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const Key('saveProfile')));
          await tester.pumpAndSettle();
          expectSync(find.byType(SkinProfileScreen), findsOneWidget);
          expectSync(
            tester
                .widget<FilledButton>(find.byKey(const Key('saveProfile')))
                .onPressed,
            isNull,
          );
          await tester.scrollUntilVisible(
            find.text('Retry refresh'),
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.text('Retry refresh'));
          await tester.pumpAndSettle();
          expectSync(posts, 1);
          expectSync(state.skinConcerns, {'updated'});
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          if (r.method == 'PATCH') {
            posts++;
            wrote = true;
            return response(user()..['skin_concerns'] = ['updated']);
          }
          if (++reads == 2) return http.Response('', 503);
          return response(
            wrote ? (user()..['skin_concerns'] = ['updated']) : user(),
          );
        }),
      );
      state.dispose();
    },
  );
  testWidgets(
    'successful editor save displays server-normalized readback on return',
    (tester) async {
      final state = DermaireState();
      var wrote = false;
      await http.runWithClient(
        () async {
          await login();
          await state.account.hydrate();
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => Column(
                    children: [
                      AccountSummary(account: state.account),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                SkinProfileScreen(state: state, editing: true),
                          ),
                        ),
                        child: const Text('Edit profile'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Edit profile'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('skin_concerns')),
            'user draft',
          );
          await tester.scrollUntilVisible(
            find.byKey(const Key('saveProfile')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(const Key('saveProfile')));
          await tester.pumpAndSettle();
          expectSync(find.byType(SkinProfileScreen), findsNothing);
          expectSync(
            find.text('Skin concerns: Server confirmed'),
            findsOneWidget,
          );
          expectSync(state.skinConcerns, {'Server confirmed'});
          await api.init();
          await tester.pumpWidget(const SizedBox());
        },
        () => isolated((r) async {
          if (isAuth(r)) return auth();
          if (r.method == 'PATCH') {
            expectSync(jsonDecode(r.body)['skin_concerns'], ['user draft']);
            wrote = true;
            return response(user()..['skin_concerns'] = ['PATCH confirmed']);
          }
          return response(
            wrote ? (user()..['skin_concerns'] = ['Server confirmed']) : user(),
          );
        }),
      );
      state.dispose();
    },
  );
}
