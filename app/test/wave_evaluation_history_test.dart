import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/consent/evaluation_withdrawal.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_evaluation_withdrawal_test.dart' as f;
import 'product_authority_test.dart' as auth;

class Wire extends f.Wire {
  int historyStatus = 200, pageSize = 100;
  String bad = '';
  final historyEvents = <Map<String, dynamic>>[];
  Completer<http.Response>? delayedHistory;
  final historySent = Completer<void>();
  void replaceCurrent() {
    final old = Map<String, dynamic>.of(job);
    historyEvents.add({
      'revision': 2,
      'actor_id': owner,
      'recorded_at': '2026-10-18T01:00:00Z',
      'operation': 'evaluation',
      'snapshot': old,
    });
    job = {...job, 'id': 'job-2', 'state': 'queued', 'plan_revision': 3};
    plan['revision'] = 3;
    historyEvents.add({
      'revision': 3,
      'actor_id': owner,
      'recorded_at': '2026-10-18T02:00:00Z',
      'operation': 'evaluation',
      'snapshot': Map.of(job),
    });
  }

  @override
  Future<http.Response> call(http.Request r) async {
    expect(r.url.host, 'flutter-tests.invalid');
    if (r.url.path.endsWith('/history')) {
      if (!historySent.isCompleted) historySent.complete();
      if (delayedHistory != null) return delayedHistory!.future;
      if (historyStatus != 200) return http.Response('{}', historyStatus);
      final after = int.parse(r.url.queryParameters['after_revision']!);
      final all = historyEvents.where((e) => e['revision'] > after).toList();
      final rows = all.take(pageSize).toList();
      final data = <String, dynamic>{
        'items': rows,
        'next_after_revision': all.length > pageSize
            ? rows.last['revision']
            : null,
        'numeric_comparison_metrics': null,
        'model_status': 'unavailable',
      };
      if (bad == 'cursor') data['next_after_revision'] = 999;
      if (rows.isNotEmpty) {
        if (bad == 'revision') rows.first['snapshot']['plan_revision'] = 999;
        if (bad == 'foreign') {
          rows.first['snapshot']['input'] = {'plan_id': 'other-plan'};
        }
        if (bad == 'actor') rows.first['actor_id'] = 'foreign';
        if (bad == 'order') data['items'] = [...rows, ...rows];
      }
      return http.Response(jsonEncode(data), 200);
    }
    return super.call(r);
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  test(
    'historical original cancellation resolves without cancelling new job',
    () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.replaceCurrent();
        await c.loadHistory(recoverOriginal: true);
        expect(c.pending, isNull);
        expect(c.job!['id'], 'job-2');
        expect(c.job!['state'], 'queued');
        expect(w.deletes, 1);
        expect(c.outcome, contains('recorded cancelled in server history'));
      });
    },
  );
  test(
    'every history page is checked before original handle is resolved',
    () async {
      final w = Wire()
        ..loss = 'after'
        ..pageSize = 1;
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.replaceCurrent();
        await c.loadHistory(recoverOriginal: true);
        expect(c.pending, isNotNull);
        expect(c.outcome, contains('incomplete'));
        await c.loadHistory(recoverOriginal: true);
        expect(c.pending, isNull);
        expect(w.deletes, 1);
      });
    },
  );
  test(
    'history projection drops inference and never changes current job display',
    () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.replaceCurrent();
        await c.refresh();
        await c.loadHistory();
        expect(c.job!['id'], 'job-2');
        expect(c.history.length, 2);
        expect(c.history.first['job'].containsKey('inference'), false);
        expect(c.history.first['job'].containsKey('input'), false);
      });
    },
  );
  test(
    'missing historical proof keeps original uncertain without DELETE replay',
    () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.replaceCurrent();
        w.historyEvents.removeAt(0);
        await c.loadHistory(recoverOriginal: true);
        expect(c.pending, isNotNull);
        expect(w.deletes, 1);
        expect(c.outcome, contains('does not confirm'));
      });
    },
  );
  for (final bad in ['cursor', 'revision', 'foreign', 'actor', 'order']) {
    test('invalid history $bad cannot unlock original cancellation', () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.replaceCurrent();
        w.bad = bad;
        await c.loadHistory(recoverOriginal: true);
        expect(c.pending, isNotNull);
        expect(c.error, isNotNull);
        expect(c.history, isEmpty);
        expect(w.deletes, 1);
      });
    });
  }
  for (final status in [401, 403, 404, 409, 410, 422, 503]) {
    test('history$status never creates original cancellation proof', () async {
      final w = Wire()..loss = 'after';
      await w.runJob((c) async {
        c.approve(true);
        await c.cancel();
        w.replaceCurrent();
        w.historyStatus = status;
        await c.loadHistory(recoverOriginal: true);
        expect(c.pending == null, status == 401);
        expect(c.history, isEmpty);
        expect(w.deletes, 1);
      });
    });
  }
  for (final event in ['hide', 'logout', 'switch']) {
    test(
      'late history after $event cannot restore content or resolve pending',
      () async {
        final w = Wire()..loss = 'after';
        await w.runJob((c) async {
          c.approve(true);
          await c.cancel();
          w.replaceCurrent();
          w.delayedHistory = Completer<http.Response>();
          final read = c.loadHistory(recoverOriginal: true);
          await w.historySent.future;
          if (event == 'hide') {
            c.hide();
          } else {
            await ApiService.instance.init();
          }
          if (event == 'switch') {
            w.owner = 'patient-2';
            await auth.login();
          }
          w.delayedHistory!.complete(
            http.Response(
              jsonEncode({
                'items': w.historyEvents,
                'next_after_revision': null,
                'numeric_comparison_metrics': null,
              }),
              200,
            ),
          );
          await read;
          expect(c.plan, isNull);
          expect(c.job, isNull);
          expect(c.history, isEmpty);
          expect(c.outcome, isNull);
          expect(w.deletes, 1);
        });
      },
    );
  }
  testWidgets(
    'real history screen labels original and current job separately',
    (t) async {
      final w = Wire()..loss = 'after';
      await w.runJob((seed) async {
        seed.approve(true);
        await seed.cancel();
        w.replaceCurrent();
        await t.pumpWidget(
          const MaterialApp(home: EvaluationWithdrawalScreen(id: 'plan-1')),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Read evaluation history'), 180);
        await t.ensureVisible(find.text('Read evaluation history'));
        await t.pumpAndSettle();
        await t.tap(find.text('Read evaluation history'));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(find.text('Historical job: job-1'), 180);
        expect(find.text('Historical job: job-1'), findsOneWidget);
        expect(find.text('Historical job: job-2'), findsOneWidget);
        expect(w.deletes, 1);
        expect(find.byType(Image), findsNothing);
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      });
    },
  );
}
