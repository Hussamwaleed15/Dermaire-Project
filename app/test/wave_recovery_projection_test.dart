import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/products/products_ui.dart';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/experiments/experiment_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_product_receipt_test.dart' as product;
import 'wave_routine_receipt_test.dart' as routine;
import 'wave_adherence_receipt_test.dart' as adherence;
import 'wave_experiment_receipt_test.dart' as experiment;
import 'product_authority_test.dart' as p;
import 'home_authority_test.dart' as h;
import 'clinical_status_test.dart' as clinical;

dynamic wireFor(String domain) => switch (domain) {
  'product' => product.Wire(),
  'routine' => routine.RoutineWire(),
  'adherence' => adherence.Wire(),
  _ => experiment.ReceiptWire(),
};
dynamic controllerFor(String domain, Future<void> Function(int) callback) =>
    switch (domain) {
      'product' => ProductsController(
        RemoteProductRepository(),
        onConfirmed: callback,
      ),
      'routine' || 'adherence' => RoutineController(
        RemoteRoutineRepository(),
        onRecoveryConfirmed: callback,
      ),
      _ => ExperimentController(
        RemoteExperimentRepository(),
        onConfirmed: callback,
      ),
    };
Future<void> load(String domain, dynamic c) async {
  if (domain == 'product') {
    await c.load();
  } else {
    await c.refresh();
  }
}

Future<bool> recover(String domain, dynamic c) async => domain == 'product'
    ? (await c.recoverProductOperation()).success as bool
    : domain == 'adherence'
    ? await c.recoverAdherence() as bool
    : await c.recoverConfiguration() as bool;
bool busy(String domain, dynamic c) =>
    domain == 'product' ? c.isSaving as bool : c.saving as bool;
bool hasPending(String domain, dynamic c) => domain == 'product'
    ? c.pendingOperation != null
    : domain == 'adherence'
    ? c.adherencePending != null
    : c.configurationPending != null;
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final domain in ['product', 'routine', 'adherence', 'experiment']) {
    for (final scenario in [
      'unknown',
      'busy callback',
      'logout callback',
      'callback failure',
    ]) {
      test(
        '$domain recovery $scenario preserves projection/session authority',
        () async {
          final dynamic w = wireFor(domain);
          if (scenario == 'unknown') w.loss = 'before';
          var calls = 0;
          final started = Completer<void>(), release = Completer<void>();
          await http.runWithClient(
            () async {
              await p.login();
              final session = ApiService.instance.sessionGeneration;
              final dynamic c = controllerFor(domain, (generation) async {
                expect(generation, session);
                calls++;
                started.complete();
                if (scenario == 'callback failure') {
                  throw StateError('sensitive simulated callback detail');
                }
                await release.future;
              });
              try {
                await load(domain, c);
                expect(await w.submit(c), false);
                final result = recover(domain, c);
                if (scenario == 'unknown') {
                  expect(await result, false);
                  expect(calls, 0);
                  expect(hasPending(domain, c), true);
                } else if (scenario == 'callback failure') {
                  expect(await result, false);
                  expect(calls, 1);
                  expect(hasPending(domain, c), false);
                  final message = domain == 'product'
                      ? c.errorMessage as String
                      : c.error as String;
                  expect(message, contains('confirmed'));
                  expect(message, isNot(contains('sensitive simulated')));
                  expect(busy(domain, c), false);
                } else {
                  await started.future.timeout(const Duration(seconds: 3));
                  expect(busy(domain, c), true);
                  expect(await recover(domain, c), false);
                  expect(await w.submit(c), false);
                  if (scenario == 'logout callback') {
                    await ApiService.instance.init();
                  }
                  release.complete();
                  expect(await result, scenario != 'logout callback');
                  expect(busy(domain, c), false);
                  if (scenario == 'logout callback') {
                    if (domain == 'product') {
                      expect(c.all, isEmpty);
                    } else if (domain == 'experiment') {
                      expect(c.rows, isNull);
                    } else {
                      expect(c.entries, isNull);
                      expect(c.history, isNull);
                    }
                  }
                  expect(calls, 1);
                }
              } finally {
                c.dispose();
              }
            },
            () => MockClient(
              (request) async => await w.call(request) as http.Response,
            ),
          );
        },
      );
    }
  }
  for (final caseName in [
    'product',
    'routine',
    'adherence',
    'experiment',
    'product unavailableHome',
  ]) {
    final domain = caseName.split(' ').first;
    final homeAvailable = !caseName.contains('unavailableHome');
    testWidgets(
      'real $caseName recovery triggers Home and clinical server readback',
      (t) async {
        await t.binding.setSurfaceSize(const Size(800, 1600));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final dynamic w = wireFor(domain);
        final state = DermaireState();
        var homeReads = 0, safetyReads = 0;
        Future<http.Response> call(http.Request request) async {
          expect(request.url.host, 'flutter-tests.invalid');
          final path = request.url.path;
          if (path.endsWith('/home')) {
            homeReads++;
            if (!homeAvailable && homeReads > 1) {
              return http.Response('{}', 503);
            }
            return http.Response(
              jsonEncode({
                ...h.snapshot(),
                'today_checked_in': false,
                'experiment': null,
                'journal': [],
              }),
              200,
            );
          }
          if (path.endsWith('/safety')) {
            safetyReads++;
            return http.Response(
              jsonEncode(clinical.safety(status: 'urgent')),
              200,
            );
          }
          if (path.endsWith('/doctor/review-status')) {
            return http.Response(
              jsonEncode(clinical.review(owner: 'patient-1')),
              200,
            );
          }
          if (path.contains('/auth/') || path.endsWith('/users/me')) {
            return await w.call(request) as http.Response;
          }
          if (domain == 'product' && path.contains('/products')) {
            return await w.call(request) as http.Response;
          }
          if (['routine', 'adherence'].contains(domain) &&
              path.contains('/routine/')) {
            return await w.call(request) as http.Response;
          }
          if (domain == 'experiment' &&
              (path.contains('/experiments') ||
                  path.endsWith('/routine/entries/entry'))) {
            return await w.call(request) as http.Response;
          }
          return http.Response('[]', 200);
        }

        await http.runWithClient(() async {
          await p.login();
          dynamic seed;
          if (domain == 'product') {
            seed = state.productController;
          } else if (domain == 'experiment') {
            seed = state.experiments;
          } else {
            seed = RoutineController(RemoteRoutineRepository());
          }
          await load(domain, seed);
          expect(await w.submit(seed), false);
          if (['routine', 'adherence'].contains(domain)) seed.dispose();
          await state.home.refresh();
          final before = homeReads;
          final Widget body = switch (domain) {
            'product' => ProductsFeatureTab(state: state),
            'routine' || 'adherence' => RoutineScreen(state: state),
            _ => ExperimentsView(
              controller: state.experiments,
              autoLoad: false,
              state: state,
            ),
          };
          await t.pumpWidget(MaterialApp(home: Scaffold(body: body)));
          await t.pumpAndSettle();
          final label = switch (domain) {
            'product' => 'Check original request',
            'routine' => 'Check original routine request',
            'adherence' => 'Check original report',
            _ => 'Check original experiment request',
          };
          await t.ensureVisible(find.text(label));
          final safetyBefore = safetyReads;
          await t.tap(find.text(label));
          await t.pumpAndSettle();
          expect(homeReads, before + 1);
          expect(safetyReads, safetyBefore + 1);
          expect(state.home.available, homeAvailable);
          if (homeAvailable) {
            expect(state.home.current!['today_checked_in'], false);
          } else {
            expect(state.home.current, isNull);
            expect(state.home.error, isNotNull);
            expect(state.productController.pendingOperation, isNull);
          }
          await t.pumpWidget(const SizedBox());
          state.dispose();
          await ApiService.instance.init();
        }, () => MockClient(call));
      },
    );
  }
}
