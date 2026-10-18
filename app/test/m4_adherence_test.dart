import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/routine/routine_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'routine_authority_test.dart' as r;
import 'product_authority_test.dart' as p;

Map<String, dynamic> event([String id = 'event']) => {
  'id': id,
  'routine_entry_id': 'entry',
  'date': '2026-10-03',
  'slot': 'AM',
  'status': 'completed',
  'source': 'user_reported',
  'note': null,
  'created_at': '2026-10-03T12:00:00',
  'configuration_snapshot': r.entry(),
};

Map<String, dynamic> keyedEvent({
  String owner = 'patient-1',
  String id = 'event',
}) => {
  ...event(id),
  'day_basis': 'UTC',
  'configuration_snapshot': {
    ...r.entry(),
    'revision': 1,
    'revision_protected': false,
  },
  'receipt': {
    'schema_version': 1,
    'operation': 'routine_adherence',
    'attempt_id': id,
    'owner_id': owner,
    'actor_id': owner,
    'resource_id': id,
    'configuration_revision': 1,
    'status': 'committed',
    'committed_at': '2026-10-03T12:00:00Z',
    'expires_at': '2026-11-02T12:00:00Z',
  },
};

class Reports extends r.Repository {
  int offset = 0;
  List<Map<String, dynamic>> next = [];
  @override
  Future<List<Map<String, dynamic>>> read(String resource) async {
    if (resource.contains('offset=')) {
      offset = int.parse(Uri.parse(resource).queryParameters['offset']!);
      if (offset > 0) {
        if (pending != null) return pending!.future;
        if (this.fail) {
          throw Exception('synthetic offline');
        }
        return next;
      }
    }
    return super.read(resource);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final kind in [
    'missing snapshot',
    'wrong snapshot identity',
    'wrong snapshot source',
    'missing schedule',
    'unknown status',
    'wrong slot',
    'invalid UTC date',
  ]) {
    test('adherence rejects $kind', () {
      final row = event();
      switch (kind) {
        case 'missing snapshot':
          row['configuration_snapshot'] = {};
        case 'wrong snapshot identity':
          row['configuration_snapshot']['id'] = 'other';
        case 'wrong snapshot source':
          row['configuration_snapshot']['source'] = 'doctor';
        case 'missing schedule':
          row['configuration_snapshot']['schedule'] = null;
        case 'unknown status':
          row['status'] = 'partial';
        case 'wrong slot':
          row['slot'] = 'PM';
        case 'invalid UTC date':
          row['date'] = '2026-02-30';
      }
      expect(RoutineController.validRow(row, 'user_reported'), false);
    });
  }
  for (final kind in [
    'confirmed',
    'missing readback',
    'timeout',
    '503',
    '403',
    '409',
  ]) {
    test('adherence $kind never invents confirmation', () async {
      var posts = 0;
      var stored = false;
      await http.runWithClient(
        () async {
          await p.login();
          final c = RoutineController(RemoteRoutineRepository());
          await c.refresh();
          final payload = {
            'routine_entry_id': 'entry',
            'date': '2026-10-03',
            'slot': 'AM',
            'status': 'completed',
          };
          final ok = await c.write('adherence', payload);
          expect(ok, kind == 'confirmed');
          if (kind == 'confirmed') {
            expect(c.history!.single['id'], 'event');
            expect(await c.write('adherence', payload), false);
          } else {
            await c.refresh();
            expect(await c.write('adherence', payload), false);
          }
          expect(posts, 1);
          c.dispose();
        },
        () => MockClient((req) async {
          expect(req.url.host, 'flutter-tests.invalid');
          if (req.url.path.endsWith('/auth/login')) return p.auth();
          if (req.url.path.endsWith('/users/me')) {
            return http.Response(
              '{"id":"patient-1","role":"patient","safety_accepted":true}',
              200,
            );
          }
          if (req.method == 'POST') {
            posts++;
            if (kind == 'timeout') throw TimeoutException('synthetic');
            if (['503', '403', '409'].contains(kind)) {
              return http.Response('{}', int.parse(kind));
            }
            stored = true;
            expect(req.headers['Idempotency-Key'], isNotNull);
            expect(req.headers['If-Match'], isNull);
            return http.Response(jsonEncode(keyedEvent()), 201);
          }
          if (req.url.path.endsWith('/entries')) {
            return http.Response(jsonEncode([r.entry()]), 200);
          }
          return http.Response(
            jsonEncode(stored && kind == 'confirmed' ? [keyedEvent()] : []),
            200,
          );
        }),
      );
    });
  }
  for (final kind in ['next page', 'overlap', 'offline', 'late clear']) {
    test('real offset history $kind preserves reports', () async {
      final repo = Reports()
        ..entries = [r.entry()]
        ..history = List.generate(100, (i) => event('e$i'))
        ..next = [event('older')];
      final c = RoutineController(repo);
      await c.refresh();
      expect(c.historyHasMore, true);
      if (kind == 'overlap') repo.next = [event('e0')];
      if (kind == 'offline') repo.fail = true;
      if (kind == 'late clear') {
        repo.pending = Completer();
        final more = c.loadMoreHistory();
        c.clear();
        repo.pending!.complete([event('older')]);
        await more;
        expect(c.history, isNull);
      } else {
        await c.loadMoreHistory();
        expect(repo.offset, 100);
        expect(c.history!.length, kind == 'next page' ? 101 : 100);
        if (kind != 'next page') expect(c.stale, true);
      }
      c.dispose();
    });
  }
}
