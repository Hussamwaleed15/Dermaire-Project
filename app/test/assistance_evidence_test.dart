import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/assistance/assistance_models.dart';
import 'package:dermaire_app/assistance/assistance_controller.dart';
import 'package:dermaire_app/assistance/assistance_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'clinical_status_test.dart' as c;
import 'observation_test.dart' as o;
import 'private_capture_history_test.dart' as h;

final api = ApiService.instance;
Map<String, dynamic> reply({String mode = 'degraded', bool facts = true}) => {
  'schema_version': 'contextual-ai-1.0',
  'context_version': 'context-1.0',
  'task': 'tracking',
  'message': 'Synthetic canonical assistance.',
  'escalation': 'urgent',
  'authoritative_safety': c.safety(status: 'urgent'),
  'authoritative_clinician': null,
  'metadata': {
    'provider': mode == 'grounded_ai' ? 'synthetic-provider' : null,
    'model': mode == 'grounded_ai' ? 'synthetic-model' : null,
    'configured': mode == 'grounded_ai',
    'invoked': mode == 'grounded_ai',
    'availability': mode == 'grounded_ai' ? 'available' : 'disabled',
    'mode': mode,
    'reason': null,
  },
  'moderation': {
    'provider': 'azure_content_safety',
    'configured': false,
    'invoked': false,
    'state': 'not_invoked',
    'flagged': false,
  },
  'grounded_facts_used': facts
      ? [
          {
            'id': 'f000',
            'source': 'measurement',
            'source_id': 'capture-id',
            'field': 'red_chromaticity_proxy',
            'category': 'system_observed',
            'value': {'value': 0.351, 'unit': 'fraction_0_to_1'},
            'recorded_at': '2026-10-13T12:00:00Z',
            'freshness': 'fresh',
            'confidence': null,
            'provenance': {
              'method_version': 'measurement-1.0',
              'clinical_measurement': false,
            },
          },
        ]
      : [],
  'inferred_points': [],
  'uncertainties': ['Only selected records are available.'],
  'next_steps': ['Synthetic server-provided tracking suggestion.'],
};

class Fixture extends h.Fixture {
  Map<String, dynamic> body = reply();
  int code = 200;
  bool disconnected = false;
  Completer<http.Response>? pendingResponse;
  @override
  Future<http.Response> transport(http.Request r) async {
    if (r.url.path.endsWith('/assistance') || r.url.path.endsWith('/chat')) {
      requests.add(r);
      expectSync(r.headers['Authorization'], 'Bearer reused-synthetic-token');
      expectSync(r.followRedirects, false);
      expectSync(jsonDecode(r.body).keys.toList(), ['message']);
      if (disconnected) throw http.ClientException('Synthetic offline');
      if (pendingResponse != null) return pendingResponse!.future;
      return o.jsonResponse(body, code);
    }
    return super.transport(r);
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
    'actual response maps selected evidence/provenance, mode and uncertainty',
    () {
      final r = AssistanceResponse.fromApi(reply(), owner: 'a');
      expect(r.facts.single.valueJson, contains('fraction_0_to_1'));
      expect(r.facts.single.provenanceJson, contains('measurement-1.0'));
      expect(r.provider.mode, 'degraded');
      expect(r.safety.rawStatus, 'urgent');
      expect(() => r.facts.clear(), throwsUnsupportedError);
    },
  );
  for (final mode in ['degraded', 'grounded_ai', 'safety_guard', 'narrowed']) {
    test('actual mode $mode remains distinct', () {
      expect(
        AssistanceResponse.fromApi(reply(mode: mode), owner: 'a').provider.mode,
        mode,
      );
    });
  }
  for (final fault in [
    'version',
    'context',
    'task',
    'mode',
    'availability',
    'provider claims',
    'duplicate',
    'category',
    'freshness',
    'inference reference',
  ]) {
    test('reject unverified $fault without fabricated response', () {
      final d = reply();
      switch (fault) {
        case 'version':
          d['schema_version'] = 'unknown';
        case 'context':
          d['context_version'] = 'unknown';
        case 'task':
          d['task'] = 'unknown';
        case 'mode':
          (d['metadata'] as Map)['mode'] = 'autonomous';
        case 'availability':
          (d['metadata'] as Map)['availability'] = 'unknown';
        case 'provider claims':
          (d['metadata'] as Map)['mode'] = 'grounded_ai';
        case 'duplicate':
          (d['grounded_facts_used'] as List).add(
            (d['grounded_facts_used'] as List).first,
          );
        case 'category':
          ((d['grounded_facts_used'] as List).first as Map)['category'] =
              'ai_inferred';
        case 'freshness':
          ((d['grounded_facts_used'] as List).first as Map)['freshness'] =
              'unknown-new';
        case 'inference reference':
          d['inferred_points'] = [
            {
              'category': 'ai_inferred',
              'statement': 'Synthetic inference',
              'evidence_ids': ['not-selected'],
            },
          ];
      }
      expect(
        () => AssistanceResponse.fromApi(d, owner: 'a'),
        throwsFormatException,
      );
    });
  }
  test(
    'unknown string source is preserved as unknown, not labeled confirmed clinical evidence',
    () {
      final d = reply();
      ((d['grounded_facts_used'] as List).first as Map)['source'] =
          'future-source';
      final f = AssistanceResponse.fromApi(d, owner: 'a').facts.single;
      expect(f.knownSource, false);
      expect(f.source, 'future-source');
    },
  );
  test(
    'missing evidence does not fabricate facts; clinician authored reference is separate',
    () {
      final d = reply(facts: false)
        ..['authoritative_clinician'] = {
          'id': 'decision',
          'sequence': 2,
          'recommendation': 'urgent',
          'provenance': 'clinician_authored',
        };
      final r = AssistanceResponse.fromApi(d, owner: 'a');
      expect(r.facts, isEmpty);
      expect(r.clinician!.sequence, 2);
    },
  );
  for (final code in [403, 422, 500, 503]) {
    test('status $code allows only one explicit retry', () async {
      final f = Fixture()..code = code;
      await f.run(() async {
        await f.login();
        final ctrl = AssistanceController(api);
        await ctrl.send('question');
        expect(ctrl.response, isNull);
        expect(ctrl.canRetry, true);
        await ctrl.retry();
        expect(ctrl.canRetry, false);
        await ctrl.retry();
        expect(
          f.requests.where((r) => r.url.path.endsWith('/assistance')).length,
          2,
        );
        ctrl.dispose();
        await f.done();
      });
    });
  }
  test(
    'duplicate pending sends and invalid input cause no extra POST',
    () async {
      final f = Fixture()..pendingResponse = Completer();
      await f.run(() async {
        await f.login();
        final ctrl = AssistanceController(api);
        await ctrl.send('');
        await ctrl.send('x' * 1001);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/assistance')),
          isEmpty,
        );
        final pending = ctrl.send('question');
        await ctrl.send('question');
        f.pendingResponse!.complete(o.jsonResponse(reply()));
        await pending;
        expect(ctrl.response, isNotNull);
        expect(
          f.requests.where((r) => r.url.path.endsWith('/assistance')).length,
          1,
        );
        ctrl.dispose();
        await f.done();
      });
    },
  );
  for (final action in ['logout', 'switch', 'revoke']) {
    test('$action rejects late private response', () async {
      final f = Fixture()..pendingResponse = Completer();
      await f.run(() async {
        await f.login();
        final ctrl = AssistanceController(api);
        final pending = ctrl.send('question');
        await Future<void>.delayed(Duration.zero);
        if (action == 'logout') {
          await api.logout();
        } else if (action == 'switch') {
          await f.login('b');
        } else {
          f.noConsent = true;
          await f.state.account.hydrate(reuseConsent: false);
        }
        f.pendingResponse!.complete(o.jsonResponse(reply()));
        await pending;
        expect(ctrl.response, isNull);
        expect(ctrl.question, isNull);
        ctrl.dispose();
        await f.done();
      });
    });
  }
  test(
    'old401 ignores reused token in B; current401 expires session',
    () async {
      final f = Fixture()..pendingResponse = Completer();
      await f.run(() async {
        await f.login();
        final ctrl = AssistanceController(api);
        final p = ctrl.send('q');
        await Future<void>.delayed(Duration.zero);
        await f.login('b');
        f.pendingResponse!.complete(o.jsonResponse({}, 401));
        await p;
        expect(api.observationOwner, 'b');
        ctrl.dispose();
        f.pendingResponse = null;
        f.code = 401;
        final b = AssistanceController(api);
        await b.send('q');
        expect(api.isAuthenticated, false);
        expect(b.response, isNull);
        b.dispose();
        await f.done();
      });
    },
  );
  test(
    'offline and timeout never create successful assistant output',
    () async {
      final f = Fixture()..disconnected = true;
      await f.run(() async {
        await f.login();
        final ctrl = AssistanceController(api, timeout: Duration.zero);
        await ctrl.send('q');
        expect(ctrl.response, isNull);
        expect(ctrl.error, isNotNull);
        ctrl.dispose();
        await f.done();
      });
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      'evidence disclosure dark=$dark large/reduced is truthful and accessible',
      (t) async {
        final f = Fixture();
        await f.run(() async {
          await f.login();
          await h.mount(
            t,
            f,
            Scaffold(
              body: SingleChildScrollView(
                child: AssistanceEvidence(
                  response: AssistanceResponse.fromApi(reply(), owner: 'a'),
                ),
              ),
            ),
            dark: dark,
            reduced: true,
            scale: 2,
            width: 320,
          );
          await t.pumpAndSettle();
          expect(
            find.text('Safety Engine · response snapshot'),
            findsOneWidget,
          );
          expect(find.text('Synthetic canonical assistance.'), findsOneWidget);
          await t.ensureVisible(
            find.text('Why this response? Supporting information'),
          );
          await t.pumpAndSettle();
          await t.tap(find.text('Why this response? Supporting information'));
          await t.pumpAndSettle();
          expect(find.textContaining('Record: capture-id'), findsOneWidget);
          expect(
            find.textContaining(
              'complete context/source availability inventory is not returned',
            ),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await f.done(t);
        });
      },
    );
  }
  testWidgets(
    'real assistance screen sends only question, preserves safety and clears on switch',
    (t) async {
      final f = Fixture();
      await f.run(() async {
        await f.login();
        await h.mount(t, f, ContextualAssistanceScreen(state: f.state));
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.byKey(const Key('assistanceQuestion')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await t.enterText(
          find.byKey(const Key('assistanceQuestion')),
          'question',
        );
        await t.ensureVisible(find.byKey(const Key('requestAssistance')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('requestAssistance')));
        await t.pumpAndSettle();
        expect(
          f.requests.where((r) => r.url.path.endsWith('/assistance')).length,
          1,
        );
        await f.login('b');
        await t.pumpAndSettle();
        expect(find.text('Session ended'), findsOneWidget);
        expect(find.byType(AssistanceEvidence), findsNothing);
        await f.done(t);
      });
    },
  );
}
