import 'dart:convert';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/home_controller.dart';
import 'package:dermaire_app/clinical/clinical_controller.dart';
import 'package:dermaire_app/psm/psm_controller.dart';
import 'package:dermaire_app/psm/psm_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'clinical_status_test.dart' as clinical;
import 'personal_skin_model_test.dart' as psm;
import 'product_authority_test.dart' as auth;
import 'home_authority_test.dart' as home;
import 'observation_test.dart' as observation;
import 'package:dermaire_app/observations/observation_controller.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() => ApiService.instance.init());
  for (final target in ['safety', 'doctor/review-status']) {
    for (final status in [403, 503]) {
      test(
        '$target denied read differs from temporary failure and recovers',
        () async {
          var code = 200;
          await http.runWithClient(
            () async {
              await auth.login();
              final c = ClinicalController(ApiService.instance);
              try {
                expect(await c.refresh(), true);
                code = status;
                expect(await c.refresh(), false);
                final value = target == 'safety' ? c.safety : c.review;
                expect(value.value == null, status == 403);
                expect(value.retrievedAt == null, status == 403);
                expect(value.stale, status != 403);
                code = 200;
                expect(await c.refresh(), true);
              } finally {
                c.dispose();
              }
            },
            () => MockClient((r) async {
              expect(r.url.host, 'flutter-tests.invalid');
              if (r.url.path.endsWith('/auth/login')) return auth.auth();
              if (r.url.path.endsWith('/users/me')) {
                return http.Response(
                  '{"id":"patient-1","role":"patient","safety_accepted":true}',
                  200,
                );
              }
              if (r.url.path.endsWith('/$target') && code != 200) {
                return http.Response('private body', code);
              }
              return http.Response(
                jsonEncode(
                  r.url.path.endsWith('/safety')
                      ? clinical.safety()
                      : clinical.review(owner: 'patient-1'),
                ),
                200,
              );
            }),
          );
        },
      );
    }
  }
  for (final status in [403, 503]) {
    test(
      'PSM$status never retains safety after denied model authority',
      () async {
        await http.runWithClient(
          () async {
            await auth.login();
            final repo = psm.FakePsmRepository()
              ..value = PersonalSkinModel.fromApi(
                psm.payload(owner: 'patient-1'),
                owner: 'patient-1',
              );
            final c = PsmController(ApiService.instance, repository: repo);
            try {
              await c.refresh();
              expect(c.safety, isNotNull);
              repo.pending = () => Future.error(PsmReadException(status));
              await c.refresh();
              expect(c.model, isNull);
              expect(c.safety == null, status == 403);
              repo.pending = null;
              await c.refresh();
              expect(c.safety, isNotNull);
            } finally {
              c.dispose();
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.url.path.endsWith('/auth/login')) return auth.auth();
            return http.Response(
              '{"id":"patient-1","role":"patient","safety_accepted":true}',
              200,
            );
          }),
        );
      },
    );
  }
  for (final status in [403, 503]) {
    test(
      'Home$status clears denied cache timestamps with honest current availability',
      () async {
        var code = 200;
        await http.runWithClient(
          () async {
            await auth.login();
            final c = HomeController(RemoteHomeRepository());
            try {
              expect(await c.refresh(), true);
              code = status;
              expect(await c.refresh(), false);
              expect(c.current, isNull);
              expect(c.retrievedAt == null, status == 403);
              code = 200;
              expect(await c.refresh(), true);
              expect(c.current, isNotNull);
            } finally {
              c.dispose();
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.url.path.endsWith('/auth/login')) return auth.auth();
            if (r.url.path.endsWith('/users/me')) {
              return http.Response(
                '{"id":"patient-1","role":"patient","safety_accepted":true}',
                200,
              );
            }
            return http.Response(jsonEncode(home.snapshot()), code);
          }),
        );
      },
    );
  }
  for (final status in [403, 503]) {
    test(
      'Observation history$status clears denied content and allows fresh read',
      () async {
        var code = 200;
        await http.runWithClient(
          () async {
            await auth.login();
            final api = ApiService.instance;
            final c = ObservationController(api);
            try {
              expect(
                await c.loadHistory(generation: api.sessionGeneration),
                true,
              );
              code = status;
              expect(
                await c.loadHistory(generation: api.sessionGeneration),
                false,
              );
              expect(c.rows == null, status == 403);
              expect(c.historyRetrievedAt == null, status == 403);
              code = 200;
              expect(
                await c.loadHistory(generation: api.sessionGeneration),
                true,
              );
              expect(c.rows!.single.ownerId, 'patient-1');
            } finally {
              c.dispose();
            }
          },
          () => MockClient((r) async {
            expect(r.url.host, 'flutter-tests.invalid');
            if (r.url.path.endsWith('/auth/login')) return auth.auth();
            if (r.url.path.endsWith('/users/me')) {
              return http.Response(
                '{"id":"patient-1","role":"patient","safety_accepted":true}',
                200,
              );
            }
            return http.Response(
              jsonEncode([observation.record(owner: 'patient-1')]),
              code,
            );
          }),
        );
      },
    );
  }
}
