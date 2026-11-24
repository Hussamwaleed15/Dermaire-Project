import 'dart:convert';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_clinical_reviews_test.dart' as c;
import 'wave_q_clinical_receipt_test.dart' as q;

class BindingWire extends q.ClinicalContractWire {
  String? binding = 'explicit';
  int? writeStatus;
  final writesSeen = <http.Request>[];
  @override
  Future<http.Response> call(http.Request request) async {
    final write =
        request.method == 'POST' &&
        (request.url.path.endsWith('/notes') ||
            request.url.path.endsWith('/reviews'));
    if (write) {
      writesSeen.add(request);
      expect(request.headers['Original-Grant-Id'], 'grant-patient-1');
      expect(request.headers.containsKey('Original-Grant-Binding'), false);
      if (writeStatus != null) return http.Response('{}', writeStatus!);
    }
    final response = await super.call(request);
    if (!write || response.statusCode != 201) return response;
    return http.Response(
      response.body,
      response.statusCode,
      headers: {'Original-Grant-Binding': ?binding},
    );
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final kind in ['notes', 'reviews']) {
    for (final status in [401, 403, 404, 409, 410, 412, 503]) {
      test('$kind HTTP $status never confirms a clinical write', () async {
        final w = BindingWire()..writeStatus = status;
        await w.run(() async {
          final v = await c.editor(w);
          try {
            expect(await c.submit(v.$3, kind), false);
            expect(w.writesSeen, hasLength(1));
            expect(v.$3.notes, isEmpty);
            expect(v.$3.review, isNull);
            if (status == 503) {
              final original = v.$3.pending(kind)!;
              expect(await c.submit(v.$3, kind), false);
              expect(v.$3.pending(kind)!.key, original.key);
              expect(w.writesSeen, hasLength(1));
            }
          } finally {
            c.clean(v);
          }
        });
      });
    }
    for (final binding in ['explicit', null, 'legacy-current', 'unexpected']) {
      test('$kind exact request grant and response binding $binding', () async {
        final w = BindingWire()..binding = binding;
        await w.run(() async {
          final v = await c.editor(w);
          try {
            expect(await c.submit(v.$3, kind), binding == 'explicit');
            expect(w.writesSeen, hasLength(1));
            if (binding != 'explicit') {
              final original = v.$3.pending(kind)!;
              expect(original.recoveryScope['access_id'], 'grant-patient-1');
              expect(jsonDecode(w.writesSeen.single.body), original.body);
              expect(
                w.writesSeen.single.headers['Idempotency-Key'],
                original.key,
              );
              expect(await c.submit(v.$3, kind), false);
              expect(w.posts, 1);
              // The durable receipt proves this original grant and payload;
              // it does not retroactively prove a response header was observed.
              expect(await v.$3.refresh(), true);
              expect(w.lookups, 1);
              expect(w.posts, 1);
              expect(v.$3.pending(kind), isNull);
            }
          } finally {
            c.clean(v);
          }
        });
      });
    }
    test(
      '$kind uncertain retry preserves key body grant and requires explicit response',
      () async {
        final w = BindingWire()..loseAfterCommit = true;
        await w.run(() async {
          final v = await c.editor(w);
          try {
            expect(await c.submit(v.$3, kind), false);
            final original = v.$3.pending(kind)!;
            w.binding = null;
            await expectLater(
              api.integrationResource(
                original.path,
                api.sessionGeneration,
                method: 'POST',
                body: original.body,
                key: original.key,
              ),
              throwsA(anything),
            );
            expect(v.$3.pending(kind)!.key, original.key);
            w.binding = 'explicit';
            await api.integrationResource(
              original.path,
              api.sessionGeneration,
              method: 'POST',
              body: original.body,
              key: original.key,
            );
            expect(
              w.writesSeen.map((r) => r.headers['Idempotency-Key']).toSet(),
              {original.key},
            );
            expect(w.writesSeen.map((r) => r.body).toSet(), {
              jsonEncode(original.body),
            });
            expect(w.posts, 1);
          } finally {
            c.clean(v);
          }
        });
      },
    );
  }
}
