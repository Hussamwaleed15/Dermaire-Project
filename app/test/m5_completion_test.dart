import 'dart:async';
import 'package:dermaire_app/notifications/inbox_controller.dart';
import 'package:dermaire_app/notifications/inbox_models.dart';
import 'package:dermaire_app/notifications/inbox_ui.dart';
import 'package:dermaire_app/notifications/notification_availability.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_inbox_test.dart' as w;
import 'm6_doctor_fixture.dart' as f;

Map<String, dynamic> notice(String id, {String at = '2026-10-18T12:00:00Z'}) =>
    {
      'id': id,
      'kind': 'routine',
      'source_id': 'entry-1',
      'source_revision': 1,
      'state_revision': 1,
      'created_at': at,
      'due_at': '2026-10-18T10:00:00Z',
      'read_at': null,
      'unread': true,
      'push_delivery': 'unconfirmed',
    };
Map<String, dynamic> history() => {
  'id': 'n',
  'kind': 'routine',
  'state': 'current',
  'due_at': '2026-10-18T10:00:00Z',
  'delivery_confirmed': false,
  'jobs': [
    {
      'id': 'job',
      'state': 'provider_accepted',
      'attempts': 1,
      'attempt_history': [
        {
          'id': 'attempt',
          'number': 1,
          'state': 'provider_accepted',
          'delivery_confirmed': false,
        },
      ],
    },
  ],
};

class Pages extends w.InboxWire {
  final Map<String, List<Map<String, dynamic>>> pages = {
    '': [notice('z'), notice('y')],
    'y': [notice('x'), notice('w')],
  };
  final Map<String, String?> cursors = {'': 'y', 'y': null};
  Completer<http.Response>? pendingPage;
  int reads = 0;
  int? historyStatus;
  @override
  Future<http.Response> call(http.Request r) async {
    if (r.method == 'GET' &&
        r.url.path.endsWith('/notifications/history') &&
        historyStatus != null) {
      return f.json({}, historyStatus!);
    }
    if (r.method == 'GET' && r.url.path.endsWith('/notifications')) {
      expectHost(r);
      reads++;
      requests.add(r);
      final cursor = r.url.queryParameters['before'] ?? '';
      if (pendingPage != null) return pendingPage!.future;
      final rows = pages[cursor] ?? [];
      return f.json({
        'items': rows,
        'next_before': cursors[cursor],
        'unread_in_page': rows.where((n) => n['unread'] == true).length,
        'provider': 'disabled',
        'delivery_confirmed': false,
      });
    }
    return super.call(r);
  }
}

class LostRead extends w.InboxWire {
  bool lose = true, committed = false;
  @override
  Future<http.Response> call(http.Request r) async {
    if (r.method == 'PUT' &&
        !r.url.path.endsWith('/preferences') &&
        !r.url.path.contains('/routine-reminders/')) {
      final response = await super.call(r);
      committed = true;
      if (lose) throw TimeoutException('synthetic response loss');
      return response;
    }
    return super.call(r);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final status in [500, 403]) {
    test(
      'transport history $status preserves only independently authorized inbox',
      () async {
        final wire = Pages()..historyStatus = status;
        await wire.run(() async {
          await wire.login();
          final c = InboxController();
          await c.refresh();
          if (status == 500) {
            expect(c.notices.length, 2);
            expect(c.historyError, isNotNull);
            wire.historyStatus = null;
            await c.refreshHistory();
            expect(c.historyError, isNull);
            expect(c.notices.length, 2);
          } else {
            expect(c.notices, isEmpty);
            expect(c.error, isNotNull);
          }
          expect(wire.sends, isEmpty);
          c.dispose();
        });
      },
    );
  }
  test(
    'actual controller traverses two nonempty timestamp-tied ordered pages',
    () async {
      final wire = Pages();
      await wire.run(() async {
        await wire.login();
        final c = InboxController();
        await c.refresh();
        expect(c.notices.map((n) => n.id), ['z', 'y']);
        await c.more();
        expect(c.notices.map((n) => n.id), ['z', 'y', 'x', 'w']);
        expect(c.next, isNull);
        expect(wire.sends, isEmpty);
        c.dispose();
      });
    },
  );
  for (final kind in [
    'within-page',
    'across-page',
    'cycle',
    'oversize',
    'duplicate',
  ]) {
    test('inbox rejects $kind instead of claiming current history', () async {
      final wire = Pages();
      await wire.run(() async {
        await wire.login();
        final c = InboxController();
        if (kind == 'within-page') wire.pages[''] = [notice('a'), notice('z')];
        if (kind == 'oversize') {
          wire.pages[''] = List.generate(
            51,
            (i) => notice('n${(99 - i).toString().padLeft(2, '0')}'),
          );
        }
        await c.refresh();
        if (kind == 'across-page') wire.pages['y'] = [notice('zz')];
        if (kind == 'cycle') wire.cursors['y'] = 'y';
        if (kind == 'duplicate') wire.pages['y'] = [notice('y')];
        if (!['within-page', 'oversize'].contains(kind)) await c.more();
        expect(c.error, isNotNull);
        expect(c.notices, isEmpty);
        c.dispose();
      });
    });
  }
  test(
    'privacy-filtered empty page may advance using a nonvisible cursor',
    () async {
      final wire = Pages();
      wire.pages[''] = [];
      wire.cursors[''] = 'hidden-anchor';
      wire.pages['hidden-anchor'] = [notice('a')];
      wire.cursors['hidden-anchor'] = null;
      await wire.run(() async {
        await wire.login();
        final c = InboxController();
        await c.refresh();
        expect(c.notices, isEmpty);
        expect(c.next, 'hidden-anchor');
        await c.more();
        expect(c.notices.single.id, 'a');
        expect(c.error, isNull);
        c.dispose();
      });
    },
  );
  test('unchanged revision cannot alter confirmed read state', () async {
    final wire = Pages();
    await wire.run(() async {
      await wire.login();
      final c = InboxController();
      await c.refresh();
      wire.pages[''] = [
        {...notice('z'), 'read_at': '2026-10-18T13:00:00Z', 'unread': false},
      ];
      wire.cursors[''] = null;
      await c.refresh();
      expect(c.notices, isEmpty);
      expect(c.error, isNotNull);
      c.dispose();
    });
  });
  test('older read revision cannot replace newer known state', () async {
    final wire = Pages();
    wire.pages[''] = [
      {...notice('z'), 'state_revision': 3},
    ];
    wire.cursors[''] = null;
    await wire.run(() async {
      await wire.login();
      final c = InboxController();
      await c.refresh();
      wire.pages[''] = [notice('z')];
      await c.refresh();
      expect(c.error, isNotNull);
      expect(c.notices, isEmpty);
      c.dispose();
    });
  });
  for (final boundary in ['hide', 'switch', 'dispose']) {
    test('pending page rejected after $boundary without writes', () async {
      final wire = Pages();
      await wire.run(() async {
        await wire.login();
        final c = InboxController();
        await c.refresh();
        wire.pendingPage = Completer();
        final pending = c.more();
        await Future<void>.delayed(Duration.zero);
        if (boundary == 'hide') {
          c.hide();
        } else if (boundary == 'switch') {
          await ApiService.instance.init();
        } else {
          c.dispose();
        }
        wire.pendingPage!.complete(
          f.json({
            'items': [notice('x')],
            'next_before': null,
            'unread_in_page': 1,
            'provider': 'disabled',
            'delivery_confirmed': false,
          }),
        );
        await pending;
        expect(c.notices, isEmpty);
        expect(wire.sends, isEmpty);
        if (!c.disposed) c.dispose();
      });
    });
  }
  test(
    'lost settings response retains original identity after matching current CAS read',
    () async {
      final wire = w.InboxWire();
      await wire.run(() async {
        await wire.login();
        final c = NoticeSettingsController();
        await c.refresh();
        wire.mode = 'lost after';
        expect(await c.save(w.settings()), false);
        final original = c.pending!;
        await c.refresh();
        expect(c.pending, isNull);
        expect(c.unconfirmedOriginals, 1);
        expect(
          ApiService.instance.integrationIntents.values,
          contains(same(original)),
        );
        expect(original.body['expected_revision'], 0);
        expect(original.uncertain, true);
        expect(wire.sends.length, 1);
        c.hide();
        expect(c.unconfirmedOriginals, 1);
        c.dispose();
        await ApiService.instance.init();
        expect(ApiService.instance.integrationIntents, isEmpty);
      });
    },
  );
  test(
    'synchronous settings acknowledgment does not become an unknown attempt',
    () async {
      final wire = w.InboxWire();
      await wire.run(() async {
        await wire.login();
        final c = NoticeSettingsController();
        await c.refresh();
        expect(await c.save(w.settings()), true);
        expect(c.unconfirmedOriginals, 0);
        expect(c.pending, isNull);
        expect(c.confirmedAt, isNotNull);
        c.dispose();
      });
    },
  );
  test('settings changed at same revision are unsupported', () async {
    final wire = w.InboxWire();
    await wire.run(() async {
      await wire.login();
      final c = NoticeSettingsController();
      await c.refresh();
      wire.preferences = {...wire.preferences, 'timezone': 'Asia/Tokyo'};
      await c.refresh();
      expect(c.value, isNull);
      expect(c.error, isNotNull);
      expect(wire.sends, isEmpty);
      c.dispose();
    });
  });
  test(
    'uncertain disable retains exact original CAS identity; refresh does not retry',
    () async {
      final wire = w.InboxWire();
      await wire.run(() async {
        await wire.login();
        final c = NoticeSettingsController();
        await c.refresh();
        wire.mode = 'lost after';
        await c.disableAll();
        final original = ApiService.instance.integrationIntents.values.single;
        expect(c.unconfirmedWithdrawal, true);
        await c.refresh();
        expect(wire.sends.length, 1);
        expect(
          ApiService.instance.integrationIntents.values,
          contains(same(original)),
        );
        expect(original.method, 'DELETE');
        expect(original.body['expected_revision'], 0);
        c.dispose();
      });
    },
  );
  test(
    'lost app-read acknowledgment is not proved by matching current state',
    () async {
      final wire = LostRead();
      await wire.run(() async {
        await wire.login();
        final c = InboxController();
        await c.refresh();
        final n = c.notices.first;
        expect(await c.mark(n, read: true), false);
        final original = ApiService.instance.integrationIntents.values.single;
        expect(wire.committed, true);
        await c.refresh();
        expect(c.notices.first.read, isNotNull);
        expect(c.unconfirmedReadChanges, 1);
        expect(
          ApiService.instance.integrationIntents.values,
          contains(same(original)),
        );
        expect(wire.sends.length, 1);
        c.hide();
        await c.show();
        expect(c.unconfirmedReadChanges, 1);
        expect(wire.sends.length, 1);
        c.dispose();
      });
    },
  );
  for (final field in ['delivery', 'state', 'number', 'attempts']) {
    test('transport rejects unsupported $field without a delivery claim', () {
      final v = history();
      final job = (v['jobs'] as List).first;
      final attempt = (job['attempt_history'] as List).first;
      if (field == 'delivery') {
        attempt['delivery_confirmed'] = true;
      } else if (field == 'state') {
        job['state'] = 'delivered';
      } else if (field == 'number') {
        attempt['number'] = 2;
      } else {
        job['attempts'] = -1;
      }
      expect(() => NoticeHistory(v), throwsFormatException);
    });
  }
  test('provider acceptance remains separate from delivery', () {
    final v = NoticeHistory(history());
    expect(v.jobs.single['state'], 'provider_accepted');
    expect(transportStateLabel('provider_accepted'), contains('NOT confirmed'));
    expect(transportStateLabel('queued'), contains('unknown'));
  });
  for (final dark in [false, true]) {
    testWidgets(
      'availability remains inert and distinct at320px200 dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (_, child) => MediaQuery(
              data: const MediaQueryData(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const NotificationAvailabilityScreen(),
          ),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.textContaining('Push token: unavailable.'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.textContaining('register an installation'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'preferences disclose session draft and preserve original unknown outcome',
    (t) async {
      final wire = w.InboxWire();
      await wire.run(() async {
        await wire.login();
        final c = NoticeSettingsController();
        await c.refresh();
        wire.mode = 'lost after';
        await c.save(w.settings());
        c.dispose();
        await t.pumpWidget(
          const MaterialApp(home: NotificationPreferencesScreen()),
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.textContaining('earlier settings attempts have unknown'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.textContaining('Unsaved settings edits exist only in memory'),
          findsOneWidget,
        );
        expect(wire.sends.length, 1);
        await t.pumpWidget(const SizedBox());
        await ApiService.instance.init();
      });
    },
  );
}
