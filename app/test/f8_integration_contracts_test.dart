import 'dart:async';
import 'package:dermaire_app/agent/agent_discovery.dart';
import 'package:dermaire_app/notifications/inbox_controller.dart';
import 'package:dermaire_app/notifications/inbox_models.dart';
import 'package:dermaire_app/plans/plan_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;
import 'wave_inbox_test.dart' as inbox;
import 'wave_comparison_test.dart' as comparison;

class DiscoveryWire extends f.DoctorWire {
  DiscoveryWire() {
    owner = 'patient-1';
    role = 'patient';
  }
  int pages = 0;
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    if (r.url.path.endsWith('/agent/sessions')) {
      pages++;
      final more = r.url.queryParameters['before'] != null;
      expect(r.url.queryParameters['limit'], '20');
      return f.json({
        'limit': 20,
        'context_included': false,
        'turns_included': false,
        'next_before': more ? null : 'session-2',
        'items': [
          {
            'id': more ? 'session-1' : 'session-2',
            'revision': 1,
            'expires_at': '2099-01-01T00:00:00Z',
            'context_at': '2026-11-01T00:00:00Z',
            'scopes': ['longitudinal_read'],
            'tool_calls': 0,
            'max_tool_calls': 8,
            'model_status': 'unavailable',
            'medical_execution_enabled': false,
          },
        ],
      });
    }
    return super.call(r);
  }
}

class CasWire extends inbox.InboxWire {
  bool conflict = false;
  int mutations = 0;
  @override
  Future<http.Response> call(http.Request r) async {
    if (r.method == 'PUT' && r.url.path.endsWith('/read')) {
      mutations++;
      expect(r.url.queryParameters['expected_revision'], '1');
      if (conflict) {
        notices.first['state_revision'] = 2;
        return f.json({}, 412);
      }
    }
    return super.call(r);
  }
}

class CancelWire extends comparison.ComparisonWire {
  CancelWire() {
    plan = {
      ...plan,
      'state': 'captured',
      'revision': 4,
      'followup_capture_id': 'followup-1',
    };
    job = evaluation();
  }
  bool lose = false;
  int? cancelStatus;
  Completer<http.Response>? hold;
  String state = 'committed';
  final keys = <String>[];
  Map<String, dynamic>? receipt;
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    if (r.method == 'DELETE' && r.url.path.endsWith('/evaluation')) {
      keys.add(r.headers['Idempotency-Key']!);
      if (cancelStatus != null) return f.json({}, cancelStatus!);
      expect(r.url.queryParameters['expected_revision'], '4');
      receipt = evaluation(state: 'cancelled');
      job = receipt;
      if (hold != null) return hold!.future;
      if (lose) throw TimeoutException('synthetic lost response');
      return f.json(receipt);
    }
    if (r.url.path.contains('/attempts/evaluation_cancel/')) {
      expect(r.url.path.split('/').last, keys.single);
      return f.json({
        'attempt_id': 'attempt-1',
        'status': state,
        'result': state == 'committed' ? receipt : null,
      });
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
  test(
    'F8-3 discovered pages are bounded, session scoped and clear on logout',
    () async {
      final w = DiscoveryWire();
      await w.run(() async {
        await w.login();
        final c = AgentDiscovery();
        await c.refresh();
        expect(c.rows.single.id, 'session-2');
        await c.load(more: true);
        expect(c.rows.map((r) => r.id), ['session-2', 'session-1']);
        expect(c.next, isNull);
        await api.logout();
        expect(c.rows, isEmpty);
        c.dispose();
      });
    },
  );
  for (final conflict in [false, true]) {
    test(
      'F8-4 CAS sends original revision and never replays conflict=$conflict',
      () async {
        final w = CasWire()..conflict = conflict;
        await w.run(() async {
          await w.login();
          final c = InboxController();
          await c.refresh();
          expect(await c.mark(c.notices.first, read: true), !conflict);
          expect(w.mutations, 1);
          expect(c.notices.first.stateRevision, 2);
          c.dispose();
        });
      },
    );
  }
  for (final state in ['committed', 'unknown', 'expired']) {
    test('F8-5 lost cancel receipt $state never repeats mutation', () async {
      final w = CancelWire()
        ..lose = true
        ..state = state;
      await w.run(() async {
        await w.login();
        final c = PlanController('plan-1');
        await c.refresh();
        await c.cancelEvaluation();
        final original = c.cancellation!;
        await c.refresh();
        await c.cancelEvaluation();
        expect(w.keys, [original.key]);
        await c.reconcileCancellation();
        expect(c.cancellation == null, state == 'committed');
        expect(w.keys, [original.key]);
        c.dispose();
      });
    });
  }
  test('F8-4 missing revision blocks mutation', () async {
    final w = CasWire();
    w.notices.first.remove('state_revision');
    await w.run(() async {
      await w.login();
      final c = InboxController();
      await c.refresh();
      expect(await c.mark(c.notices.first, read: true), false);
      expect(w.mutations, 0);
      c.dispose();
    });
  });
  test('F8-4 uses only authorized conversation target, never source id', () {
    final base = inbox.InboxWire().notices.last;
    final valid = InboxNotice({
      ...base,
      'target': {
        'type': 'conversation',
        'thread_id': 'thread-1',
        'message_id': 'message-1',
        'authority': 'current_server_authorized',
      },
    });
    expect(valid.threadId, 'thread-1');
    expect(valid.source, 'message-1');
    expect(
      InboxNotice({
        ...base,
        'target': {
          'type': 'conversation',
          'thread_id': 'foreign',
          'message_id': 'other',
          'authority': 'current_server_authorized',
        },
      }).threadId,
      isNull,
    );
  });
  for (final status in [403, 404, 409, 410, 412, 503]) {
    test(
      'F8-5 HTTP $status keeps original cancellation and never auto retries',
      () async {
        final w = CancelWire()..cancelStatus = status;
        await w.run(() async {
          await w.login();
          final c = PlanController('plan-1');
          await c.refresh();
          await c.cancelEvaluation();
          final key = c.cancellation!.key;
          await c.refresh();
          await c.cancelEvaluation();
          expect(w.keys, [key]);
          c.dispose();
        });
      },
    );
  }
  test('F8-5 logout fences late cancellation response', () async {
    final w = CancelWire()..hold = Completer<http.Response>();
    await w.run(() async {
      await w.login();
      final c = PlanController('plan-1');
      await c.refresh();
      final request = c.cancelEvaluation();
      await Future<void>.delayed(Duration.zero);
      expect(w.keys, hasLength(1));
      await api.logout();
      w.hold!.complete(f.json(w.receipt));
      await request;
      expect(c.value, isNull);
      expect(c.evaluation, isNull);
      expect(c.cancellation, isNull);
      c.dispose();
    });
  });
}
