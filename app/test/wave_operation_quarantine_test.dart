import 'dart:convert';
import 'package:dermaire_app/integration/operation_identity.dart';
import 'package:dermaire_app/messaging/messaging_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'wave_messaging_test.dart' as f;

class ReadDeniedWire extends f.MessageWire {
  ReadDeniedWire({super.doctor});
  int? readStatus;
  @override
  Future<http.Response> call(http.Request request) {
    expectHost(request);
    if (request.method == 'GET' &&
        request.url.path.endsWith('/messages') &&
        readStatus != null) {
      return Future.value(http.Response('{}', readStatus!));
    }
    return super.call(request);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api.baseUrl = 'https://flutter-tests.invalid/api/v1';
    await api.init();
  });
  tearDown(() => api.init());
  for (final doctor in [false, true]) {
    for (final status in [401, 403, 503]) {
      test(
        'private read$status retains original identity doctor=$doctor',
        () async {
          final w = ReadDeniedWire(doctor: doctor);
          await w.run(() async {
            await w.login();
            final c = ConversationController(w.model);
            await c.refresh();
            w.mode = 'lost before';
            await c.send('SENSITIVE MESSAGE NEVER IN METADATA');
            final key = c.pending!.key;
            w.readStatus = status;
            await c.refresh();
            expect(c.messages, isEmpty);
            if (status == 401) {
              expect(api.isAuthenticated, isFalse);
              expect(api.integrationIntents, isEmpty);
              expect(
                api.quarantinedOperations,
                isEmpty,
              ); // no unauthenticated disclosure
              w.readStatus = null;
              await w.login();
              final handle = api.quarantinedOperations.single;
              expect(handle.key, key);
              expect(handle.scope['access_id'], 'grant-1');
              expect(
                jsonEncode(handle.toJson()),
                isNot(contains('SENSITIVE MESSAGE')),
              );
              final before = w.posts;
              final replacement = ConversationController(w.model);
              await replacement.refresh();
              await replacement.send('replacement forbidden');
              expect(w.posts, before);
              expect(
                replacement.error,
                contains('original operation remains unresolved'),
              );
              replacement.dispose();
              // Another identity cannot see or use this metadata.
              final original = w.owner;
              w.owner = 'other-account';
              await w.login();
              expect(api.quarantinedOperations, isEmpty);
              w.owner = original;
              await w.login();
              expect(api.quarantinedOperations.single.key, key);
              await api.logout();
              await w.login();
              expect(api.quarantinedOperations, isEmpty);
            } else {
              expect(c.pending!.key, key);
            }
            c.dispose();
          });
        },
      );
    }
  }
  test('operation metadata rejects extra private fields and unsafe paths', () {
    final identity = OperationIdentity(
      owner: 'patient-1',
      role: 'patient',
      path: 'products',
      receiptPath: 'products/attempts',
      key: 'a' * 48,
      fingerprint: 'b' * 64,
    );
    expect(OperationIdentity.fromJson(identity.toJson()).key, identity.key);
    expect(
      () => OperationIdentity.fromJson({
        ...identity.toJson(),
        'message': 'private',
      }),
      throwsFormatException,
    );
    expect(
      () => OperationIdentity(
        owner: 'patient-1',
        role: 'patient',
        path: 'https://production.invalid',
        receiptPath: 'products/attempts',
        key: 'a' * 48,
        fingerprint: 'b' * 64,
      ),
      throwsFormatException,
    );
    expect(
      () => OperationIdentity(
        owner: 'patient-1',
        role: 'patient',
        path: 'products',
        receiptPath: 'products/attempts',
        key: 'a' * 48,
        fingerprint: 'b' * 64,
        scope: {'raw_note': 'private'},
      ),
      throwsFormatException,
    );
  });
}
