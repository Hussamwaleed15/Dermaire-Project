import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/products/products_ui.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/experiments/experiment_ui.dart';
import 'package:dermaire_app/psm/psm_screen.dart';
import 'package:dermaire_app/assistance/assistance_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'product_authority_test.dart' as p;
import 'routine_authority_test.dart' as r;
import 'm4_adherence_test.dart' as a;
import 'experiment_authority_test.dart' as e;
import 'personal_skin_model_test.dart' as m;
import 'clinical_status_test.dart' as c;
import 'home_authority_test.dart' as h;
import 'observation_test.dart' as o;

class Journey {
  String owner = 'a';
  bool failReport = false,
      missingProduct = false,
      missingExperiment = false,
      noConsent = false;
  int productGets = 0, homeGets = 0, reportPosts = 0;
  final requests = <http.Request>[];
  final reports = <Map<String, dynamic>>[];
  late final state = DermaireState();
  Map<String, dynamic> get product => {
    ...p.row('Synthetic serum'),
    'id': 'product',
    'user_id': owner,
  };
  Map<String, dynamic> get experiment => {
    ...e.experiment('active', 'insufficient_evidence'),
    'user_id': owner,
  };
  Future<http.Response> transport(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (path.endsWith('/auth/login')) return o.auth(owner);
    if (path.endsWith('/users/me')) {
      final user = jsonDecode(o.user(owner).body) as Map<String, dynamic>;
      user['safety_accepted'] = !noConsent;
      return o.jsonResponse(user);
    }
    if (path.endsWith('/auth/logout')) return o.jsonResponse({});
    if (path.endsWith('/safety')) {
      return o.jsonResponse(c.safety(status: 'urgent'));
    }
    if (path.endsWith('/doctor/review-status')) {
      return o.jsonResponse(c.review(owner: owner));
    }
    if (path.endsWith('/home')) {
      homeGets++;
      return o.jsonResponse({
        ...h.snapshot(),
        'today_checked_in': false,
        'experiment': null,
        'journal': [],
      });
    }
    if (path.endsWith('/products')) {
      productGets++;
      return o.jsonResponse(missingProduct ? [] : [product]);
    }
    if (path.endsWith('/products/product')) return o.jsonResponse(product);
    if (path.contains('/intelligence')) return o.jsonResponse({}, 404);
    if (path.endsWith('/routine/entries')) return o.jsonResponse([r.entry()]);
    if (path.endsWith('/routine/adherence')) {
      if (request.method == 'POST') {
        reportPosts++;
        if (failReport) throw TimeoutException('synthetic');
        final report = {
          ...a.event(),
          ...jsonDecode(request.body) as Map<String, dynamic>,
        };
        reports.add(report);
        return o.jsonResponse(report, 201);
      }
      return o.jsonResponse(reports);
    }
    if (path.endsWith('/experiments')) {
      return o.jsonResponse(missingExperiment ? [] : [experiment]);
    }
    if (path.endsWith('/personal-skin-model')) {
      return o.jsonResponse(m.payload(owner: owner));
    }
    return o.jsonResponse({}, 404);
  }

  Future<void> run(Future<void> Function() body) =>
      http.runWithClient(body, () => o.isolated(transport));
  Future<void> login() async {
    await o.login(owner);
    await state.account.hydrate();
    await state.clinical.refresh();
    await state.productController.load();
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    state.dispose();
    await ApiService.instance.init();
  }
}

Future<void> mount(
  WidgetTester t,
  Widget screen, {
  bool dark = false,
  bool large = false,
}) async {
  t.view.physicalSize = Size(large ? 320 : 390, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? DermaireTheme.dark : DermaireTheme.light,
      builder: (_, child) => MediaQuery(
        data: MediaQueryData(
          size: Size(large ? 320 : 390, 1000),
          disableAnimations: large,
          accessibleNavigation: large,
          textScaler: TextScaler.linear(large ? 2 : 1),
        ),
        child: child!,
      ),
      home: screen,
    ),
  );
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder target) async {
  final scrollable = t.state<ScrollableState>(find.byType(Scrollable).first);
  for (var step = 0; target.evaluate().isEmpty && step < 300; step++) {
    final next = (scrollable.position.pixels + 300).clamp(
      0.0,
      scrollable.position.maxScrollExtent,
    );
    if (next == scrollable.position.pixels) break;
    scrollable.position.jumpTo(next);
    await t.pumpAndSettle();
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final dark in [false, true]) {
    for (final large in [false, true]) {
      testWidgets(
        'product routine report evidence PSM assistance dark=$dark large=$large',
        (t) async {
          final f = Journey();
          await f.run(() async {
            await f.login();
            await mount(
              t,
              ProductFeatureDetailScreen(state: f.state, productId: 'product'),
              dark: dark,
              large: large,
            );
            await reveal(t, find.text('View linked routine steps'));
            await t.tap(find.text('View linked routine steps'));
            await t.pumpAndSettle();
            expect(find.byType(RoutineScreen), findsOneWidget);
            await reveal(t, find.text('AM completed today'));
            final reads = f.productGets;
            await t.tap(find.text('AM completed today'));
            await t.pumpAndSettle();
            expect(f.reportPosts, 1);
            expect(f.productGets, greaterThan(reads));
            expect(f.state.home.current!['today_checked_in'], false);
            expect(f.reports.single['source'], 'user_reported');
            await reveal(t, find.text('Related experiments'));
            await t.tap(find.text('Related experiments'));
            await t.pumpAndSettle();
            expect(find.text('Related experiments'), findsOneWidget);
            expect(find.byType(ExperimentsView), findsOneWidget);
            await reveal(t, find.text('Evidence and source references'));
            await t.tap(find.text('Evidence and source references'));
            await t.pumpAndSettle();
            expect(
              find.textContaining('not interpreted as percentages'),
              findsOneWidget,
            );
            await reveal(t, find.byKey(const Key('openPersonalSkinModel')));
            await t.tap(find.byKey(const Key('openPersonalSkinModel')));
            await t.pumpAndSettle();
            expect(find.byType(PersonalSkinModelScreen), findsOneWidget);
            await reveal(t, find.text('Ask about my evidence'));
            await t.tap(find.text('Ask about my evidence'));
            await t.pumpAndSettle();
            expect(find.byType(ContextualAssistanceScreen), findsOneWidget);
            expect(
              f.requests.where(
                (r) =>
                    r.url.path.contains('agent') ||
                    r.url.path.contains('comparison'),
              ),
              isEmpty,
            );
            Navigator.of(
              t.element(find.byType(ContextualAssistanceScreen)),
            ).pop();
            await t.pumpAndSettle();
            expect(find.byType(PersonalSkinModelScreen), findsOneWidget);
            Navigator.of(t.element(find.byType(PersonalSkinModelScreen))).pop();
            await t.pumpAndSettle();
            expect(find.byType(ExperimentsView), findsOneWidget);
            Navigator.of(t.element(find.byType(ExperimentsView))).pop();
            await t.pumpAndSettle();
            expect(find.byType(RoutineScreen), findsOneWidget);
            Navigator.of(t.element(find.byType(RoutineScreen))).pop();
            await t.pumpAndSettle();
            expect(find.byType(ProductFeatureDetailScreen), findsOneWidget);
            expect(
              f.requests
                  .where(
                    (r) => r.method == 'POST' && !r.url.path.contains('/auth/'),
                  )
                  .length,
              1,
            );
            expect(t.takeException(), isNull);
            await f.done(t);
          });
        },
      );
    }
  }
  for (final scenario in [
    'failed report',
    'missing product',
    'missing experiment',
    'switch reused token',
    'consent revoked',
  ]) {
    testWidgets('integrated $scenario stays honest', (t) async {
      final f = Journey();
      await f.run(() async {
        await f.login();
        await mount(t, RoutineScreen(state: f.state));
        if (scenario == 'failed report') {
          f.failReport = true;
          await reveal(t, find.text('AM completed today'));
          await t.tap(find.text('AM completed today'));
          await t.pumpAndSettle();
          expect(f.reports, isEmpty);
          expect(find.text('Saved on server'), findsNothing);
        }
        if (scenario == 'missing product') {
          f.missingProduct = true;
          await reveal(t, find.text('View associated product'));
          await t.tap(find.text('View associated product'));
          await t.pumpAndSettle();
          expect(find.byType(ProductFeatureDetailScreen), findsNothing);
          expect(
            find.textContaining('Associated product unavailable'),
            findsOneWidget,
          );
        }
        if (scenario == 'missing experiment') {
          f.missingExperiment = true;
          await reveal(t, find.text('Related experiments'));
          await t.tap(find.text('Related experiments'));
          await t.pumpAndSettle();
          await reveal(
            t,
            find.textContaining('No related experiment in loaded records'),
          );
          expect(
            find.textContaining('No related experiment in loaded records'),
            findsOneWidget,
          );
        }
        if (scenario == 'switch reused token') {
          f.owner = 'b';
          await f.login();
          await t.pumpAndSettle();
          expect(
            find.text('Session ended. Reopen your routine.'),
            findsOneWidget,
          );
          expect(find.text('Inventory · AM · daily'), findsNothing);
        }
        if (scenario == 'consent revoked') {
          f.noConsent = true;
          await ApiService.instance.readSafetyAcceptance();
          await t.pumpAndSettle();
          expect(
            find.text('Session ended. Reopen your routine.'),
            findsOneWidget,
          );
        }
        expect(t.takeException(), isNull);
        await f.done(t);
      });
    });
  }
  testWidgets('old product detail and search clear on account change', (
    t,
  ) async {
    final f = Journey();
    await f.run(() async {
      await f.login();
      await mount(
        t,
        ProductFeatureDetailScreen(state: f.state, productId: 'product'),
      );
      f.owner = 'b';
      await f.login();
      await t.pumpAndSettle();
      expect(find.text('Session ended'), findsOneWidget);
      expect(find.text('Synthetic serum'), findsNothing);
      await mount(t, ProductsSearchScreen(state: f.state));
      await t.enterText(find.byType(SearchBar), 'Private query');
      f.owner = 'c';
      await f.login();
      await t.pumpAndSettle();
      expect(find.text('Private query'), findsNothing);
      expect(find.text('Search cleared. Reopen products.'), findsOneWidget);
      await f.done(t);
    });
  });
  testWidgets('old related experiment view stops after reused-token switch', (
    t,
  ) async {
    final f = Journey();
    await f.run(() async {
      await f.login();
      await f.state.experiments.refresh();
      await mount(
        t,
        Scaffold(
          body: ExperimentsView(
            controller: f.state.experiments,
            state: f.state,
            routineEntryId: 'entry',
          ),
        ),
      );
      f.owner = 'b';
      await f.login();
      await t.pumpAndSettle();
      expect(
        find.text(
          'Session ended. Reopen experiments from your current account.',
        ),
        findsOneWidget,
      );
      expect(find.text('Plan one change'), findsNothing);
      await f.done(t);
    });
  });
  for (final code in [401, 403, 404, 503]) {
    test('old $code cannot invalidate new consented routine session', () async {
      final pending = Completer<http.Response>();
      var delay = false;
      final f = Journey();
      await http.runWithClient(
        () async {
          await f.login();
          final controller = RoutineController(RemoteRoutineRepository());
          await controller.refresh();
          delay = true;
          final old = controller.refresh();
          await Future<void>.delayed(Duration.zero);
          f.owner = 'b';
          await f.login();
          delay = false;
          pending.complete(http.Response('{}', code));
          await old;
          expect(ApiService.instance.observationOwner, 'b');
          expect(ApiService.instance.hasConfirmedSafetyAcceptance, true);
          expect(controller.entries, isNull);
          controller.dispose();
          f.state.dispose();
        },
        () => o.isolated((r) {
          if (delay && r.url.path.endsWith('/routine/entries')) {
            return pending.future;
          }
          return f.transport(r);
        }),
      );
    });
  }
}
