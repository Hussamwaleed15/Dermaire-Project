import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/experiments/experiment_contract.dart';
import 'package:dermaire_app/experiments/experiment_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'experiment_authority_test.dart' as e;
import 'product_authority_test.dart' as p;

Map<String, dynamic> draft() => {
  'routine_entry_id': 'entry',
  'intervention': {'type': 'start_entry', 'schedule': 'AM'},
  'start_date': '2026-10-02',
  'target_days': 28,
  'primary_concern': 'texture',
  'goal': null,
  'notes': null,
};
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final field in [
    'user_id',
    'engine_version',
    'status',
    'product_id',
    'routine_entry_id',
    'target_days',
    'intervention',
    'coverage',
    'start_date',
  ]) {
    test('owned experiment rejects $field', () {
      final row = e.experiment();
      row[field] = field == 'engine_version' ? 99 : null;
      expect(ExperimentContract.valid(row, 'patient-1'), false);
    });
  }
  for (final field in [
    'label',
    'evidence_strength',
    'provenance',
    'observed_change',
    'evaluated_at',
  ]) {
    test('evaluation rejects unsupported $field', () {
      final row = e.evaluation();
      (row['result'] as Map)[field] = 'unsupported';
      expect(ExperimentContract.result(row, 'experiment'), false);
    });
  }
  for (final scenario in [
    'create',
    'activate',
    'finish',
    'evaluate',
    'edit draft',
    'timeout',
    'missing readback',
    'foreign owner',
    'stale definition',
    'late logout',
  ]) {
    test('experiment lifecycle $scenario', () async {
      var row = e.experiment();
      var posts = 0;
      var readFailed = false;
      var delayed = false;
      final pending = Completer<http.Response>();
      await http.runWithClient(
        () async {
          await p.login();
          final c = ExperimentController(RemoteExperimentRepository());
          await c.refresh();
          final original = Map<String, dynamic>.from(row);
          if (scenario == 'foreign owner') {
            row['user_id'] = 'other';
            await c.refresh();
            expect(c.stale, true);
          } else if (scenario == 'late logout') {
            delayed = true;
            final read = c.refresh();
            await Future<void>.delayed(Duration.zero);
            await ApiService.instance.init();
            pending.complete(http.Response(jsonEncode([row]), 200));
            await read;
            expect(c.rows, isNull);
          } else {
            var path = '';
            Map<String, dynamic> payload = draft();
            var method = 'POST';
            if (scenario == 'activate' || scenario == 'stale definition') {
              path = 'experiment/activate';
              payload = {};
            }
            if (scenario == 'stale definition') {
              row['goal'] = 'Changed elsewhere';
            }
            if (scenario == 'finish' || scenario == 'evaluate') {
              row = e.experiment('active');
              await c.refresh();
              original.clear();
              original.addAll(row);
              path =
                  'experiment/${scenario == 'finish' ? 'finish' : 'evaluate'}';
              payload = scenario == 'finish' ? {'status': 'stopped'} : {};
            }
            if (scenario == 'edit draft') {
              path = 'experiment';
              method = 'PATCH';
              payload = {
                'definition': {...draft(), 'goal': 'New question'},
                'notes': null,
              };
            }
            final ok = await c.write(
              path,
              payload,
              method: method,
              expected: path.isEmpty ? null : original,
            );
            expect(
              ok,
              ![
                'timeout',
                'missing readback',
                'stale definition',
              ].contains(scenario),
            );
            if (scenario == 'timeout' || scenario == 'missing readback') {
              await c.refresh();
              expect(await c.write(path, payload), false);
              expect(posts, 1);
            }
            if (scenario == 'stale definition') expect(posts, 0);
            if (scenario == 'evaluate') {
              expect(c.rows!.single['result']['id'], 'evaluation');
            }
          }
          c.dispose();
        },
        () => MockClient((req) async {
          if (req.url.path.endsWith('/auth/login')) return p.auth();
          if (req.url.path.endsWith('/users/me')) {
            return http.Response(
              '{"id":"patient-1","role":"patient","safety_accepted":true}',
              200,
            );
          }
          if (req.method == 'POST' || req.method == 'PATCH') {
            posts++;
            if (scenario == 'timeout') throw TimeoutException('synthetic');
            if (req.url.path.endsWith('/activate')) {
              row = e.experiment('active');
            } else if (req.url.path.endsWith('/finish')) {
              row = e.experiment('stopped');
            } else if (req.url.path.endsWith('/evaluate')) {
              row = e.experiment('active', 'insufficient_evidence');
            } else if (req.method == 'PATCH') {
              row['goal'] = 'New question';
            }
            readFailed = scenario == 'missing readback';
            return http.Response(
              jsonEncode(
                req.url.path.endsWith('/evaluate') ? row['result'] : row,
              ),
              201,
            );
          }
          if (delayed) return pending.future;
          return http.Response(
            jsonEncode(req.url.path.endsWith('/experiments') ? [row] : row),
            readFailed ? 503 : 200,
          );
        }),
      );
    });
  }
  test('unknown unit and null measurements stay unmodified', () {
    final row = e.evaluation();
    row['result']['observed_change'] = {
      'metric': 'texture',
      'baseline_mean': null,
      'experiment_mean': null,
      'delta_points': null,
    };
    expect(ExperimentContract.result(row, 'experiment'), true);
    expect(row['result']['observed_change']['baseline_mean'], isNull);
  });
}
