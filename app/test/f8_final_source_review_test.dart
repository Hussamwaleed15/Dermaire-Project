import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/agent/agent_discovery.dart';
import 'package:dermaire_app/agent/server_agent_controller.dart';
import 'package:dermaire_app/notifications/inbox_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'f8_integration_contracts_test.dart' as f;

class NegativeDiscovery extends f.DiscoveryWire {
  String mode = '';
  int? status;
  Completer<http.Response>? delayed;
  @override
  Future<http.Response> call(http.Request r) async {
    if (!r.url.path.endsWith('/agent/sessions')) return super.call(r);
    expectHost(r);
    if (delayed != null) return delayed!.future;
    if (status != null) return http.Response('{}', status!);
    final response = await super.call(r);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final row = (data['items'] as List).single as Map<String, dynamic>;
    if (mode == 'scope') {
      row['scopes'] = ['longitudinal_read', 'clinical_write'];
    }
    if (mode == 'duplicate scope') {
      row['scopes'] = ['longitudinal_read', 'longitudinal_read'];
    }
    if (mode == 'private context') data['context_included'] = true;
    if (mode == 'duplicate row') data['items'] = [row, row];
    if (mode == 'order') {
      data['items'] = [
        {...row, 'id': 'session-1'},
        row,
      ];
    }
    if (mode == 'cycle') {
      data['items'] = <Object>[];
      data['next_before'] = pages.isOdd ? 'cursor-a' : 'cursor-b';
    }
    return http.Response(jsonEncode(data), 200);
  }
}

class AheadReceipt extends f.CasWire {
  @override
  Future<http.Response> call(http.Request r) async {
    final response = await super.call(r);
    if (r.method == 'PUT' && r.url.path.endsWith('/read')) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      data['state_revision'] = 99;
      return http.Response(jsonEncode(data), 200);
    }
    return response;
  }
}

class CyclingDoctorRequests extends f.DiscoveryWire {
  CyclingDoctorRequests() {
    owner = 'doctor-1';
    role = 'doctor';
  }
  int requestPages = 0;
  @override
  Future<http.Response> call(http.Request r) async {
    if (r.url.path.endsWith('/agent/requests')) {
      expectHost(r);
      requestPages++;
      expect(r.url.queryParameters['limit'], '100');
      return http.Response(
        jsonEncode({
          'items': [],
          'limit': 100,
          'medical_execution_enabled': false,
          'notification_delivery': 'unavailable',
            'next_before': requestPages.isOdd ? 'cursor-a' : 'cursor-b',
        }),
        200,
      );
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
    'F8 review doctor request pagination refuses nonadjacent cursor reuse',
    () async {
      final w = CyclingDoctorRequests();
      await w.run(() async {
        await w.login();
        final c = ClinicianRequestsController();
        await c.refresh();
        await c.more();
        expect(c.next, 'cursor-b');
        await c.more();
        expect(c.next, isNull);
        expect(c.error, isNotNull);
        c.dispose();
      });
    },
  );
  test(
    'F8 review notification readback cannot precede mutation receipt revision',
    () async {
      final w = AheadReceipt();
      await w.run(() async {
        await w.login();
        final c = InboxController();
        await c.refresh();
        expect(await c.mark(c.notices.first, read: true), false);
        expect(c.outcome, isNull);
        expect(c.error, isNotNull);
        c.dispose();
      });
    },
  );
  for (final size in [4, 8, 128, 129]) {
    test(
      'F8 review reset length matches Backend Unicode characters $size',
      () async {
        var calls = 0;
        await http.runWithClient(
          () async {
            final request = api.resetPassword(
              email: 'user@example.invalid',
              token: '12345678',
              newPassword: '😀' * size,
            );
            if (size < 8 || size > 128) {
              await expectLater(request, throwsA(anything));
              expect(calls, 0);
            } else {
              await request;
              expect(calls, 1);
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            calls++;
            return http.Response('{}', 200);
          }),
        );
      },
    );
  }
  for (final mode in [
    'scope',
    'duplicate scope',
    'private context',
    'duplicate row',
    'order',
  ]) {
    test('F8 review refuses malformed discovery $mode', () async {
      final w = NegativeDiscovery()..mode = mode;
      await w.run(() async {
        await w.login();
        final c = AgentDiscovery();
        await c.refresh();
        expect(c.rows, isEmpty);
        expect(c.error, isNotNull);
        c.dispose();
      });
    });
  }
  for (final status in [401, 403, 404, 409, 410, 422]) {
    test('F8 review discovery HTTP$status clears private page', () async {
      final w = NegativeDiscovery();
      await w.run(() async {
        await w.login();
        final c = AgentDiscovery();
        await c.refresh();
        expect(c.rows, hasLength(1));
        w.status = status;
        await c.load(more: true);
        expect(c.rows, isEmpty);
        expect(c.next, isNull);
        c.dispose();
      });
    });
  }
  test('F8 review detects cursor cycle across empty pages', () async {
    final w = NegativeDiscovery()..mode = 'cycle';
    await w.run(() async {
      await w.login();
      final c = AgentDiscovery();
      await c.refresh();
      await c.load(more: true);
      expect(c.next, 'cursor-b');
      await c.load(more: true);
      expect(c.next, isNull);
      expect(c.error, isNotNull);
      c.dispose();
    });
  });
  for (final switchAccount in [false, true]) {
    test('F8 review late discovery is fenced switch=$switchAccount', () async {
      final w = NegativeDiscovery();
      await w.run(() async {
        await w.login();
        final c = AgentDiscovery();
        final response = await w.call(
          http.Request(
            'GET',
            Uri.parse(
              'https://flutter-tests.invalid/api/v1/agent/sessions?limit=20',
            ),
          ),
        );
        w.delayed = Completer<http.Response>();
        final pending = c.refresh();
        await Future<void>.delayed(Duration.zero);
        await api.logout();
        if (switchAccount) {
          w.owner = 'other-patient';
          await w.login();
        }
        w.delayed!.complete(response);
        await pending;
        expect(c.rows, isEmpty);
        expect(c.current, false);
        c.dispose();
      });
    });
  }
}
