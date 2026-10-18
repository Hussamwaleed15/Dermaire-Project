import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dermaire_app/routine/routine_evidence.dart';
import 'package:dermaire_app/routine/routine_evidence_controller.dart';
import 'package:dermaire_app/routine/routine_evidence_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'product_authority_test.dart' as auth;

Map<String, dynamic> event({
  String id = 'event-b',
  String date = '2026-10-18T11:00:00Z',
  String owner = 'patient-1',
}) => {
  'id': id,
  'routine_entry_id': 'entry-1',
  'source_product_id': 'product-1',
  'kind': 'created',
  'schema_version': 1,
  'created_at': date,
  'snapshot': {
    'id': 'entry-1',
    'user_id': owner,
    'product_id': 'product-1',
    'revision': 1,
    'schedule': 'AM',
    'frequency': 'daily',
    'active': true,
    'product_evidence': {'id': 'product-1', 'name': 'Recorded product'},
    'provenance': {
      'owner_id': owner,
      'source': 'committed_configuration_write',
      'day_basis': 'UTC',
      'historical_backfill': false,
      'clinical_validation': false,
      'actor_id': owner,
      'writer_operation': 'routine.create',
    },
  },
};
Map<String, dynamic> history({bool more = false}) => {
  'schema_version': 1,
  'day_basis': 'UTC',
  'coverage': 'prospective_orm_writes_no_backfill',
  'freshness': 'event_history_not_current_state_verification',
  'consistency': 'append_only_keyset_cutoff_not_atomic_snapshot',
  'as_of': '2026-10-18T12:00:00Z',
  'coverage_since': '2026-10-17T11:00:00Z',
  'last_evidence_at': '2026-10-18T11:00:00Z',
  'items': [
    more ? event(id: 'event-a', date: '2026-10-17T11:00:00Z') : event(),
  ],
  'next_cursor': more ? null : 'signed.next.cursor',
};
Map<String, dynamic> policy([int revision = 0, String zone = 'UTC']) => {
  'schema_version': 1,
  'revision': revision,
  'timezone': zone,
  'effective_at': revision == 0 ? null : '2026-10-18T12:00:00Z',
  'local_today': '2026-10-18',
  'adherence_day_basis': 'UTC',
  'historical_reinterpretation': false,
  'policy': 'forward_only_labels_at_committed_instant',
  'reminder_policy': 'explicit_per_reminder_timezone_fold_and_gap',
};

class Wire {
  int revision = 0, historyStatus = 200, putStatus = 200, puts = 0;
  String zone = 'UTC', loss = '', owner = 'patient-1';
  bool wrongCurrent = false;
  Completer<http.Response>? delayedHistory;
  final historySent = Completer<void>();
  final requests = <http.Request>[];
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    requests.add(r);
    if (r.url.path.endsWith('/auth/login')) {
      return http.Response(
        jsonEncode({
          'access_token': 'synthetic',
          'expires_in': 3600,
          'user_id': owner,
          'role': 'patient',
        }),
        200,
      );
    }
    if (r.url.path.endsWith('/users/me')) {
      return http.Response(
        jsonEncode({'id': owner, 'role': 'patient', 'safety_accepted': true}),
        200,
      );
    }
    if (r.url.path.endsWith('/auth/logout')) return http.Response('{}', 200);
    if (r.url.path.endsWith('/configuration-history')) {
      if (!historySent.isCompleted) historySent.complete();
      if (delayedHistory != null) return delayedHistory!.future;
      expect(r.method, 'GET');
      expect(r.url.queryParameters['limit'], '100');
      return http.Response(
        jsonEncode(history(more: r.url.queryParameters['cursor'] != null)),
        historyStatus,
      );
    }
    if (r.url.path.endsWith('/calendar-policy')) {
      if (r.method == 'PUT') {
        puts++;
        expect(r.headers.containsKey('Idempotency-Key'), false);
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'timezone', 'expected_revision'});
        if (loss == 'before') {
          throw const SocketException('synthetic loss before commit');
        }
        if (putStatus != 200) return http.Response('{}', putStatus);
        expect(body['expected_revision'], revision);
        zone = body['timezone'] as String;
        revision++;
        if (loss == 'after') {
          throw const SocketException('synthetic response loss');
        }
      }
      return http.Response(
        jsonEncode(
          policy(
            revision,
            wrongCurrent && r.method == 'GET' && revision > 0
                ? 'Europe/Paris'
                : zone,
          ),
        ),
        200,
      );
    }
    throw StateError('Unexpected synthetic route');
  }

  Future<void> run(
    Future<void> Function(RoutineEvidenceController) action,
  ) async => http.runWithClient(() async {
    await auth.login();
    final c = RoutineEvidenceController(entry: 'entry-1');
    try {
      await action(c);
    } finally {
      c.dispose();
      await ApiService.instance.init();
    }
  }, () => MockClient(call));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  test(
    'history is paginated, original product/writer are evidence, never current state',
    () async {
      final w = Wire();
      await w.run((c) async {
        await c.refresh();
        expect(c.events.single.name, 'Recorded product');
        expect(c.policy!.zone, 'UTC');
        await c.loadMore();
        expect(c.events.map((e) => e.id), ['event-b', 'event-a']);
        expect(c.more, false);
        expect(w.puts, 0);
        expect(
          w.requests.last.url.queryParameters['routine_entry_id'],
          'entry-1',
        );
      });
    },
  );
  for (final bad in [
    'owner',
    'product',
    'provenance',
    'schema',
    'order',
    'cursor',
    'cutoff',
  ]) {
    test(
      'reject history with invalid $bad rather than expose partial private evidence',
      () {
        final raw = history();
        final row = (raw['items'] as List).first as Map<String, dynamic>;
        switch (bad) {
          case 'owner':
            (row['snapshot'] as Map)['user_id'] = 'other';
          case 'product':
            row['source_product_id'] = 'foreign-product';
          case 'provenance':
            ((row['snapshot'] as Map)['provenance']
                    as Map)['clinical_validation'] =
                true;
          case 'schema':
            raw['schema_version'] = 2;
          case 'order':
            raw['items'] = [
              event(id: 'event-a', date: '2026-10-17T11:00:00Z'),
              event(),
            ];
          case 'cursor':
            raw['next_cursor'] = 'private/cursor';
          case 'cutoff':
            raw['as_of'] = '2026-10-16T00:00:00Z';
        }
        expect(
          () => RoutineEvidencePage.parse(raw, 'patient-1', entry: 'entry-1'),
          throwsFormatException,
        );
      },
    );
  }
  test(
    'calendar PUT uses original revision then verifies current separately',
    () async {
      final w = Wire();
      await w.run((c) async {
        await c.refresh();
        await c.changeZone('Africa/Cairo');
        expect(w.puts, 1);
        expect(c.policy!.revision, 1);
        expect(c.policy!.zone, 'Africa/Cairo');
        expect(c.pending, isNull);
        expect(c.outcome, contains('confirmed by the server'));
      });
    },
  );
  test('unchanged zone sends no request', () async {
    final w = Wire();
    await w.run((c) async {
      await c.refresh();
      await c.changeZone('UTC');
      expect(w.puts, 0);
      expect(c.outcome, contains('No update'));
    });
  });
  test(
    'lost committed calendar response reconciles a superseded CAS without claiming original receipt',
    () async {
      final w = Wire()..loss = 'after';
      await w.run((c) async {
        await c.refresh();
        await c.changeZone('Africa/Cairo');
        expect(c.pending!.uncertain, true);
        expect(c.policy, isNull);
        await c.refresh();
        expect(c.policy!.zone, 'Africa/Cairo');
        expect(c.pending, isNull);
        expect(c.outcome, contains('not independently receipted'));
        expect(w.puts, 1);
      });
    },
  );
  test(
    'unknown same-revision calendar result locks replacement; explicit retry preserves original body',
    () async {
      final w = Wire()..loss = 'before';
      await w.run((c) async {
        await c.refresh();
        await c.changeZone('Africa/Cairo');
        final original = c.pending!;
        await c.refresh();
        await c.changeZone('Europe/Paris');
        expect(w.puts, 1);
        expect(c.pending, same(original));
        w.loss = '';
        await c.changeZone('Africa/Cairo', retryOriginal: true);
        expect(w.puts, 2);
        final bodies = w.requests
            .where((r) => r.method == 'PUT')
            .map((r) => r.body)
            .toSet();
        expect(bodies.length, 1);
        expect(c.pending, isNull);
      });
    },
  );
  test(
    'stale calendar revision does not overwrite server or automatically retry',
    () async {
      final w = Wire()..putStatus = 412;
      await w.run((c) async {
        await c.refresh();
        await c.changeZone('Africa/Cairo');
        expect(c.pending, isNull);
        expect(c.policy, isNull);
        expect(w.puts, 1);
        expect(w.zone, 'UTC');
      });
    },
  );
  test(
    'same-revision contradictory policy readback retains uncertainty',
    () async {
      final w = Wire()..wrongCurrent = true;
      await w.run((c) async {
        await c.refresh();
        await c.changeZone('Africa/Cairo');
        expect(c.pending, isNotNull);
        expect(c.policy, isNull);
        expect(c.error, isNotNull);
      });
    },
  );
  for (final status in [401, 403, 410, 422, 503]) {
    test(
      'history $status clears visible evidence and requires explicit fresh read',
      () async {
        final w = Wire();
        await w.run((c) async {
          await c.refresh();
          w.historyStatus = status;
          await c.loadMore();
          expect(c.events, isEmpty);
          expect(c.policy, isNull);
          expect(c.more, false);
          expect(w.puts, 0);
        });
      },
    );
  }
  test(
    'late history after logout and another account cannot publish original rows',
    () async {
      final w = Wire()..delayedHistory = Completer<http.Response>();
      await w.run((c) async {
        final read = c.refresh();
        await w.historySent.future;
        await ApiService.instance.logout();
        w.owner = 'patient-b';
        await auth.login();
        w.delayedHistory!.complete(http.Response(jsonEncode(history()), 200));
        await read;
        expect(c.events, isEmpty);
        expect(c.policy, isNull);
      });
    },
  );
  test(
    'denied calendar update removes prior private history without repeating the write',
    () async {
      final w = Wire()..putStatus = 403;
      await w.run((c) async {
        await c.refresh();
        expect(c.events, isNotEmpty);
        await c.changeZone('Africa/Cairo');
        expect(c.events, isEmpty);
        expect(c.policy, isNull);
        expect(w.puts, 1);
      });
    },
  );
  test(
    'overlapping timezone updates send only the first original draft',
    () async {
      final w = Wire();
      await w.run((c) async {
        await c.refresh();
        await Future.wait([
          c.changeZone('Africa/Cairo'),
          c.changeZone('Europe/Paris'),
        ]);
        expect(w.puts, 1);
        expect(c.policy!.zone, 'Africa/Cairo');
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'routine history and consent-bound timezone form 320px 200% dark=$dark',
      (t) async {
        Future<void> scrollTo(Finder target, double delta) =>
            t.scrollUntilVisible(
              target,
              delta,
              scrollable: find.byType(Scrollable).first,
            );
        await t.binding.setSurfaceSize(const Size(320, 1000));
        addTearDown(() => t.binding.setSurfaceSize(null));
        final w = Wire();
        await http.runWithClient(() async {
          try {
            await auth.login();
            await t.pumpWidget(
              MaterialApp(
                theme: dark ? DermaireTheme.dark : DermaireTheme.light,
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx).copyWith(
                    textScaler: const TextScaler.linear(2),
                    disableAnimations: true,
                  ),
                  child: child!,
                ),
                home: const RoutineEvidenceScreen(),
              ),
            );
            await t.pumpAndSettle();
            await scrollTo(find.text('Current timezone: UTC'), 250);
            expect(find.text('Current timezone: UTC'), findsOneWidget);
            await scrollTo(find.byKey(const Key('routineCalendarZone')), 250);
            await t.enterText(
              find.byKey(const Key('routineCalendarZone')),
              'Africa/Cairo',
            );
            await scrollTo(
              find.byKey(const Key('routineCalendarConsent')),
              250,
            );
            await t.ensureVisible(
              find.byKey(const Key('routineCalendarConsent')),
            );
            await t.tap(find.byKey(const Key('routineCalendarConsent')));
            await t.pumpAndSettle();
            await scrollTo(find.byKey(const Key('routineCalendarZone')), -250);
            await t.enterText(
              find.byKey(const Key('routineCalendarZone')),
              'Europe/Paris',
            );
            await t.pumpAndSettle();
            await scrollTo(find.byKey(const Key('saveRoutineCalendar')), 250);
            await t.ensureVisible(find.byKey(const Key('saveRoutineCalendar')));
            expect(
              t
                  .widget<FilledButton>(
                    find.byKey(const Key('saveRoutineCalendar')),
                  )
                  .onPressed,
              isNull,
            );
            expect(w.puts, 0);
            expect(t.takeException(), isNull);
          } finally {
            await t.pumpWidget(const SizedBox.shrink());
            await ApiService.instance.init();
          }
        }, () => MockClient(w.call));
      },
    );
  }
}
