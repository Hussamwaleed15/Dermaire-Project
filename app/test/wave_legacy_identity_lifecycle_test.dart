import 'dart:convert';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_clinical_reviews_test.dart' as f;

class Wire extends f.ClinicalWire {
  int? readStatus;
  @override
  Future<http.Response> call(http.Request request) {
    expectHost(request);
    if (readStatus != null &&
        request.method == 'GET' &&
        (request.url.path.endsWith('/notes') ||
            request.url.path.endsWith('/reviews'))) {
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
  for (final kind in ['notes', 'reviews']) {
    for (final status in [401, 403, 503]) {
      test(
        'legacy $kind original survives read$status without clinical payload restoration',
        () async {
          final w = Wire();
          await w.run(() async {
            final editor = await f.editor(w);
            w.mode = 'lost readback';
            expect(await f.submit(editor.$3, kind), false);
            final original = api.integrationIntents.values.single;
            expect(original.path, 'doctor/patients/patient-1/$kind');
            expect(original.recoveryScope['access_id'], 'grant-patient-1');
            if (kind == 'reviews') {
              expect(original.recoveryScope['expected_sequence'], 0);
            }
            w.readStatus = status;
            w.mode = 'success';
            await editor.$3.refresh();
            expect(editor.$3.notes, isEmpty);
            expect(editor.$3.review, isNull);
            if (status == 401) {
              expect(api.integrationIntents, isEmpty);
              expect(api.pendingDoctorReceipts, isEmpty);
              w.readStatus = null;
              await w.login();
              final identity = api.quarantinedOperations.single;
              expect(identity.key, original.key);
              final encoded = jsonEncode(identity.toJson());
              expect(encoded, isNot(contains('Explicit clinician')));
              expect(encoded, isNot(contains('Clinician review remains')));
              final next = await f.editor(w);
              final posts = w.posts;
              expect(await f.submit(next.$3, kind), false);
              expect(w.posts, posts);
              expect(api.quarantinedOperations.single.key, original.key);
              f.clean(next);
            } else {
              expect(api.integrationIntents.values.single.key, original.key);
            }
            f.clean(editor);
          });
        },
      );
    }
  }
}
