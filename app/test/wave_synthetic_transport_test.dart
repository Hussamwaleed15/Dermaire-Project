import 'support/contract_assertions.dart';
import 'dart:async';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api.baseUrl = 'https://flutter-tests.invalid/api/v1';
    await api.init();
  });
  tearDown(() => api.init());
  test(
    'explicit synthetic transport survives engine-style root Zone callbacks',
    () async {
      final w = f.DoctorWire();
      await api.withSyntheticTransport(
        () async {
          await Zone.root.run(w.login);
          expect(api.canReadDoctorWorkspace, true);
          await Zone.root.run(
            () => api.doctorResource('patients', api.sessionGeneration),
          );
          expect(
            w.requests.any((r) => r.url.path.endsWith('/doctor/patients')),
            true,
          );
          expect(
            w.requests.every((r) => r.url.host == 'flutter-tests.invalid'),
            true,
          );
        },
        () => MockClient((request) {
          expectContract(request.url.host, 'flutter-tests.invalid');
          return w.call(request);
        }),
      );
    },
  );
  test('cross-Zone synthetic failure returns to the request caller', () async {
    await api.withSyntheticTransport(
      () async {
        final handled = await Zone.root.run(() async {
          try {
            await api.login(
              email: 'synthetic@example.invalid',
              password: 'synthetic',
            );
            return false;
          } on TimeoutException {
            return true;
          }
        });
        expect(handled, true);
        expect(api.isAuthenticated, false);
      },
      () => MockClient((request) async {
        expectContract(request.url.host, 'flutter-tests.invalid');
        throw TimeoutException('synthetic only');
      }),
    );
  });
  test(
    'synthetic injection refuses non-test base before constructing transport',
    () async {
      var created = 0;
      api.baseUrl = 'https://example.invalid/api/v1';
      await expectLater(
        api.withSyntheticTransport(() async {}, () {
          created++;
          return MockClient(f.DoctorWire().call);
        }),
        throwsStateError,
      );
      expect(created, 0);
    },
  );
  test(
    'host switch inside synthetic scope is rejected before HTTP factory',
    () async {
      var created = 0;
      await api.withSyntheticTransport(
        () async {
          api.baseUrl = 'https://example.com/api/v1';
          await expectLater(
            api.login(
              email: 'synthetic@example.invalid',
              password: 'synthetic',
            ),
            throwsStateError,
          );
        },
        () {
          created++;
          return MockClient(f.DoctorWire().call);
        },
      );
      expect(created, 0);
    },
  );
  test(
    'failed synthetic scope restores injection and disallows nesting',
    () async {
      final w = f.DoctorWire();
      await expectLater(
        api.withSyntheticTransport(() async {
          throw StateError('synthetic');
        }, () => MockClient(w.call)),
        throwsStateError,
      );
      await api.withSyntheticTransport(() async {
        await expectLater(
          api.withSyntheticTransport(() async {}, () => MockClient(w.call)),
          throwsStateError,
        );
        await w.login();
        expect(api.canReadDoctorWorkspace, true);
      }, () => MockClient(w.call));
    },
  );
  test('fake contract predicates stay strict outside a WidgetTester Zone', () {
    Zone.root.run(() {
      expectContract(
        {
          'values': [1, 2],
        },
        {
          'values': [1, 2],
        },
      );
      expectContract('original-key', matches(r'^original-[a-z]+$'));
    });
    expect(
      () => Zone.root.run(() => expectContract('SENSITIVE', 'different')),
      throwsA(
        isA<StateError>().having(
          (e) => e.toString().contains('SENSITIVE'),
          'no payload in diagnostics',
          false,
        ),
      ),
    );
  });
}
