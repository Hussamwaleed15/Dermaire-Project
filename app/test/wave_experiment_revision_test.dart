import 'package:dermaire_app/experiments/activation_review.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/experiments/experiment_contract.dart';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/experiments/experiment_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'experiment_authority_test.dart' as e;
import 'm4_experiments_test.dart' as m;
import 'product_authority_test.dart' as p;
import 'routine_authority_test.dart' as r;

Map<String, dynamic> experiment([String state = 'draft']) => {
  ...e.experiment(state),
  'revision': 5,
  'revision_protected': true,
};

class Wire {
  Map<String, dynamic> row = experiment();
  Map<String, dynamic> routine = {
    ...r.entry(),
    'revision': 7,
    'revision_protected': true,
  };
  int writes = 0, status = 200;
  bool timeout = false;
  Completer<http.Response>? pending;
  Completer<void> sent = Completer<void>();
  Future<http.Response> call(http.Request request) async {
    expect(request.url.host, 'flutter-tests.invalid');
    final path = request.url.path;
    if (path.endsWith('/auth/login')) return p.auth();
    if (path.endsWith('/users/me')) {
      return http.Response(
        '{"id":"patient-1","role":"patient","safety_accepted":true}',
        200,
      );
    }
    if (path.endsWith('/routine/entries/entry')) {
      return http.Response(jsonEncode(routine), 200);
    }
    if (request.method != 'GET') {
      writes++;
      expect(request.headers['If-Match'], '"5"');
      expect(
        request.headers['Routine-If-Match'],
        path.endsWith('/activate') ? '"7"' : null,
      );
      expect(jsonDecode(request.body), isNot(contains('expected_version')));
      if (!sent.isCompleted) sent.complete();
      if (pending != null) return pending!.future;
      if (timeout) throw TimeoutException('synthetic');
      if (status != 200) return http.Response('{}', status);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (path.endsWith('/activate')) {
        row = experiment('active');
      } else if (path.endsWith('/finish')) {
        row = experiment(body['status'] as String);
      } else if (path.endsWith('/evaluate')) {
        row = {...experiment('active'), 'result': e.evaluation()};
      } else if (request.method == 'DELETE') {
        row = experiment('cancelled');
      } else {
        row = {
          ...row,
          ...body['definition'] as Map<String, dynamic>,
          'notes': body['notes'],
        };
      }
      row['revision'] = 13;
      return http.Response(
        jsonEncode(path.endsWith('/evaluate') ? e.evaluation() : row),
        path.endsWith('/evaluate') ? 201 : 200,
      );
    }
    return http.Response(
      jsonEncode(path.endsWith('/experiments') ? [row] : row),
      200,
    );
  }

  Future<void> run(Future<void> Function(ExperimentController c) body) =>
      http.runWithClient(() async {
        await p.login();
        final c = ExperimentController(RemoteExperimentRepository());
        await c.refresh();
        try {
          await body(c);
        } finally {
          c.dispose();
        }
      }, () => MockClient(call));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final invalid in [null, 0, -1, 2147483648, '5', 5.0]) {
    test('experiment invalid revision $invalid (${invalid.runtimeType})', () {
      expect(
        ExperimentContract.valid(
          experiment()..['revision'] = invalid,
          'patient-1',
        ),
        false,
      );
    });
  }
  for (final field in ['revision', 'revision_protected']) {
    test('experiment partial metadata missing $field fails closed', () {
      expect(
        ExperimentContract.valid(experiment()..remove(field), 'patient-1'),
        false,
      );
    });
  }
  for (final operation in [
    'edit',
    'activate',
    'finish',
    'evaluate',
    'cancel',
  ]) {
    test(
      'protected lifecycle $operation carries original parent revision',
      () async {
        final w = Wire();
        if (['finish', 'evaluate'].contains(operation)) {
          w.row = experiment('active');
        }
        await w.run((c) async {
          final old = Map<String, dynamic>.of(c.rows!.single);
          final path = operation == 'edit' || operation == 'cancel'
              ? 'experiment'
              : 'experiment/$operation';
          final payload = operation == 'edit'
              ? {
                  'definition': {...m.draft(), 'goal': 'New goal'},
                  'notes': null,
                }
              : operation == 'finish'
              ? {'status': 'stopped'}
              : <String, dynamic>{};
          expect(
            await c.write(
              path,
              payload,
              method: operation == 'edit'
                  ? 'PATCH'
                  : operation == 'cancel'
                  ? 'DELETE'
                  : 'POST',
              expected: old,
              expectedRoutine: operation == 'activate'
                  ? Map.of(w.routine)
                  : null,
            ),
            true,
          );
          expect(c.rows!.single['revision'], 13);
          expect(w.writes, 1);
        });
      },
    );
  }
  test(
    'equal definition with changed revision cannot silently rebase',
    () async {
      final w = Wire();
      await w.run((c) async {
        final old = Map<String, dynamic>.of(c.rows!.single);
        w.row = {...w.row, 'revision': 6};
        expect(
          await c.write(
            'experiment/activate',
            {},
            expected: old,
            expectedRoutine: w.routine,
          ),
          false,
        );
        expect(w.writes, 0);
        expect(c.uncertain, isEmpty);
        expect(c.error, contains('reopen the editor'));
      });
    },
  );
  for (final scenario in [
    'missing',
    'changed revision',
    'changed instructions',
    'wrong product',
  ]) {
    test('activation rejects $scenario linked routine before POST', () async {
      final w = Wire();
      await w.run((c) async {
        final reviewed = Map<String, dynamic>.of(w.routine);
        if (scenario == 'changed revision') {
          w.routine = {...w.routine, 'revision': 8};
        }
        if (scenario == 'changed instructions') {
          w.routine = {...w.routine, 'instructions': 'New note'};
        }
        if (scenario == 'wrong product') reviewed['product_id'] = 'other';
        expect(
          await c.write(
            'experiment/activate',
            {},
            expected: c.rows!.single,
            expectedRoutine: scenario == 'missing' ? null : reviewed,
          ),
          false,
        );
        expect(w.writes, 0);
      });
    });
  }
  for (final status in [401, 403, 409, 410, 412, 422, 428, 503]) {
    test('activation $status does not become current success', () async {
      final w = Wire()..status = status;
      await w.run((c) async {
        expect(
          await c.write(
            'experiment/activate',
            {},
            expected: c.rows!.single,
            expectedRoutine: Map.of(w.routine),
          ),
          false,
        );
        expect(w.writes, 1);
        if (status == 401) {
          expect(c.rows, isNull);
        } else {
          expect(c.rows!.single['status'], 'draft');
          expect(c.stale, true);
        }
        if ([409, 410, 412, 422, 428].contains(status)) {
          expect(c.uncertain, isEmpty);
        }
        if (status == 503) expect(c.uncertain, contains('experiment/activate'));
      });
    });
  }
  test('timeout blocks another unkeyed activation after refresh', () async {
    final w = Wire()..timeout = true;
    await w.run((c) async {
      expect(
        await c.write(
          'experiment/activate',
          {},
          expected: c.rows!.single,
          expectedRoutine: Map.of(w.routine),
        ),
        false,
      );
      await c.refresh();
      expect(
        await c.write(
          'experiment/activate',
          {},
          expected: c.rows!.single,
          expectedRoutine: Map.of(w.routine),
        ),
        false,
      );
      expect(w.writes, 1);
    });
  });
  test('late activation after logout cannot restore data', () async {
    final w = Wire()..pending = Completer<http.Response>();
    await w.run((c) async {
      final save = c.write(
        'experiment/activate',
        {},
        expected: c.rows!.single,
        expectedRoutine: Map.of(w.routine),
      );
      await w.sent.future;
      await ApiService.instance.init();
      w.pending!.complete(http.Response(jsonEncode(experiment('active')), 200));
      expect(await save, false);
      expect(c.rows, isNull);
    });
  });
  for (final scenario in [
    'confirmed',
    'declined',
    'changed after review',
    'logout',
    'background',
  ]) {
    testWidgets('actual activation requires reviewed routine: $scenario', (
      t,
    ) async {
      await t.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final w = Wire();
      await http.runWithClient(() async {
        await p.login();
        final c = ExperimentController(RemoteExperimentRepository());
        await c.refresh();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ExperimentsView(controller: c, autoLoad: false),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('Activate today'));
        await t.tap(find.text('Activate today'));
        await t.pumpAndSettle();
        expect(find.text('Review linked routine'), findsOneWidget);
        expect(find.text('Product: Inventory'), findsOneWidget);
        expect(w.writes, 0);
        if (scenario == 'changed after review') {
          w.routine = {...w.routine, 'revision': 8};
        }
        if (scenario == 'logout') {
          await ApiService.instance.init();
          await t.pumpAndSettle();
        }
        if (scenario == 'background') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
          await t.pumpAndSettle();
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await t.pumpAndSettle();
        }
        if (['logout', 'background'].contains(scenario)) {
          expect(find.text('Product: Inventory'), findsNothing);
          expect(find.text('Review expired'), findsOneWidget);
          expect(find.text('Confirm activation'), findsNothing);
          await t.tap(find.text('Close'));
        } else {
          await t.tap(
            find.text(
              scenario == 'declined' ? 'Keep draft' : 'Confirm activation',
            ),
          );
        }
        await t.pumpAndSettle();
        expect(w.writes, scenario == 'confirmed' ? 1 : 0);
        if (scenario == 'logout') {
          expect(c.rows, isNull);
        } else {
          expect(
            c.rows!.single['status'],
            scenario == 'confirmed' ? 'active' : 'draft',
          );
        }
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await ApiService.instance.init();
      }, () => MockClient(w.call));
    });
  }
  for (final dark in [false, true]) {
    testWidgets(
      'activation review readable 320px 200% dark=$dark and expires on cover',
      (t) async {
        await t.binding.setSurfaceSize(const Size(320, 900));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final w = Wire();
        await http.runWithClient(() async {
          await p.login();
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: ExperimentActivationReview(
                generation: ApiService.instance.sessionGeneration,
                entry: w.routine,
                experiment: w.row,
              ),
            ),
          );
          await t.pumpAndSettle();
          expect(find.text('Review linked routine'), findsOneWidget);
          expect(t.takeException(), isNull);
          final nav = t.state<NavigatorState>(find.byType(Navigator));
          nav.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Covered')),
            ),
          );
          await t.pumpAndSettle();
          nav.pop();
          await t.pumpAndSettle();
          expect(find.text('Review expired'), findsOneWidget);
          expect(find.text('Product: Inventory'), findsNothing);
          expect(find.text('Confirm activation'), findsNothing);
          expect(t.takeException(), isNull);
          expect(w.writes, 0);
          await t.pumpWidget(const SizedBox());
          await ApiService.instance.init();
        }, () => MockClient(w.call));
      },
    );
  }
}
