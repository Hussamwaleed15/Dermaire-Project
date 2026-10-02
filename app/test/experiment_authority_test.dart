import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/experiments/experiment_ui.dart';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> evaluation([String label = 'insufficient_evidence']) => {
  'id': 'evaluation',
  'experiment_id': 'experiment',
  'result': {
    'label': label,
    'evidence_summary': 'Server evidence only. Association is not causality.',
    'provenance': {'source': 'server_derived'},
    'limitations': ['No clinical conclusion.'],
    'evidence_strength': 'limited',
    'coverage': {},
    'evaluated_at': '2026-10-02T12:00:00',
  },
};
Map<String, dynamic> experiment([String status = 'draft', String? label]) => {
  'id': 'experiment',
  'engine_version': 2,
  'source': 'user_configured',
  'created_at': '2026-10-02T12:00:00',
  'status': status,
  'target_days': 28,
  'start_date': '2026-10-02T00:00:00',
  'routine_entry_id': 'entry',
  'intervention': {'type': 'start_entry', 'schedule': 'AM'},
  'goal': null,
  'notes': null,
  'coverage': {
    'elapsed_days': 7,
    'observed_days': 5,
    'adherence_coverage': .8,
    'context_coverage': .7,
  },
  'result': label == null ? null : evaluation(label),
};

class Repository implements ExperimentRepository {
  List<Map<String, dynamic>> rows = [];
  bool fail = false;
  bool fake = false;
  Completer<List<Map<String, dynamic>>>? pending;
  Completer<Map<String, dynamic>>? pendingWrite;
  @override
  Future<List<Map<String, dynamic>>> read() async {
    if (pending != null) return pending!.future;
    if (fail) throw Exception('offline');
    return rows;
  }

  @override
  Future<Map<String, dynamic>> write(
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (pendingWrite != null) return pendingWrite!.future;
    if (fail) throw Exception('offline');
    if (fake) return {'success': true};
    if (path.endsWith('/evaluate')) {
      rows = [experiment('active', 'insufficient_evidence')];
      return evaluation();
    }
    final row = experiment(
      path.endsWith('/activate') ? 'active' : payload['status'] ?? 'draft',
    );
    if (path.isEmpty) row.addAll(payload);
    rows = [row];
    return row;
  }
}

void main() {
  test('writes require server confirmation and persistent readback', () async {
    final repo = Repository();
    final c = ExperimentController(repo);
    final payload = {
      'routine_entry_id': 'entry',
      'intervention': {'type': 'start_entry', 'schedule': 'AM'},
    };
    expect(await c.write('', payload), true);
    expect(c.rows!.single['status'], 'draft');
    expect(await c.write('experiment/activate', {}), true);
    expect(c.rows!.single['status'], 'active');
    expect(await c.write('experiment/evaluate', {}), true);
    expect(c.rows!.single['result']['id'], 'evaluation');
    expect(await c.write('experiment/finish', {'status': 'stopped'}), true);
    expect(c.rows!.single['status'], 'stopped');
    c.dispose();
  });
  test('fake write confirmation never creates experiment state', () async {
    final c = ExperimentController(Repository()..fake = true);
    expect(await c.write('', {}), false);
    expect(c.rows, null);
    expect(c.error, contains('unconfirmed'));
    c.dispose();
  });
  test('wrong target confirmation is rejected', () async {
    final c = ExperimentController(Repository());
    expect(await c.write('other/activate', {}), false);
    expect(c.rows, null);
    c.dispose();
  });
  test('server success without readback is unconfirmed', () async {
    final repo = Repository()..pendingWrite = Completer();
    final c = ExperimentController(repo);
    final operation = c.write('experiment/activate', {});
    repo.pendingWrite!.complete(experiment('active'));
    expect(await operation, false);
    expect(c.error, contains('unconfirmed'));
    c.dispose();
  });
  test('failed refresh removes stale experiments', () async {
    final repo = Repository()..rows = [experiment('active')];
    final c = ExperimentController(repo);
    expect(await c.refresh(), true);
    repo.fail = true;
    expect(await c.refresh(), false);
    expect(c.rows, null);
    c.dispose();
  });
  test('malformed response is not canonical state', () async {
    final c = ExperimentController(
      Repository()
        ..rows = [
          {'success': true},
        ],
    );
    expect(await c.refresh(), false);
    expect(c.rows, null);
    c.dispose();
  });
  test('logout invalidates pending reads', () async {
    final repo = Repository()..pending = Completer();
    final c = ExperimentController(repo);
    final operation = c.refresh();
    c.clear();
    repo.pending!.complete([experiment('active')]);
    expect(await operation, false);
    expect(c.rows, null);
    c.dispose();
  });
  test(
    'logout invalidates pending failed writes without error resurrection',
    () async {
      final repo = Repository()..pendingWrite = Completer();
      final c = ExperimentController(repo);
      final operation = c.write('experiment/activate', {});
      c.clear();
      repo.pendingWrite!.completeError(Exception('offline'));
      expect(await operation, false);
      expect(c.rows, null);
      expect(c.error, null);
      c.dispose();
    },
  );
  test('logout during post-write refresh suppresses success', () async {
    final repo = Repository()..pendingWrite = Completer();
    final c = ExperimentController(repo);
    final operation = c.write('experiment/activate', {});
    repo.pending = Completer();
    repo.pendingWrite!.complete(experiment('active'));
    await Future<void>.delayed(Duration.zero);
    c.clear();
    repo.pending!.complete([experiment('active')]);
    expect(await operation, false);
    expect(c.rows, null);
    c.dispose();
  });
  test('account lifecycle clears experiment controller', () async {
    final state = DermaireState(
      experimentRepository: Repository()..rows = [experiment('active')],
    );
    await state.experiments.refresh();
    state.clearAccountData();
    expect(state.experiments.rows, null);
    state.dispose();
  });
  test(
    'remote transport uses experiment endpoints and rejects HTTP failures',
    () async {
      var status = 200;
      await http.runWithClient(
        () async {
          final repo = RemoteExperimentRepository();
          expect((await repo.read()).single['id'], 'experiment');
          for (final code in [401, 403, 409, 422, 500, 503]) {
            status = code;
            await expectLater(repo.read(), throwsException);
          }
        },
        () => MockClient((request) async {
          expect(request.url.path, '/api/v1/experiments');
          return http.Response(jsonEncode([experiment()]), status);
        }),
      );
    },
  );
  for (final state in [
    'draft',
    'active',
    'stopped',
    'cancelled',
    'completed',
  ]) {
    testWidgets('shows server $state state', (tester) async {
      final c = ExperimentController(Repository()..rows = [experiment(state)]);
      await c.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExperimentsView(controller: c, autoLoad: false)),
        ),
      );
      expect(find.text('Status: $state'), findsOneWidget);
      expect(find.textContaining('Complete days: 7'), findsOneWidget);
      expect(
        find.text('Activate today'),
        state == 'draft' ? findsOneWidget : findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  for (final label in [
    'insufficient_evidence',
    'likely_associated_improvement',
    'confounded_or_low_adherence',
  ]) {
    testWidgets('shows server $label result', (tester) async {
      final c = ExperimentController(
        Repository()..rows = [experiment('active', label)],
      );
      await c.refresh();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ExperimentsView(controller: c, autoLoad: false)),
        ),
      );
      expect(find.text(label.replaceAll('_', ' ')), findsOneWidget);
      expect(
        find.text('Server evidence only. Association is not causality.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }
  testWidgets('empty loading and failure remain distinct', (tester) async {
    final repo = Repository();
    final c = ExperimentController(repo);
    await c.refresh();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ExperimentsView(controller: c, autoLoad: false)),
      ),
    );
    expect(find.text('No experiments yet.'), findsOneWidget);
    repo.pending = Completer();
    final pending = c.refresh();
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('No experiments yet.'), findsNothing);
    repo.pending!.completeError(Exception('offline'));
    await pending;
    await tester.pump();
    expect(find.byKey(const Key('experimentError')), findsOneWidget);
    expect(find.text('No experiments yet.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
