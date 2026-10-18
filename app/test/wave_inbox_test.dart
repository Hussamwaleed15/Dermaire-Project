import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/notifications/inbox_models.dart';
import 'package:dermaire_app/notifications/inbox_controller.dart';
import 'package:dermaire_app/notifications/inbox_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

class InboxWire extends f.DoctorWire {
  InboxWire({bool doctor = false}) {
    owner = doctor ? 'doctor-1' : 'patient-1';
    role = doctor ? 'doctor' : 'patient';
  }
  String mode = 'success';
  bool revoked = false;
  int pageSize = 1, readback = 0;
  final sends = <http.Request>[];
  Completer<http.Response>? delayed;
  Map<String, dynamic> preferences = {
    'revision': 0,
    'enabled_kinds': <String>[],
    'push_enabled': false,
    'timezone': 'UTC',
    'quiet_start': 0,
    'quiet_end': 0,
    'provider': 'disabled',
    'actual_delivery': 'unavailable',
  };
  Map<String, dynamic> reminder = {
    'revision': 0,
    'enabled': false,
    'configured': false,
  };
  final notices = <Map<String, dynamic>>[
    {
      'id': 'notice-2',
      'kind': 'follow_up',
      'source_id': 'plan-1',
      'source_revision': 1,
      'created_at': '2026-10-18T12:00:00Z',
      'due_at': '2026-10-18T12:00:00Z',
      'read_at': null,
      'unread': true,
      'push_delivery': 'unconfirmed',
    },
    {
      'id': 'notice-1',
      'kind': 'message',
      'source_id': 'message-1',
      'source_revision': 1,
      'created_at': '2026-10-18T10:00:00Z',
      'due_at': '2026-10-18T10:00:00Z',
      'read_at': null,
      'unread': true,
      'push_delivery': 'unconfirmed',
    },
  ];
  Map<String, dynamic> get page {
    final rows = notices.take(pageSize).toList();
    return {
      'items': rows,
      'next_before': notices.length > pageSize ? rows.last['id'] : null,
      'unread_in_page': rows.where((n) => n['unread'] == true).length,
      'provider': 'disabled',
      'delivery_confirmed': false,
    };
  }

  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    final path = r.url.path;
    if (!path.contains('/notifications')) return super.call(r);
    requests.add(r);
    if (revoked) return f.json({}, 403);
    if (r.method != 'GET') {
      sends.add(r);
      if (delayed != null) return delayed!.future;
      if (int.tryParse(mode) != null) return f.json({}, int.parse(mode));
      if (mode == 'lost before') throw TimeoutException('synthetic');
      if (path.endsWith('/preferences') ||
          path.contains('/routine-reminders/')) {
        final isReminder = path.contains('/routine-reminders/');
        final current = isReminder ? reminder : preferences;
        final body = r.method == 'DELETE'
            ? {
                'expected_revision': int.parse(
                  r.url.queryParameters['expected_revision']!,
                ),
                'enabled_kinds': [],
                'push_enabled': false,
                'timezone': current['timezone'],
                'quiet_start': current['quiet_start'],
                'quiet_end': current['quiet_end'],
              }
            : jsonDecode(r.body) as Map;
        if (body['expected_revision'] != current['revision']) {
          return f.json({}, 409);
        }
        final updated = <String, dynamic>{
          ...current,
          ...body,
          'revision': (current['revision'] as int) + 1,
        }..remove('expected_revision');
        if (isReminder) {
          updated.addAll({
            'configured': true,
            'calendar_policy': 'prospective_fixed_occurrences_v1',
            'live_delivery': 'unavailable',
            'effective_at': '2026-10-18T12:00:00Z',
          });
          reminder = updated;
        } else {
          preferences = updated;
        }
        if (mode == 'lost after') throw TimeoutException('synthetic');
        if (mode == 'superseded') {
          preferences = {
            ...updated,
            'revision': (updated['revision'] as int) + 1,
            'timezone': 'Asia/Tokyo',
          };
        }
        return f.json(updated);
      }
      final id = path.split('/').reversed.skip(1).first;
      final n = notices.firstWhere((n) => n['id'] == id);
      final read = path.endsWith('/read');
      n['read_at'] = read ? '2026-10-18T13:00:00Z' : null;
      n['unread'] = !read;
      return f.json({
        'id': id,
        'read_at': n['read_at'],
        if (read) 'receipt': 'app_read_acknowledged',
        if (!read) 'unread': true,
        'delivery_confirmed': false,
      });
    }
    if (path.endsWith('/preferences')) return f.json(preferences);
    if (path.contains('/routine-reminders/')) return f.json(reminder);
    if (path.endsWith('/history')) {
      return f.json({
        'items': [
          {
            'id': 'notice-2',
            'kind': 'follow_up',
            'due_at': '2026-10-18T12:00:00Z',
            'state': 'current',
            'cancelled_at': null,
            'jobs': [
              {
                'id': 'job-1',
                'state': 'retry',
                'attempts': 1,
                'attempt_history': [
                  {
                    'id': 'attempt-1',
                    'number': 1,
                    'state': 'unavailable',
                    'delivery_confirmed': false,
                  },
                ],
              },
            ],
            'delivery_confirmed': false,
          },
        ],
        'next_before': null,
        'history_contract':
            'prospective_attempts_and_current_authority_no_delivery_proof',
      });
    }
    if (mode == 'bad count') return f.json({...page, 'unread_in_page': 99});
    if (mode == 'fake delivered') {
      return f.json({...page, 'delivery_confirmed': true});
    }
    if (r.url.queryParameters['before'] != null) {
      final after = notices
          .skipWhile((n) => n['id'] != r.url.queryParameters['before'])
          .skip(1)
          .toList();
      return f.json({
        ...page,
        'items': after,
        'next_before': null,
        'unread_in_page': after.where((n) => n['unread'] == true).length,
      });
    }
    return f.json(page);
  }
}

Map<String, dynamic> settings({String zone = 'Africa/Cairo'}) => {
  'enabled_kinds': ['message', 'routine'],
  'push_enabled': false,
  'timezone': zone,
  'quiet_start': 1320,
  'quiet_end': 420,
};
void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final doctor in [false, true]) {
    test(
      'role $doctor loads honest bounded inbox count/history and pages',
      () async {
        final w = InboxWire(doctor: doctor);
        await w.run(() async {
          await w.login();
          final c = InboxController();
          await c.refresh();
          expect(c.unreadLoaded, 1);
          expect(c.next, 'notice-2');
          expect(c.history.single.jobs.single['state'], 'retry');
          await c.more();
          expect(c.unreadLoaded, 2);
          expect(c.next, isNull);
          expect(w.sends, isEmpty);
          c.dispose();
        });
      },
    );
  }
  test(
    'read and unread use receipts and fresh server state without delivery claim',
    () async {
      final w = InboxWire()..pageSize = 2;
      await w.run(() async {
        await w.login();
        final c = InboxController();
        await c.refresh();
        expect(await c.mark(c.notices.first, read: true), isTrue);
        expect(c.unreadLoaded, 1);
        expect(c.outcome, contains('unconfirmed'));
        expect(await c.mark(c.notices.first, read: false), isTrue);
        expect(c.unreadLoaded, 2);
        c.dispose();
      });
    },
  );
  for (final mode in ['bad count', 'fake delivered']) {
    test('$mode clears untrusted inbox', () async {
      final w = InboxWire()..mode = mode;
      await w.run(() async {
        await w.login();
        final c = InboxController();
        await c.refresh();
        expect(c.notices, isEmpty);
        expect(c.error, isNotNull);
        c.dispose();
      });
    });
  }
  test('save preferences requires CAS and current readback', () async {
    final w = InboxWire();
    await w.run(() async {
      await w.login();
      final c = NoticeSettingsController();
      await c.refresh();
      expect(c.value!.revision, 0);
      expect(await c.save(settings()), isTrue);
      expect(c.value!.revision, 1);
      expect(c.value!.data['timezone'], 'Africa/Cairo');
      expect(w.sends.single.headers.containsKey('Idempotency-Key'), isFalse);
      expect(c.pending, isNull);
      c.dispose();
    });
  });
  for (final mode in ['lost before', 'lost after']) {
    test(
      'settings $mode keeps exact CAS body and reconciles without new write',
      () async {
        final w = InboxWire();
        await w.run(() async {
          await w.login();
          final c = NoticeSettingsController();
          await c.refresh();
          w.mode = mode;
          expect(await c.save(settings()), isFalse);
          final original = c.pending!;
          expect(await c.save(settings(zone: 'Asia/Tokyo')), isFalse);
          w.mode = 'success';
          await c.refresh();
          if (mode == 'lost before') {
            expect(c.pending, same(original));
            expect(await c.retryOriginal(), isTrue);
            expect(w.sends.last.body, w.sends.first.body);
          } else {
            expect(c.pending, isNull);
            expect(w.sends.length, 1);
          }
          expect(c.value!.revision, 1);
          c.dispose();
        });
      },
    );
  }
  test(
    'newer settings supersede original receipt without false confirmation',
    () async {
      final w = InboxWire();
      await w.run(() async {
        await w.login();
        final c = NoticeSettingsController();
        await c.refresh();
        w.mode = 'superseded';
        expect(await c.save(settings()), isFalse);
        expect(c.value!.revision, 2);
        expect(c.value!.data['timezone'], 'Asia/Tokyo');
        expect(c.outcome, isNull);
        expect(c.pending, isNull);
        c.dispose();
      });
    },
  );
  test(
    'routine reminders use explicit zone/fold/skip and actual saved revision',
    () async {
      final w = InboxWire();
      await w.run(() async {
        await w.login();
        final c = NoticeSettingsController(entryId: 'entry-1');
        await c.refresh();
        expect(c.value!.data['configured'], isFalse);
        expect(
          await c.save({
            'enabled': true,
            'timezone': 'America/New_York',
            'am_minute': 90,
            'pm_minute': 1200,
            'fold': 1,
            'gap_policy': 'skip',
          }),
          isTrue,
        );
        expect(c.value!.data['fold'], 1);
        expect(
          c.value!.data['calendar_policy'],
          'prospective_fixed_occurrences_v1',
        );
        c.dispose();
      });
    },
  );
  for (final status in [401, 403, 404, 409, 422, 503]) {
    test(
      'preference $status preserves unconfirmed intent or invalidates session',
      () async {
        final w = InboxWire();
        await w.run(() async {
          await w.login();
          final c = NoticeSettingsController();
          await c.refresh();
          w.mode = '$status';
          expect(await c.save(settings()), isFalse);
          expect(c.outcome, isNull);
          expect(c.value, isNull);
          if (status != 401) expect(c.pending, isNotNull);
          c.dispose();
        });
      },
    );
  }
  test(
    'withdraw preferences remains allowed after current safety policy is lost',
    () async {
      final w = InboxWire();
      await w.run(() async {
        await w.login();
        final c = NoticeSettingsController();
        await c.refresh();
        w.accepted = false;
        await api.readSafetyAcceptance();
        expect(c.current, isFalse);
        expect(c.value, isNull);
        expect(c.canDisable, isTrue);
        await c.disableAll();
        expect(w.sends.single.method, 'DELETE');
        expect(c.outcome, contains('withdrawal acknowledged'));
        expect(c.value, isNull);
        c.dispose();
      });
    },
  );
  for (final action in ['hide', 'logout', 'switch']) {
    test('late preferences after $action cannot restore old data', () async {
      final w = InboxWire();
      await w.run(() async {
        await w.login();
        final c = NoticeSettingsController();
        await c.refresh();
        w.delayed = Completer();
        final pending = c.save(settings());
        await Future<void>.delayed(Duration.zero);
        if (action == 'hide') {
          c.hide();
        } else if (action == 'logout') {
          await api.logout();
        } else {
          w.owner = 'patient-2';
          await w.login();
        }
        w.delayed!.complete(
          f.json({...w.preferences, ...settings(), 'revision': 1}),
        );
        expect(await pending, isFalse);
        expect(c.value, isNull);
        expect(c.outcome, isNull);
        c.dispose();
      });
    });
  }
  test('clock parsing never normalizes invalid dates or ambiguous input', () {
    expect(parseClock('23:59'), 1439);
    expect(parseClock('24:00'), isNull);
    expect(parseClock('12:60'), isNull);
    expect(parseClock('8:00'), isNull);
    expect(clockMinute(90), '01:30');
  });
  for (final dark in [false, true]) {
    testWidgets('inbox and settings readable 320px 200% dark=$dark', (
      tester,
    ) async {
      final w = InboxWire();
      await w.run(() async {
        await w.login();
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Widget page(Widget home) => MaterialApp(
          theme: dark ? DermaireTheme.dark : DermaireTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: home,
        );
        await tester.pumpWidget(page(const NotificationInboxScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Notification inbox'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(page(const NotificationPreferencesScreen()));
        await tester.pumpAndSettle();
        expect(find.text('Notification preferences'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await api.logout();
      });
    });
  }
}
