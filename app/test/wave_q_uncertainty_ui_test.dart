import 'dart:convert';
import 'package:dermaire_app/integration/contract.dart';
import 'package:dermaire_app/recovery/recovery_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_product_receipt_test.dart' as product;
import 'product_authority_test.dart' as auth;
import 'm6_doctor_fixture.dart' as base;

class VerificationWire extends product.Wire {
  @override
  Future<http.Response> call(http.Request r) {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/auth/logout')) {
      return Future.value(http.Response('', 204));
    }
    return super.call(r);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final dark in [false, true]) {
    testWidgets(
      'unknown → late original commit → unavailable verification stays no-write dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final w = VerificationWire()..loss = 'before';
        await w.run((c) async {
          try {
            await w.submit(c);
            w.lookupStatus = 401;
            await c.recoverProductOperation();
            w.lookupStatus = 200;
            await auth.login();
            final key = api.quarantinedOperations.single.key;
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
                home: const RecoveryReviewScreen(),
              ),
            );
            await t.pumpAndSettle();
            Future<void> verify() async {
              final button = find.text('Check original product receipt');
              await t.scrollUntilVisible(button, 200);
              await t.ensureVisible(button);
              await t.pumpAndSettle();
              await t.tap(button);
              await t.pumpAndSettle();
            }

            await verify();
            expect(find.text('Original outcome unknown'), findsOneWidget);
            expect(find.text('Finish verified receipt review'), findsNothing);
            expect(
              find.textContaining(
                'Do not submit a replacement while the original outcome is unknown.',
              ),
              findsOneWidget,
            );
            w.committed = {
              ...w.current!,
              'revision': 9,
              ...jsonDecode(w.originalBody!) as Map<String, dynamic>,
            };
            w.current = Map<String, dynamic>.of(w.committed!);
            await verify();
            expect(
              find.text('Receipt and current record checked'),
              findsOneWidget,
            );
            expect(find.textContaining('Verification read:'), findsOneWidget);
            expect(find.text('Original outcome unknown'), findsNothing);
            w.lookupStatus = 503;
            final finish = find.text('Finish verified receipt review');
            await t.scrollUntilVisible(finish, 200);
            await t.ensureVisible(finish);
            await t.pumpAndSettle();
            await t.tap(finish);
            await t.pumpAndSettle();
            expect(find.text('Verification unavailable'), findsOneWidget);
            expect(
              find.textContaining('No clinical change will be sent.'),
              findsOneWidget,
            );
            expect(
              find.text('Original authorization unavailable'),
              findsNothing,
            );
            expect(w.writes, 1);
            expect(api.quarantinedOperations.single.key, key);
            w.lookupStatus = 200;
            await verify();
            final complete = find.text('Finish verified receipt review');
            await t.scrollUntilVisible(complete, 200);
            await t.ensureVisible(complete);
            await t.pumpAndSettle();
            await t.tap(complete);
            await t.pumpAndSettle();
            expect(api.quarantinedOperations, isEmpty);
            expect(
              find.text('No retained operation identities for this account.'),
              findsOneWidget,
            );
            expect(w.writes, 1);
            expect(t.takeException(), isNull);
            await api.logout();
            await t.pumpAndSettle();
            expect(find.text('Verification unavailable'), findsNothing);
            expect(find.textContaining('Verification read:'), findsNothing);
            await t.pumpWidget(const SizedBox.shrink());
          } finally {
            await api.init();
          }
        });
      },
    );
    testWidgets(
      'unsupported contracts provide honest next actions and no fabricated receipt dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final wire = base.DoctorWire()
          ..owner = 'patient-1'
          ..role = 'patient';
        int extraWrites = 0;
        await http.runWithClient(
          () async {
            try {
              await wire.login();
              for (final path in [
                'agent/requests/action-1/decision',
                'notifications/preferences',
                'routine/calendar-policy',
              ]) {
                api.integrationIntents[path] = PendingIntent(
                  path: path,
                  attemptPath: '',
                  body: {
                    'rationale': 'Synthetic private request narrative',
                    'expected_revision': 1,
                  },
                );
              }
              await expectLater(
                api.integrationResource(
                  'agent/requests',
                  api.sessionGeneration,
                ),
                throwsA(anything),
              );
              expect(api.isAuthenticated, false);
              await wire.login();
              expect(api.quarantinedOperations.length, 3);
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
                  home: const RecoveryReviewScreen(),
                ),
              );
              await t.pumpAndSettle();
              final scroll = find.byType(Scrollable).first;
              for (final marker in [
                'No independent original confirmed-request receipt is exposed.',
                'without an independent original-attempt receipt.',
                'without a keyed receipt.',
              ]) {
                final text = find.textContaining(marker);
                await t.scrollUntilVisible(text, 200, scrollable: scroll);
                expect(text, findsOneWidget);
              }
              expect(
                find.text('Synthetic private request narrative'),
                findsNothing,
              );
              expect(find.byType(OutlinedButton), findsNothing);
              expect(extraWrites, 0);
              expect(api.quarantinedOperations.length, 3);
              expect(t.takeException(), isNull);
              await t.pumpWidget(const SizedBox.shrink());
            } finally {
              await api.init();
            }
          },
          () => MockClient((r) {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.url.path.endsWith('/agent/requests')) {
              return Future.value(http.Response('{}', 401));
            }
            if (r.method != 'GET' && !r.url.path.endsWith('/auth/login')) {
              extraWrites++;
            }
            return wire.call(r);
          }),
        );
      },
    );
  }
}
