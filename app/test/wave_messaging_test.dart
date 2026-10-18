import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/messaging/messaging_models.dart';
import 'package:dermaire_app/messaging/messaging_controller.dart';
import 'package:dermaire_app/messaging/messaging_ui.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

class MessageWire extends f.DoctorWire {
  MessageWire({bool doctor = false}) {
    owner = doctor ? 'doctor-1' : 'patient-1';
    role = doctor ? 'doctor' : 'patient';
  }
  String mode = 'success';
  int posts = 0, patientRead = 0, doctorRead = 0;
  bool enrolled = true, closed = false;
  final messages = <Map<String, dynamic>>[], sends = <http.Request>[];
  final receipts = <String, Map<String, dynamic>>{};
  Completer<http.Response>? delay;
  Map<String, dynamic> get thread => {
    'id': 'thread-1',
    'patient_id': 'patient-1',
    'doctor_id': 'doctor-1',
    'access_id': 'grant-1',
    'created_at': '2026-10-01T00:00:00Z',
    'closed_at': closed ? '2026-10-18T12:00:00Z' : null,
    'latest_sequence': messages.length,
    'patient_read': patientRead,
    'doctor_read': doctorRead,
    'emergency_service': false,
    'retention':
        'account_lifetime_erased_if_either_participant_deletes_account',
  };
  Map<String, dynamic> message(int sequence, String body) => {
    'id': 'message-$sequence',
    'thread_id': 'thread-1',
    'actor_id': owner,
    'sequence': sequence,
    'body': body,
    'created_at': '2026-10-18T10:00:00Z',
    'provenance': 'participant_authored',
    'clinical_clearance': false,
  };
  CareThread get model => CareThread.fromApi(thread, owner, role);
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    final path = request.url.path;
    if (path.endsWith('/doctor/access')) {
      return f.json([
        {
          ...grant(),
          'id': 'grant-1',
          'doctor_id': 'doctor-1',
          'scopes': ['VIEW'],
        },
      ]);
    }
    if (path.contains('/messaging/')) {
      requests.add(request);
      if (path.endsWith('/threads')) {
        if (request.method == 'POST') {
          enrolled = true;
          expect(jsonDecode(request.body), {
            'access_id': 'grant-1',
            'messaging_consent': true,
          });
          return f.json(thread, 201);
        }
        return f.json({
          'items': enrolled && !closed ? [thread] : [],
          'next_after': null,
        });
      }
      if (closed || mode == 'revoked') return f.json({}, 403);
      if (path.contains('/attempts/')) {
        final row = receipts[path.split('/').last];
        return f.json({
          'attempt_id': row?['id'] ?? 'unknown-attempt',
          'status': mode == 'expired'
              ? 'expired'
              : row == null
              ? 'unknown'
              : 'committed',
          'result': mode == 'expired' ? null : row,
        });
      }
      if (path.endsWith('/consent')) {
        closed = true;
        return f.json({'id': 'thread-1', 'status': 'closed'});
      }
      if (path.endsWith('/read')) {
        final sequence =
            (jsonDecode(request.body) as Map)['through_sequence'] as int;
        if (role == 'patient') {
          patientRead = sequence;
        } else {
          doctorRead = sequence;
        }
        return f.json(thread);
      }
      if (path.endsWith('/messages')) {
        if (request.method == 'POST') {
          posts++;
          sends.add(request);
          if (delay != null) return delay!.future;
          if (['401', '403', '409', '410', '422', '503'].contains(mode)) {
            return f.json({}, int.parse(mode));
          }
          if (mode == 'lost before') {
            throw TimeoutException('synthetic before commit');
          }
          final body = (jsonDecode(request.body) as Map)['body'] as String,
              key = request.headers['Idempotency-Key']!;
          final result = receipts.putIfAbsent(key, () {
            final row = message(messages.length + 1, body);
            messages.add(row);
            return row;
          });
          if (mode == 'lost after') {
            throw TimeoutException('synthetic after commit');
          }
          final row = Map<String, dynamic>.from(result);
          if (mode == 'wrong actor') row['actor_id'] = 'foreign';
          if (mode == 'wrong thread') row['thread_id'] = 'foreign';
          return http.Response(
            jsonEncode(row),
            201,
            headers: {'operation-attempt-id': row['id'] as String},
          );
        }
        if (posts > 0 && mode == 'denied readback') return f.json({}, 403);
        final high =
            int.tryParse(request.url.queryParameters['as_of'] ?? '') ??
            messages.length;
        final after = int.parse(request.url.queryParameters['after']!),
            limit = int.parse(request.url.queryParameters['limit']!);
        final rows = messages
            .where((m) => m['sequence'] > after && m['sequence'] <= high)
            .toList();
        return f.json({
          'items': rows.take(limit).toList(),
          'as_of_sequence': high,
          'next_after': rows.length > limit
              ? rows[limit - 1]['sequence']
              : null,
          'patient_read': patientRead,
          'doctor_read': doctorRead,
        });
      }
    }
    return super.call(request);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final doctor in [false, true]) {
    test(
      'current role doctor=$doctor reads, sends, and acknowledges actual history',
      () async {
        final wire = MessageWire(doctor: doctor);
        await wire.run(() async {
          await wire.login();
          final list = ThreadsController();
          await list.refresh();
          expect(list.threads.length, 1);
          final c = ConversationController(list.threads.single);
          await c.refresh();
          expect(c.messages, isEmpty);
          expect(await c.send('  Real participant text  '), true);
          expect(c.messages.single.body, 'Real participant text');
          expect(c.outcome, contains('not confirmed'));
          expect(wire.posts, 1);
          await c.markRead();
          expect(doctor ? c.doctorRead : c.patientRead, 1);
          expect(api.integrationIntents, isEmpty);
          c.dispose();
          list.dispose();
        });
      },
    );
  }
  test(
    'patient enrollment requires explicit active-grant selection and confirmed thread',
    () async {
      final wire = MessageWire()..enrolled = false;
      await wire.run(() async {
        await wire.login();
        final c = ThreadsController();
        await c.refresh();
        expect(c.threads, isEmpty);
        expect(c.grants.single['id'], 'grant-1');
        expect(await c.enroll('foreign'), isNull);
        expect((await c.enroll('grant-1'))!.grant, 'grant-1');
        c.dispose();
      });
    },
  );
  test(
    'frozen high watermark loads latest and earlier messages without duplicate pages',
    () async {
      final wire = MessageWire();
      for (int i = 1; i <= 120; i++) {
        wire.messages.add(wire.message(i, 'Recorded $i'));
      }
      await wire.run(() async {
        await wire.login();
        final c = ConversationController(wire.model);
        await c.refresh();
        expect(c.messages.first.sequence, 71);
        expect(c.messages.last.sequence, 120);
        wire.messages.add(wire.message(121, 'New after snapshot'));
        await c.earlier();
        expect(c.high, 120);
        expect(c.messages.first.sequence, 21);
        expect(c.messages.last.sequence, 120);
        await c.earlier();
        expect(c.messages.length, 120);
        expect(c.hasEarlier, false);
        c.dispose();
      });
    },
  );
  for (final mode in [
    'lost before',
    'lost after',
    '401',
    '403',
    '409',
    '410',
    '422',
    '503',
    'wrong actor',
    'wrong thread',
    'denied readback',
  ]) {
    test('send $mode is never optimistic or blindly duplicated', () async {
      final wire = MessageWire();
      await wire.run(() async {
        await wire.login();
        final c = ConversationController(wire.model);
        await c.refresh();
        wire.mode = mode;
        expect(await c.send('Original body across uncertain requests'), false);
        expect(wire.posts, 1);
        expect(c.messages, isEmpty);
        expect(c.pending != null, !['401', '403', '422'].contains(mode));
        if (c.pending != null) {
          final key = c.pending!.key;
          expect(await c.send('Different replacement'), false);
          expect(wire.posts, 1);
          wire.mode = 'success';
          await c.refresh();
          if (mode == 'lost after') {
            expect(await c.reconcile(), true);
            expect(wire.posts, 1);
            expect(c.pending, isNull);
          }
          if (mode == 'lost before') {
            expect(await c.reconcile(), false);
            expect(c.pending!.key, key);
            expect(await c.reconcile(retryOriginal: true), true);
            expect(wire.posts, 2);
            expect(
              wire.sends.first.headers['Idempotency-Key'],
              wire.sends.last.headers['Idempotency-Key'],
            );
            expect(wire.sends.first.body, wire.sends.last.body);
            expect(wire.messages.length, 1);
          }
        }
        c.dispose();
      });
    });
  }
  test(
    'expired receipt remains locked, does not produce a new message key',
    () async {
      final wire = MessageWire();
      await wire.run(() async {
        await wire.login();
        final c = ConversationController(wire.model);
        await c.refresh();
        wire.mode = 'lost before';
        await c.send('Original expires');
        wire.mode = 'expired';
        expect(await c.reconcile(retryOriginal: true), false);
        expect(wire.posts, 1);
        expect(c.pending, isNotNull);
        c.dispose();
      });
    },
  );
  for (final mode in ['duplicate', 'hide', 'logout', 'account switch']) {
    test('pending send $mode isolates late content', () async {
      final wire = MessageWire();
      await wire.run(() async {
        await wire.login();
        final c = ConversationController(wire.model);
        await c.refresh();
        wire.delay = Completer();
        final sending = c.send('Late original content');
        await Future<void>.delayed(Duration.zero);
        expect(wire.posts, 1);
        expect(await c.send('Duplicate'), false);
        if (mode == 'hide') c.hide();
        if (mode == 'logout') await api.logout();
        if (mode == 'account switch') {
          await api.init();
          wire.owner = 'patient-b';
          await wire.login();
        }
        wire.delay!.complete(
          http.Response(
            jsonEncode(wire.message(1, 'Late original content')),
            201,
            headers: {'operation-attempt-id': 'message-1'},
          ),
        );
        // No saved row was committed by this delayed fixture: receipt alone cannot fabricate current history.
        expect(await sending, false);
        expect(c.messages, isEmpty);
        if (['logout', 'account switch'].contains(mode)) {
          expect(api.integrationIntents, isEmpty);
        }
        c.dispose();
      });
    });
  }
  test(
    'withdrawn original conversation cannot be reopened by refreshing or sending',
    () async {
      final wire = MessageWire();
      await wire.run(() async {
        await wire.login();
        final c = ConversationController(wire.model);
        await c.refresh();
        expect(await c.withdraw(), true);
        await c.refresh();
        expect(c.messages, isEmpty);
        expect(await c.send('No renewed authority'), false);
        expect(wire.posts, 0);
        c.dispose();
      });
    },
  );
  testWidgets(
    'withdrawal remains reachable after policy currency is lost, with content hidden',
    (t) async {
      final wire = MessageWire();
      await wire.run(() async {
        await wire.login();
        await t.pumpWidget(
          MaterialApp(home: CareConversationScreen(thread: wire.model)),
        );
        await t.pumpAndSettle();
        wire.accepted = false;
        await api.readSafetyAcceptance();
        await t.pumpAndSettle();
        expect(find.byKey(const Key('careMessageBody')), findsNothing);
        await t.tap(find.text('Withdraw messaging consent'));
        await t.pumpAndSettle();
        expect(wire.closed, true);
        await t.pumpWidget(const SizedBox());
        await api.logout();
      });
    },
  );
  test('late old401 send cannot clear a newer reused-token account', () async {
    final wire = MessageWire();
    await wire.run(() async {
      await wire.login();
      final c = ConversationController(wire.model);
      await c.refresh();
      wire.delay = Completer();
      final send = c.send('Old account send');
      await Future<void>.delayed(Duration.zero);
      await api.init();
      wire.owner = 'patient-b';
      await wire.login();
      wire.delay!.complete(f.json({}, 401));
      expect(await send, false);
      expect(api.authenticatedOwner, 'patient-b');
      expect(api.isAuthenticated, true);
      expect(c.messages, isEmpty);
      expect(api.integrationIntents, isEmpty);
      c.dispose();
    });
  });
  for (final dark in [false, true]) {
    testWidgets(
      'care conversation dark=$dark 320px/200% has truthful empty and consent states',
      (t) async {
        t.view.physicalSize = const Size(320, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final wire = MessageWire();
        await wire.run(() async {
          await wire.login();
          await t.pumpWidget(
            MaterialApp(
              theme: dark ? DermaireTheme.dark : DermaireTheme.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true,
                ),
                child: child!,
              ),
              home: CareConversationScreen(thread: wire.model),
            ),
          );
          await t.pumpAndSettle();
          expect(
            find.textContaining('Not monitored for emergencies'),
            findsOneWidget,
          );
          expect(wire.posts, 0);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await api.logout();
        });
      },
    );
  }
}
