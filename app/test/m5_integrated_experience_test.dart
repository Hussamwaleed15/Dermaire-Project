import 'dart:io';
import 'dart:async';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/experiments/experiment_ui.dart';
import 'package:dermaire_app/products/products_ui.dart';
import 'experiment_authority_test.dart' as e;
import 'package:dermaire_app/services/recovery_notice.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/products/product.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/notifications/notification_availability.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm5_offline_recovery_test.dart' as n;
import 'product_authority_test.dart' as p;
import 'm4_integrated_test.dart' as j;
import 'observation_test.dart' as o;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      for (final reduced in [false, true]) {
        testWidgets(
          'recovery remains readable and accessible dark=$dark scale=$scale reduced=$reduced',
          (tester) async {
            tester.view.physicalSize = const Size(320, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            var refreshes = 0;
            Widget build(bool busy) => MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(scale),
                  disableAnimations: reduced,
                ),
                child: child!,
              ),
              home: Scaffold(
                body: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    RecoveryNotice(
                      message:
                          'The service could not be reached. Check your connection and retry.',
                      hasPreviousData: true,
                      confirmedAt: DateTime.utc(2026, 10, 13, 12),
                      uncertainWrite: true,
                      busy: busy,
                      onRefresh: () => refreshes++,
                    ),
                  ],
                ),
              ),
            );
            await tester.pumpWidget(build(false));
            await tester.pumpAndSettle();
            expect(
              find.textContaining('not clinical clearance'),
              findsOneWidget,
            );
            await tester.scrollUntilVisible(find.text('Refresh'), 150);
            await tester.pumpAndSettle();
            await tester.tap(find.text('Refresh'));
            expect(refreshes, 1);
            final semantics = tester.ensureSemantics();
            expect(tester, meetsGuideline(labeledTapTargetGuideline));
            expect(tester, meetsGuideline(textContrastGuideline));
            semantics.dispose();
            await tester.pumpWidget(build(true));
            await tester.pump();
            expect(
              tester
                  .widget<OutlinedButton>(find.byType(OutlinedButton))
                  .onPressed,
              isNull,
            );
            expect(
              find.byType(LinearProgressIndicator),
              reduced ? findsNothing : findsOneWidget,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
  for (final mode in ['stale', 'loading']) {
    test(
      'creation blocked by $mode before dispatch has no uncertain receipt',
      () async {
        final wire = n.Wire();
        await wire.run(() async {
          await p.login();
          final c = ProductsController(RemoteProductRepository());
          if (mode == 'stale') {
            await c.load();
            wire.status = 503;
            await c.load();
          }
          final product = Product.fromApi(p.row('Synthetic new product'));
          expect((await c.add(product)).success, false);
          expect(c.createUncertain, false);
          expect(wire.writes, 0);
          wire.status = null;
          await c.load();
          expect((await c.add(product)).success, false);
          expect(
            c.createUncertain,
            true,
          ); // Actual dispatched timeout is unknown.
          expect(wire.writes, 1);
          await c.load();
          expect(c.createUncertain, true);
          expect((await c.add(product)).success, false);
          expect(wire.writes, 1);
          c.dispose();
        });
      },
    );
  }
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'routine offline → GET recovery → uncertain write is honest dark=$dark large=$large',
        (tester) async {
          final f = j.Journey();
          var offline = false;
          await http.runWithClient(
            () async {
              await f.login();
              await j.mount(
                tester,
                RoutineScreen(state: f.state),
                dark: dark,
                large: large,
              );
              expect(find.text('Safety & clinician guidance'), findsOneWidget);
              offline = true;
              await tester.tap(find.byTooltip('Refresh routine'));
              await tester.pumpAndSettle();
              await j.reveal(tester, find.text('Retry'));
              expect(find.byType(RecoveryNotice), findsOneWidget);
              expect(
                find.textContaining('could not be reached'),
                findsOneWidget,
              );
              expect(
                find.textContaining('Last confirmed read:'),
                findsOneWidget,
              );
              expect(f.reportPosts, 0);
              offline = false;
              await tester.tap(find.text('Retry'));
              await tester.pumpAndSettle();
              expect(find.byType(RecoveryNotice), findsNothing);
              f.failReport = true;
              await j.reveal(tester, find.text('AM completed today'));
              await tester.tap(find.text('AM completed today'));
              await tester.pumpAndSettle();
              final scroll = tester.state<ScrollableState>(
                find.byType(Scrollable).first,
              );
              scroll.position.jumpTo(0);
              await tester.pumpAndSettle();
              await j.reveal(tester, find.text('Retry'));
              expect(
                find.textContaining('previous change is still unconfirmed'),
                findsOneWidget,
              );
              expect(find.text('Saved on server'), findsNothing);
              expect(f.reportPosts, 1);
              f.failReport = false;
              await tester.tap(find.text('Retry'));
              await tester.pumpAndSettle();
              scroll.position.jumpTo(0);
              await tester.pumpAndSettle();
              await j.reveal(tester, find.text('Retry'));
              expect(
                find.textContaining('previous change is still unconfirmed'),
                findsOneWidget,
              );
              expect(
                find.textContaining('Previously confirmed data may be stale'),
                findsNothing,
              );
              expect(f.reportPosts, 1); // Recovered GET never replays the POST.
              await j.reveal(tester, find.text('AM completed today'));
              final button = tester.widget<TextButton>(
                find.widgetWithText(TextButton, 'AM completed today'),
              );
              expect(button.onPressed, isNull);
              expect(
                find.textContaining('Server-confirmed completed report'),
                findsNothing,
              );
              await ApiService.instance.logout();
              await tester.pumpAndSettle();
              expect(
                find.text('Session ended. Reopen your routine.'),
                findsOneWidget,
              );
              expect(find.byType(RecoveryNotice), findsNothing);
              expect(find.textContaining('Inventory'), findsNothing);
              expect(tester.takeException(), isNull);
              await f.done(tester);
            },
            () => o.isolated((request) async {
              if (offline &&
                  request.method == 'GET' &&
                  request.url.path.contains('/routine/')) {
                throw const SocketException('synthetic DNS failure');
              }
              return f.transport(request);
            }),
          );
        },
      );
    }
  }
  for (final dark in [false, true]) {
    testWidgets(
      'experiment retry keeps changes disabled until verified GET dark=$dark',
      (tester) async {
        final repo = e.Repository()
          ..rows = [e.experiment()]
          ..fail = true;
        final c = ExperimentController(repo);
        await c.refresh();
        await j.mount(
          tester,
          Scaffold(body: ExperimentsView(controller: c, autoLoad: false)),
          dark: dark,
          large: true,
        );
        expect(find.byKey(const Key('experimentError')), findsOneWidget);
        await j.reveal(tester, find.text('Plan one change'));
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Plan one change'),
              )
              .onPressed,
          isNull,
        );
        final scroll = tester.state<ScrollableState>(
          find.byType(Scrollable).first,
        );
        scroll.position.jumpTo(0);
        await tester.pumpAndSettle();
        await j.reveal(tester, find.text('Refresh experiments'));
        repo.fail = false;
        repo.pending = Completer();
        await tester.tap(find.text('Refresh experiments'));
        await tester.pump();
        expect(c.loading, true);
        expect(
          find.byType(LinearProgressIndicator),
          findsNothing,
        ); // Reduced motion.
        final retry = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Refresh experiments'),
        );
        expect(retry.onPressed, isNull);
        repo.pending!.complete([]);
        repo.pending = null;
        await tester.pumpAndSettle();
        expect(c.stale, false);
        expect(find.byType(RecoveryNotice), findsNothing);
        expect(find.text('No experiments yet.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
    testWidgets(
      'product recovery has no fake creation or empty success dark=$dark',
      (tester) async {
        final f = j.Journey();
        var offline = false;
        await http.runWithClient(
          () async {
            await f.login();
            offline = true;
            await f.state.productController.load();
            await j.mount(
              tester,
              Scaffold(body: ProductsFeatureTab(state: f.state)),
              dark: dark,
              large: true,
            );
            expect(
              tester
                  .widget<IconButton>(find.byKey(const Key('addProduct')))
                  .onPressed,
              isNull,
            );
            await j.reveal(tester, find.text('Retry refresh'));
            expect(find.byType(RecoveryNotice), findsOneWidget);
            expect(find.textContaining('could not be reached'), findsOneWidget);
            expect(f.state.productController.createUncertain, false);
            offline = false;
            await tester.tap(find.text('Retry refresh'));
            await tester.pumpAndSettle();
            expect(f.state.productController.isStale, false);
            expect(find.byType(RecoveryNotice), findsNothing);
            await j.reveal(tester, find.text('Synthetic serum'));
            expect(find.text('Synthetic serum'), findsOneWidget);
            expect(
              f.requests.where(
                (r) => r.method != 'GET' && !r.url.path.endsWith('/auth/login'),
              ),
              isEmpty,
            );
            expect(tester.takeException(), isNull);
            await f.done(tester);
          },
          () => o.isolated((request) async {
            if (offline && request.url.path.endsWith('/products')) {
              throw const SocketException('synthetic connection');
            }
            return f.transport(request);
          }),
        );
      },
    );
  }
  testWidgets(
    'notification explanation opens and Back returns without a feed or permission flow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationAvailabilityScreen(),
                  ),
                ),
                child: const Text('Notification availability'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Notification availability'));
      await tester.pumpAndSettle();
      expect(find.text('Notifications are unavailable'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Notification availability'), findsOneWidget);
      expect(find.byType(NotificationAvailabilityScreen), findsNothing);
    },
  );
}
