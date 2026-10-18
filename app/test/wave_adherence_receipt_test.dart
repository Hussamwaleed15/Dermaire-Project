import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/routine/routine_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_authority_test.dart' as p;
import 'routine_authority_test.dart' as r;
import 'm4_adherence_test.dart' as a;
import 'wave_product_receipt_test.dart' as products;
import 'wave_routine_receipt_test.dart' as configs;
import 'wave_experiment_receipt_test.dart' as experiments;
import 'package:dermaire_app/products/product_repository.dart';
import 'package:dermaire_app/products/products_controller.dart';
import 'package:dermaire_app/experiments/experiment_controller.dart';

class Wire {
  Map<String, dynamic>? original;
  List<Map<String, dynamic>> reports = [];
  Map<String, dynamic> configuration = {
    ...r.entry(),
    'revision': 7,
    'revision_protected': true,
  };
  String? key, body;
  bool lose = true;
  String loss = 'after', reportDate = '2026-10-03';
  int posts = 0, lookupStatus = 200, mutationStatus = 201;
  Map<String, dynamic> Function(Map<String, dynamic>)? change;
  Completer<http.Response>? delayed;
  final lookupSent = Completer<void>();
  Map<String, dynamic> lookup() => original == null
      ? {
          'schema_version': 1,
          'operation': 'routine_adherence',
          'attempt_id': 'report-id',
          'owner_id': 'patient-1',
          'actor_id': 'patient-1',
          'status': 'unknown',
          'result': null,
        }
      : {...original!['receipt'] as Map<String, dynamic>, 'result': original};
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
    if (path.contains('/adherence/attempts/')) {
      expect(request.method, 'GET');
      expect(path.endsWith('/$key'), true);
      if (!lookupSent.isCompleted) lookupSent.complete();
      if (delayed != null) return delayed!.future;
      final value = lookup();
      return http.Response(
        jsonEncode(change?.call(value) ?? value),
        lookupStatus,
      );
    }
    if (request.method == 'POST') {
      posts++;
      expect(request.headers['If-Match'], isNull);
      expect(request.headers['Routine-If-Match'], isNull);
      expect(
        request.headers['Idempotency-Key'],
        matches(RegExp(r'^[A-Za-z0-9_-]{16,128}$')),
      );
      if (key == null) {
        key = request.headers['Idempotency-Key'];
        body = request.body;
      } else {
        expect(request.headers['Idempotency-Key'], key);
        expect(request.body, body);
      }
      if (mutationStatus != 201) return http.Response('{}', mutationStatus);
      if (loss == 'before' && lose) throw TimeoutException('synthetic');
      if (original == null) {
        original = {
          ...a.keyedEvent(id: 'report-id'),
          ...jsonDecode(request.body) as Map<String, dynamic>,
          'configuration_snapshot': Map.of(configuration),
          'receipt': {
            ...a.keyedEvent(id: 'report-id')['receipt'] as Map<String, dynamic>,
            'configuration_revision': configuration['revision'],
          },
        };
        reports = [...reports, original!];
        reports.sort(
          (a, b) => (b['date'] as String).compareTo(a['date'] as String),
        );
      }
      if (lose) throw TimeoutException('synthetic');
      return http.Response(jsonEncode(original), 201);
    }
    final offset =
        int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '100') ?? 100;
    return http.Response(
      jsonEncode(
        path.endsWith('/entries')
            ? [configuration]
            : reports.skip(offset).take(limit).toList(),
      ),
      200,
    );
  }

  Future<void> run(Future<void> Function(RoutineController c) body) =>
      http.runWithClient(() async {
        await p.login();
        final c = RoutineController(RemoteRoutineRepository());
        await c.refresh();
        try {
          await body(c);
        } finally {
          c.dispose();
        }
      }, () => MockClient(call));
  Future<bool> submit(RoutineController c) => c.write('adherence', {
    'routine_entry_id': 'entry',
    'date': reportDate,
    'slot': 'AM',
    'status': 'completed',
    'note': 'Original synthetic note',
  });
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final loss in ['before', 'after']) {
    test(
      'adherence $loss loss preserves original key and frozen configuration',
      () async {
        final w = Wire()..loss = loss;
        await w.run((c) async {
          expect(await w.submit(c), false);
          expect(c.adherencePending, isNotNull);
          await c.refresh();
          expect(await w.submit(c), false);
          expect(w.posts, 1);
          if (loss == 'before') {
            expect(await c.recoverAdherence(), false);
            w.lose = false;
          }
          expect(await c.recoverAdherence(retryOriginal: true), true);
          expect(c.adherencePending, isNull);
          expect(c.history!.single['id'], 'report-id');
          expect(c.history!.single['configuration_snapshot']['revision'], 7);
          expect(w.posts, loss == 'before' ? 2 : 1);
        });
      },
    );
  }
  test('new configuration does not rewrite original report snapshot', () async {
    final w = Wire();
    await w.run((c) async {
      expect(await w.submit(c), false);
      w.configuration = {
        ...w.configuration,
        'revision': 19,
        'schedule': 'BOTH',
      };
      expect(await c.recoverAdherence(), true);
      expect(c.entries!.single['revision'], 19);
      expect(c.history!.single['configuration_snapshot']['revision'], 7);
      expect(c.history!.single['configuration_snapshot']['schedule'], 'AM');
      expect(w.posts, 1);
    });
  });
  test(
    'occupied slot409 and unrelated report never confirm original key',
    () async {
      final w = Wire()..mutationStatus = 409;
      await w.run((c) async {
        expect(await w.submit(c), false);
        w.reports = [a.keyedEvent(id: 'unrelated')];
        await c.refresh();
        expect(await c.recoverAdherence(), false);
        expect(c.adherencePending!.lookupStatus, 'unknown');
        expect(await c.recoverAdherence(finishExpiredReview: true), false);
        expect(await w.submit(c), false);
        expect(w.posts, 1);
      });
    },
  );
  for (final scenario in [
    'actor',
    'slot',
    'date',
    'note',
    'report id',
    'configuration revision',
    'created time',
    'nested receipt',
    'unknown with result',
  ]) {
    test('adherence rejects contradictory receipt $scenario', () async {
      final w = Wire()
        ..change = (v) {
          if (scenario == 'actor') v['actor_id'] = 'other';
          if (scenario == 'report id') v['resource_id'] = 'other';
          if (scenario == 'configuration revision') {
            v['configuration_revision'] = 9;
          }
          if (scenario == 'unknown with result') v['status'] = 'unknown';
          if ([
            'slot',
            'date',
            'note',
            'created time',
            'nested receipt',
          ].contains(scenario)) {
            final record = Map<String, dynamic>.of(
              v['result'] as Map<String, dynamic>,
            );
            if (scenario == 'slot') record['slot'] = 'PM';
            if (scenario == 'date') record['date'] = '2026-10-04';
            if (scenario == 'note') record['note'] = 'Other';
            if (scenario == 'created time') {
              record['created_at'] = '2026-10-04T12:00:00Z';
            }
            if (scenario == 'nested receipt') {
              record['receipt'] = {
                ...record['receipt'] as Map<String, dynamic>,
                'owner_id': 'other',
              };
            }
            v['result'] = record;
          }
          return v;
        };
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(await c.recoverAdherence(retryOriginal: true), false);
        expect(c.adherencePending, isNotNull);
        expect(w.posts, 1);
      });
    });
  }
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    test('adherence lookup$status never replays or claims recorded', () async {
      final w = Wire()..lookupStatus = status;
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(await c.recoverAdherence(retryOriginal: true), false);
        expect(w.posts, 1);
        if (status == 401) {
          expect(c.history, isNull);
          expect(c.adherencePending, isNull);
        } else {
          expect(c.adherencePending, isNotNull);
        }
      });
    });
  }
  test(
    'expired adherence receipt requires explicit history review without replay',
    () async {
      final w = Wire()
        ..change = (v) => {...v, 'status': 'expired', 'result': null};
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(await c.recoverAdherence(retryOriginal: true), false);
        expect(c.adherencePending, isNotNull);
        expect(await c.recoverAdherence(finishExpiredReview: true), true);
        expect(w.posts, 1);
        expect(c.error, contains('No report was repeated'));
      });
    },
  );
  test(
    'late report lookup after session reset cannot restore history',
    () async {
      final w = Wire()..delayed = Completer<http.Response>();
      await w.run((c) async {
        expect(await w.submit(c), false);
        final recovery = c.recoverAdherence();
        await w.lookupSent.future;
        await ApiService.instance.init();
        w.delayed!.complete(http.Response(jsonEncode(w.lookup()), 200));
        expect(await recovery, false);
        expect(c.history, isNull);
        expect(c.adherencePending, isNull);
      });
    },
  );
  testWidgets('real routine report recovery shows server-confirmed history', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final w = Wire();
    await http.runWithClient(() async {
      await p.login();
      final c = RoutineController(RemoteRoutineRepository());
      await c.refresh();
      expect(await w.submit(c), false);
      c.dispose();
      await t.pumpWidget(const MaterialApp(home: RoutineScreen()));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Check original report'));
      await t.tap(find.text('Check original report'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Original adherence report confirmed'),
        findsOneWidget,
      );
      expect(w.posts, 1);
      await t.pumpWidget(const SizedBox());
      await ApiService.instance.init();
    }, () => MockClient(w.call));
  });
  test(
    'fresh product controller can resolve creation and original controller unlocks on confirmed refresh',
    () async {
      final w = products.Wire()..kind = 'create';
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(c.createUncertain, true);
        final other = ProductsController(RemoteProductRepository());
        await other.load();
        expect((await other.recoverProductOperation()).success, true);
        other.dispose();
        await c.load();
        expect(c.createUncertain, false);
        expect(c.pendingOperation, isNull);
      });
    },
  );
  test(
    'resolved routine request does not leave another controller with an orphan lock',
    () async {
      final w = configs.RoutineWire();
      await w.run((c) async {
        expect(await w.submit(c), false);
        final other = RoutineController(RemoteRoutineRepository());
        await other.refresh();
        expect(await other.recoverConfiguration(), true);
        other.dispose();
        await c.refresh();
        expect(c.configurationPending, isNull);
        expect(c.uncertain, isEmpty);
      });
    },
  );
  test(
    'resolved experiment request unlocks another controller only after a fresh read',
    () async {
      final w = experiments.ReceiptWire();
      await w.run((c) async {
        expect(await w.submit(c), false);
        final other = ExperimentController(RemoteExperimentRepository());
        await other.refresh();
        expect(await other.recoverConfiguration(), true);
        other.dispose();
        await c.refresh();
        expect(c.configurationPending, isNull);
        expect(c.uncertain, isEmpty);
      });
    },
  );
  test(
    'immutable original outside newest100 resolves without inserting historical data',
    () async {
      final w = Wire()..reportDate = '2026-01-01';
      w.configuration = {
        ...w.configuration,
        'start_date': '2025-12-01',
        'created_at': '2025-12-01T10:00:00',
        'updated_at': '2025-12-01T10:00:00',
      };
      w.reports = List.generate(
        100,
        (i) => {
          ...a.keyedEvent(id: 'other-$i'),
          'date': DateTime.utc(
            2026,
            1,
            2,
          ).add(Duration(days: 99 - i)).toIso8601String().substring(0, 10),
          'configuration_snapshot': Map.of(w.configuration),
          'receipt': {
            ...a.keyedEvent(id: 'other-$i')['receipt'] as Map<String, dynamic>,
            'configuration_revision': 7,
          },
        },
      );
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(await c.recoverAdherence(), true);
        expect(c.history!.length, 100);
        expect(c.history!.any((r) => r['id'] == 'report-id'), false);
        expect(c.historyHasMore, true);
        expect(w.posts, 1);
      });
    },
  );
  test(
    'definite first report422 permits a separately reviewed report',
    () async {
      final w = Wire()
        ..lose = false
        ..mutationStatus = 422;
      await w.run((c) async {
        expect(await w.submit(c), false);
        expect(c.adherencePending, isNull);
        expect(c.uncertain, isEmpty);
        final rejected = w.key;
        await c.refresh();
        w.key = null;
        w.mutationStatus = 201;
        expect(
          await c.write('adherence', {
            'routine_entry_id': 'entry',
            'date': '2026-10-03',
            'slot': 'AM',
            'status': 'completed',
            'note': 'Reviewed replacement',
          }),
          true,
        );
        expect(w.key, isNot(rejected));
        expect(w.posts, 2);
      });
    },
  );
}
