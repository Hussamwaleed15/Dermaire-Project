import 'dart:async';
import 'package:dermaire_app/chat/chat_controller.dart';
import 'package:dermaire_app/chatbot.dart';
import 'package:dermaire_app/assistance/assistance_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'assistance_evidence_test.dart' as a;
import 'private_capture_history_test.dart' as h;
import 'observation_test.dart' as o;

final api = ApiService.instance;
Map<String, dynamic> envelope({
  String message = 'Synthetic canonical assistance.',
  String kind = 'education',
}) {
  final content = a.reply();
  content['message'] = message;
  return {
    'reply': message,
    'kind': kind,
    'escalation_triggered': kind == 'escalation',
    'azure_model_used':
        'Deterministic Contextual AI v1 (AI unavailable or narrowed)',
    'safety_details': {
      'authoritative_safety': {
        ...content['authoritative_safety'] as Map<String, dynamic>,
      },
      'contextual_assistance': content,
    },
  };
}

class Fixture extends a.Fixture {
  Fixture() {
    body = envelope();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  test(
    'actual chat wrapper and embedded assistance are validated separately',
    () {
      final r = PatientChatReply.fromApi(envelope(), owner: 'a');
      expect(r.kind, 'education');
      expect(r.assistance.facts.length, 1);
      expect(r.compatibilitySource, contains('Deterministic'));
    },
  );
  for (final fault in [
    'kind',
    'text mismatch',
    'missing details',
    'escalation',
    'safety mismatch',
  ]) {
    test('invalid $fault never produces a fake assistant reply', () {
      final d = envelope();
      switch (fault) {
        case 'kind':
          d['kind'] = 'autonomous';
        case 'text mismatch':
          d['reply'] = 'fake';
        case 'missing details':
          d['safety_details'] = null;
        case 'escalation':
          d['escalation_triggered'] = true;
        case 'safety mismatch':
          ((d['safety_details'] as Map)['authoritative_safety']
                  as Map)['status'] =
              'track';
      }
      expect(() => PatientChatReply.fromApi(d, owner: 'a'), throwsA(anything));
    });
  }
  test(
    'empty/long input and duplicate sends do not add unsupported requests',
    () async {
      final f = Fixture()..pendingResponse = Completer();
      await f.run(() async {
        await f.login();
        final chat = PatientChatController(api);
        await chat.send('');
        await chat.send('x' * 1001);
        expect(chat.turns, isEmpty);
        final p = chat.send('first');
        await chat.send('duplicate');
        expect(chat.turns.length, 1);
        f.pendingResponse!.complete(o.jsonResponse(envelope()));
        await p;
        expect(chat.turns.single.response, isNotNull);
        expect(chat.turns.single.receivedAt!.isUtc, true);
        chat.dispose();
        await f.done();
      });
    },
  );
  for (final code in [403, 500, 503]) {
    test('chat $code shows failure and only one explicit retry', () async {
      final f = Fixture()..code = code;
      await f.run(() async {
        await f.login();
        final chat = PatientChatController(api);
        await chat.send('q');
        expect(chat.turns.single.response, isNull);
        await chat.retry(chat.turns.single);
        await chat.retry(chat.turns.single);
        expect(f.requests.where((r) => r.url.path.endsWith('/chat')).length, 2);
        chat.dispose();
        await f.done();
      });
    });
  }
  test(
    'offline/timeout failure and clear never create successful responses',
    () async {
      final f = Fixture()..disconnected = true;
      await f.run(() async {
        await f.login();
        final chat = PatientChatController(api, timeout: Duration.zero);
        await chat.send('q');
        expect(chat.turns.single.response, isNull);
        expect(chat.turns.single.error, isNotNull);
        chat.clear();
        expect(chat.turns, isEmpty);
        chat.dispose();
        await f.done();
      });
    },
  );
  for (final action in ['switch', 'logout', 'revoke', 'clear', 'dispose']) {
    test('$action discards pending response', () async {
      final f = Fixture()..pendingResponse = Completer();
      await f.run(() async {
        await f.login();
        final chat = PatientChatController(api);
        final p = chat.send('q');
        await Future<void>.delayed(Duration.zero);
        if (action == 'switch') {
          await f.login('b');
        } else if (action == 'logout') {
          await api.logout();
        } else if (action == 'revoke') {
          f.noConsent = true;
          await f.state.account.hydrate(reuseConsent: false);
        } else if (action == 'clear') {
          chat.clear();
        } else {
          chat.dispose();
        }
        f.pendingResponse!.complete(o.jsonResponse(envelope()));
        await p;
        expect(chat.turns, isEmpty);
        if (action != 'dispose') chat.dispose();
        await f.done();
      });
    });
  }
  test(
    'old401 cannot invalidate reused B token; current401 clears temporary turns',
    () async {
      final f = Fixture()..pendingResponse = Completer();
      await f.run(() async {
        await f.login();
        final chat = PatientChatController(api);
        final p = chat.send('q');
        await Future<void>.delayed(Duration.zero);
        await f.login('b');
        f.pendingResponse!.complete(o.jsonResponse({}, 401));
        await p;
        expect(api.observationOwner, 'b');
        chat.dispose();
        f.pendingResponse = null;
        f.code = 401;
        final next = PatientChatController(api);
        await next.send('q');
        expect(api.isAuthenticated, false);
        expect(next.turns, isEmpty);
        next.dispose();
        await f.done();
      });
    },
  );
  test(
    'temporary history is bounded and never included in the next POST',
    () async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        final chat = PatientChatController(api);
        for (var i = 0; i < 21; i++) {
          await chat.send('question $i');
        }
        expect(chat.turns.length, 20);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/chat')).length,
          20,
        );
        chat.dispose();
        final fresh = PatientChatController(api);
        expect(fresh.turns, isEmpty);
        fresh.dispose();
        await f.done();
      });
    },
  );
  for (final theme in ['light', 'dark', 'large light', 'large dark']) {
    testWidgets(
      'chat $theme has honest memory, whole reply and accessible composer',
      (t) async {
        final f = Fixture();
        await f.run(() async {
          await f.login();
          await h.mount(
            t,
            f,
            SkinAssistantScreen(state: f.state),
            dark: theme.contains('dark'),
            reduced: true,
            scale: theme.contains('large') ? 2 : 1,
            width: theme.contains('large') ? 320 : 390,
          );
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('assistantInput')),
            'What changed?',
          );
          await t.tap(find.byTooltip('Send message'));
          await t.pumpAndSettle();
          expect(find.text('Synthetic canonical assistance.'), findsOneWidget);
          expect(
            find.textContaining('Received on this device'),
            findsOneWidget,
          );
          expect(find.text('Memory enabled'), findsNothing);
          expect(find.text('Thinking…'), findsNothing);
          expect(find.byType(AssistanceSafetySnapshot), findsOneWidget);
          expect(t.takeException(), isNull);
          await f.login('b');
          await t.pumpAndSettle();
          expect(find.text('Session ended'), findsOneWidget);
          await f.done(t);
        });
      },
    );
  }
  testWidgets('chat failure does not insert a local diagnosis', (t) async {
    final f = Fixture()..code = 503;
    await f.run(() async {
      await f.login();
      await h.mount(t, f, SkinAssistantScreen(state: f.state));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('assistantInput')),
        'my routine is worse',
      );
      await t.tap(find.byTooltip('Send message'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('server assistant is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('No reply confirmed.'), findsOneWidget);
      expect(find.text('Synthetic canonical assistance.'), findsNothing);
      await f.done(t);
    });
  });
  testWidgets(
    'whole long reply is selectable and clear affects only device view',
    (t) async {
      final f = Fixture()
        ..body = envelope(message: 'Synthetic long response. ' * 300);
      await f.run(() async {
        await f.login();
        await h.mount(t, f, SkinAssistantScreen(state: f.state), reduced: true);
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('assistantInput')), 'question');
        await t.testTextInput.receiveAction(TextInputAction.send);
        await t.pumpAndSettle();
        expect(find.text('Synthetic long response. ' * 300), findsOneWidget);
        await t.tap(find.byTooltip('Clear conversation'));
        await t.pumpAndSettle();
        expect(find.text('Synthetic long response. ' * 300), findsNothing);
        expect(
          f.requests.where(
            (r) =>
                r.url.path.contains('history') || r.url.path.contains('delete'),
          ),
          isEmpty,
        );
        await f.done(t);
      });
    },
  );
}
