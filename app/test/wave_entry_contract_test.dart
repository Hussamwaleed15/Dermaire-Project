import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/entry/server_entry_metadata.dart';
import 'package:dermaire_app/integration/contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'm6_doctor_fixture.dart' as f;

class WaveWire extends f.DoctorWire {
  String requiredVersion = '2.0',
      acceptedVersion = '1.0',
      policyState = 'outdated';
  bool profileReviewed = false;
  Map<String, dynamic> get consent => {
    'schema_version': 1,
    'state': policyState,
    'required_version': requiredVersion,
    'accepted_version': acceptedVersion,
    'accepted_at': '2026-10-01T12:00:00Z',
    'acceptance_required': policyState != 'current',
    'enforcement_enabled': true,
  };
  @override
  Map<String, dynamic> get profile => {
    ...super.profile,
    'safety_consent': consent,
    'onboarding': {
      'schema_version': 1,
      'review_state': role == 'doctor'
          ? 'not_applicable'
          : profileReviewed
          ? 'reviewed'
          : 'never_reviewed',
      'reviewed_at': profileReviewed ? '2026-10-01T12:00:00Z' : null,
      'optional_data_present': false,
    },
  };
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    if (request.url.path.endsWith('/accept-safety')) {
      requests.add(request);
      if (!request.body.contains('"policy_version":"$requiredVersion"')) {
        return f.json({}, 409);
      }
      acceptedVersion = requiredVersion;
      policyState = 'current';
      return f.json(profile);
    }
    if (request.url.path.endsWith('/users/profile-review')) {
      requests.add(request);
      profileReviewed = true;
      return f.json(profile);
    }
    if (request.url.path.startsWith('/api/v1/messaging/')) {
      requests.add(request);
      return f.json({'items': []});
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
  for (final state in ['missing', 'outdated', 'unknown', 'current']) {
    test('server policy $state overrides accepted Boolean', () async {
      final wire = WaveWire()..policyState = state;
      wire.acceptedVersion = state == 'current' ? '2.0' : '1.0';
      await wire.run(() async {
        await wire.login();
        expect(api.hasConfirmedSafetyAcceptance, state == 'current');
        expect(api.canReadDoctorWorkspace, state == 'current');
        expect(api.requiredSafetyPolicyVersion, '2.0');
      });
    });
  }
  test('accept sends exact GET policy then requires new GET', () async {
    final wire = WaveWire();
    await wire.run(() async {
      await wire.login();
      await api.acceptSafetyTerms();
      expect(api.hasConfirmedSafetyAcceptance, false);
      expect(await api.readSafetyAcceptance(), true);
      expect(wire.requests.last.url.path, endsWith('/users/me'));
    });
  });
  test('patient review completion is server-backed and read back', () async {
    final wire = WaveWire()
      ..role = 'patient'
      ..owner = 'patient-1'
      ..policyState = 'current'
      ..acceptedVersion = '2.0';
    await wire.run(() async {
      await wire.login();
      expect(api.profileReviewRequired, true);
      await api.completeProfileReview();
      expect(api.profileReviewRequired, false);
      expect(wire.requests.last.url.path, endsWith('/users/me'));
    });
  });
  for (final field in [
    'schema_version',
    'required_version',
    'accepted_at',
    'onboarding',
  ]) {
    test('malformed $field never grants entry', () {
      final wire = WaveWire()
        ..policyState = 'current'
        ..acceptedVersion = '2.0';
      final data = wire.profile;
      if (field == 'onboarding') {
        data['onboarding'] = null;
      } else {
        (data['safety_consent'] as Map)[field] = null;
      }
      expect(() => ServerEntryMetadata.fromApi(data), throwsFormatException);
    });
  }
  test('legacy absent metadata remains compatible with existing contract', () {
    expect(ServerEntryMetadata.fromApi(f.DoctorWire().profile).accepted, true);
  });
  test(
    'integration transport denies stale session and foreign paths before HTTP',
    () async {
      final wire = WaveWire()
        ..policyState = 'current'
        ..acceptedVersion = '2.0';
      await wire.run(() async {
        await wire.login();
        final generation = api.sessionGeneration;
        expect(
          (await api.integrationResource(
            'messaging/threads',
            generation,
          )).status,
          200,
        );
        final before = wire.requests.length;
        for (final path in [
          'https://production.invalid',
          'messaging/../users',
          '/messaging/threads',
          'messaging//threads',
        ]) {
          await expectLater(
            api.integrationResource(path, generation),
            throwsArgumentError,
          );
        }
        expect(wire.requests.length, before);
        await api.logout();
        await expectLater(
          api.integrationResource('messaging/threads', generation),
          throwsA(isA<IntegrationFailure>()),
        );
      });
    },
  );
  test('intent preserves original body/key across uncertainty', () {
    final intent = PendingIntent(
      path: 'messaging/threads/t/messages',
      attemptPath: 'messaging/threads/t/attempts',
      body: {'body': 'Original'},
    );
    final key = intent.key;
    intent.uncertain = true;
    expect(intent.key, key);
    expect(key, matches(RegExp(r'^[a-f0-9]{48}$')));
    expect(() => intent.body['body'] = 'Changed', throwsUnsupportedError);
  });
}
