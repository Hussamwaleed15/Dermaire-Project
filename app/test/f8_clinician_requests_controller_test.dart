import 'dart:async';
import 'package:dermaire_app/agent/server_agent_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;
import 'wave_agent_test.dart' as fixture;

class RequestPages extends fixture.AgentWire {
  RequestPages() : super(doctor: true);
  final reads = <http.Request>[];
  final gate = <Completer<http.Response>>[];
  bool hold = false;
  int status = 200;
  late List<Map<String, dynamic>> first = [requestRow('z', 3), requestRow('y', 2)];
  late List<Map<String, dynamic>> second = [requestRow('x', 2), requestRow('w', 1)];

  Map<String, dynamic> requestRow(String id, int minute) {
    final at = DateTime.utc(2026, 11, 1, 0, minute);
    return {
      ...action(id, {
        'kind': 'propose_followup',
        'rationale': 'Synthetic review',
      }),
      'state': 'confirmed',
      'revision': 2,
      'requires_explicit_confirmation': false,
      'previewed_at': at.toIso8601String(),
      'preview_valid_until': at
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'confirmed_at': at.toIso8601String(),
      'result': {
        'request_id': id,
        'clinical_clearance': false,
        'medical_resources_modified': false,
        'clinician_notified': false,
        'notification_enqueued': false,
        'provenance': 'user_confirmed_request',
        'status': 'pending_clinician_review',
        'access_id': 'grant-1',
        'doctor_id': 'doctor-1',
        'consent_version': 1,
        'submitted_at': at.toIso8601String(),
        'expires_at': expires.toIso8601String(),
      },
    };
  }

  http.Response page(bool subsequent) => f.json({
    'items': subsequent ? second : first,
    'limit': 100,
    'next_before': subsequent ? null : 'cursor-1',
    'medical_execution_enabled': false,
    'notification_delivery': 'unavailable',
  }, status);

  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    if (r.url.path.endsWith('/agent/requests')) {
      expect(r.method, 'GET');
      reads.add(r);
      if (hold) {
        final c = Completer<http.Response>();
        gate.add(c);
        return c.future;
      }
      return page(r.url.queryParameters.containsKey('before'));
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

  Future<void> exercise(
    Future<void> Function(RequestPages, ClinicianRequestsController) body,
  ) async {
    final wire = RequestPages();
    await wire.run(() async {
      await wire.login();
      final controller = ClinicianRequestsController();
      try {
        await body(wire, controller);
      } finally {
        if (!controller.disposed) controller.dispose();
      }
    });
  }

  test(
    'controller appends two nonempty pages with boundary ties and busy transitions',
    () => exercise((w, c) async {
      final busy = <bool>[];
      c.addListener(() => busy.add(c.busy));
      w.hold = true;
      final initial = c.refresh();
      expect(c.busy, isTrue);
      expect(c.requests, isEmpty);
      await Future<void>.delayed(Duration.zero);
      await c.more(); // Busy guard must not issue another read.
      expect(w.reads.length, 1);
      w.gate.removeAt(0).complete(w.page(false));
      await initial;
      expect(c.requests.map((r) => r.id), ['z', 'y']);
      expect(c.next, 'cursor-1');
      expect(c.busy, isFalse);
      final subsequent = c.more();
      expect(c.busy, isTrue);
      expect(c.requests.map((r) => r.id), ['z', 'y']);
      await Future<void>.delayed(Duration.zero);
      w.gate.removeAt(0).complete(w.page(true));
      await subsequent;
      expect(c.requests.map((r) => r.id), ['z', 'y', 'x', 'w']);
      expect(c.requests[1].previewed, c.requests[2].previewed);
      expect(c.next, isNull);
      expect(c.error, isNull);
      expect(busy, [true, false, true, false]);
      expect(w.reads.map((r) => r.url.queryParameters), [
        {'limit': '100'},
        {'limit': '100', 'before': 'cursor-1'},
      ]);
      await c.more();
      expect(w.reads.length, 2);
    }),
  );

  for (final mode in [
    'missing timestamp',
    'invalid timestamp',
    'ascending time',
    'duplicate id',
    'equal tuple',
    'ascending tie',
  ]) {
    test(
      'controller rejects $mode across pagination and clears private rows',
      () => exercise((w, c) async {
        await c.refresh();
        expect(c.requests.length, 2);
        switch (mode) {
          case 'missing timestamp':
            w.second.first.remove('previewed_at');
          case 'invalid timestamp':
            w.second.first['previewed_at'] = 'invalid';
          case 'ascending time':
            w.second = [w.requestRow('x', 4), w.requestRow('w', 1)];
          case 'duplicate id':
            w.second = [w.requestRow('y', 1), w.requestRow('w', 0)];
          case 'equal tuple':
            w.second = [w.requestRow('y', 2), w.requestRow('w', 1)];
          case 'ascending tie':
            w.second = [w.requestRow('z2', 2), w.requestRow('w', 1)];
        }
        await c.more();
        expect(c.requests, isEmpty);
        expect(c.next, isNull);
        expect(c.error, isNotNull);
        expect(c.busy, isFalse);
        w.second = [w.requestRow('x', 2), w.requestRow('w', 1)];
        await c.refresh();
        await c.more();
        expect(c.requests.map((r) => r.id), ['z', 'y', 'x', 'w']);
        expect(c.error, isNull);
      }),
    );
  }

  for (final subsequent in [false, true]) {
    test(
      'controller recovers from ${subsequent ? 'pagination' : 'initial'} API failure',
      () => exercise((w, c) async {
        if (subsequent) await c.refresh();
        w.status = 503;
        await (subsequent ? c.more() : c.refresh());
        expect(c.busy, isFalse);
        expect(c.requests, isEmpty);
        expect(c.next, isNull);
        expect(c.error, isNotNull);
        w.status = 200;
        await c.refresh();
        await c.more();
        expect(c.requests.length, 4);
        expect(c.error, isNull);
      }),
    );
  }

  for (final isolation in ['hide', 'session change', 'dispose']) {
    test(
      'controller $isolation wipes rows and rejects late page',
      () => exercise((w, c) async {
        await c.refresh();
        w.hold = true;
        final pending = c.more();
        await Future<void>.delayed(Duration.zero);
        if (isolation == 'hide') c.hide();
        if (isolation == 'session change') await api.init();
        if (isolation == 'dispose') c.dispose();
        expect(c.requests, isEmpty);
        expect(c.next, isNull);
        w.gate.removeAt(0).complete(w.page(true));
        await pending;
        expect(c.requests, isEmpty);
        expect(c.next, isNull);
        if (isolation != 'dispose') expect(c.busy, isFalse);
        w.hold = false;
        if (isolation == 'hide') {
          await c.show();
          expect(c.requests.map((r) => r.id), ['z', 'y']);
        }
        // exercise owns disposal; avoid a second ChangeNotifier disposal.
        if (isolation == 'dispose') return;
      }),
    );
  }
}
