import 'dart:async';
import 'dart:convert';
import 'package:dermaire_app/clinical/clinical_snapshot.dart';
import 'package:dermaire_app/clinical/clinical_snapshot_ui.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;
import 'clinical_status_test.dart' as clinical;
import 'personal_skin_model_test.dart' as psm;

Map<String, dynamic> packet({bool doctor = false}) {
  final at = DateTime.now().toUtc().toIso8601String();
  final safety = {...clinical.safety(status: 'urgent'), 'evaluated_at': at};
  final model = {
    ...psm.payload(owner: 'patient-1', status: 'no_data'),
    'generated_at': at,
    'safety': safety,
  };
  final home = {
    'as_of': at,
    'date': at.split('T').first,
    'consistency': 'postgresql_repeatable_read_transaction',
    'safety': safety,
    'experiment': null,
    'today_checked_in': false,
    'journal': [],
    'observation_status': {
      'schema_version': 1,
      'day_basis': 'UTC',
      'today_completed': true,
      'recent': [
        {
          'id': 'report-only-1',
          'created_at': at,
          'time_of_day': 'Morning',
          'kind': 'report_only',
          'measurement_available': false,
        },
      ],
    },
  };
  return {
    'schema_version': doctor ? 2 : 1,
    'snapshot_id': 'snapshot-1',
    'patient_id': 'patient-1',
    'evaluated_at': at,
    'consistency': 'postgresql_repeatable_read_transaction',
    'atomic_scope': 'database_rows_visible_in_one_transaction',
    'external_sources': 'not_fetched_not_atomic',
    'replayable': false,
    'clinical_clearance': false,
    'safety': safety,
    'review': {
      ...clinical.review(owner: 'patient-1', evaluation: safety),
      'as_of': at,
      'consistency': 'postgresql_repeatable_read_transaction',
    },
    'home': home,
    'personal_skin_model': model,
    'limitations': [
      'Snapshot correlation is not a replay token.',
      'External images and services are outside this snapshot.',
    ],
    if (doctor) ...{
      'reader_id': 'doctor-1',
      'reader_role': 'doctor',
      'access_id': 'grant-patient-1',
      'projection_visibility': 'doctor_review_with_patient_home_and_psm',
    },
  };
}

class SnapshotWire extends f.DoctorWire {
  SnapshotWire({bool doctor = false}) {
    owner = doctor ? 'doctor-1' : 'patient-1';
    role = doctor ? 'doctor' : 'patient';
    data = packet(doctor: doctor);
  }
  late Map<String, dynamic> data;
  bool alternateGrant = false;
  @override
  Map<String, dynamic> grant([String status = 'active']) => {
    ...super.grant(status),
    if (alternateGrant) 'id': 'new-grant',
  };
  int status = 200;
  int snapshots = 0;
  bool offline = false;
  Completer<http.Response>? delayed;
  @override
  Future<http.Response> call(http.Request r) async {
    expectHost(r);
    if (r.url.path.contains('/clinical-snapshot')) {
      requests.add(r);
      snapshots++;
      if (offline) throw http.ClientException('synthetic offline');
      return delayed?.future ?? f.json(data, status);
    }
    return super.call(r);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  test(
    'one transaction keeps report-only completion separate from measurement',
    () {
      final value = ClinicalSnapshot(
        packet(),
        owner: 'patient-1',
        role: 'patient',
      );
      expect(value.observationCompleted, isTrue);
      expect(value.home['today_checked_in'], false);
      expect(value.home['journal'], isEmpty);
      expect(value.model.generatedAt, value.asOf);
      expect(value.safety.rawStatus, 'urgent');
      expect(value.patientReview!.safety.evaluatedAt, value.asOf);
    },
  );
  for (final malformed in [
    'owner',
    'schema',
    'clock',
    'home clock',
    'model clock',
    'safety',
    'clearance',
    'external',
    'atomic',
    'observation',
    'future report',
    'future measurement',
    'completion',
    'psm',
  ]) {
    test('snapshot $malformed fails closed', () {
      final v = jsonDecode(jsonEncode(packet())) as Map<String, dynamic>;
      switch (malformed) {
        case 'owner':
          v['patient_id'] = 'foreign';
        case 'schema':
          v['schema_version'] = 2;
        case 'clock':
          v['evaluated_at'] = '2020-01-01T00:00:00Z';
        case 'home clock':
          v['home']['as_of'] = '2020-01-01T00:00:00Z';
        case 'model clock':
          v['personal_skin_model']['generated_at'] = '2020-01-01T00:00:00Z';
        case 'safety':
          v['review']['safety']['status'] = 'track';
        case 'clearance':
          v['clinical_clearance'] = true;
        case 'external':
          v['external_sources'] = 'atomic';
        case 'atomic':
          v['consistency'] = 'multiple_reads_not_atomic_snapshot';
        case 'observation':
          v['home']['observation_status']['day_basis'] = 'local';
        case 'future report':
          v['home']['observation_status']['recent'][0]['created_at'] =
              '2099-01-01T00:00:00Z';
        case 'future measurement':
          v['home']['journal'] = [
            {
              'id': 'future',
              'created_at': '2099-01-01T00:00:00Z',
              'time_of_day': 'Morning',
              'measurement_source': 'manual',
              'hydration_score': 10,
              'texture_score': 10,
              'redness_score': 10,
            },
          ];
        case 'completion':
          v['home']['today_checked_in'] = true;
        case 'psm':
          v['personal_skin_model']['schema_version'] = 99;
      }
      expect(
        () => ClinicalSnapshot(v, owner: 'patient-1', role: 'patient'),
        throwsA(anything),
      );
    });
  }
  test(
    'doctor snapshot requires original grant and actual reader identity',
    () {
      final v = packet(doctor: true);
      expect(
        ClinicalSnapshot(
          v,
          owner: 'doctor-1',
          role: 'doctor',
          grant: 'grant-patient-1',
        ).patient,
        'patient-1',
      );
      expect(
        () => ClinicalSnapshot(
          v,
          owner: 'foreign-doctor',
          role: 'doctor',
          grant: 'grant-patient-1',
        ),
        throwsFormatException,
      );
      expect(
        () => ClinicalSnapshot(
          v,
          owner: 'doctor-1',
          role: 'doctor',
          grant: 'new-grant',
        ),
        throwsFormatException,
      );
      expect(
        () => ClinicalSnapshot(v, owner: 'patient-1', role: 'patient'),
        throwsFormatException,
      );
    },
  );
  test(
    'patient snapshot uses exactly one API bundle with no independent aggregation',
    () async {
      final w = SnapshotWire();
      await w.run(() async {
        await w.login();
        final c = ClinicalSnapshotController();
        await c.refresh();
        expect(c.value!.observationCompleted, isTrue);
        expect(w.snapshots, 1);
        expect(
          w.requests.any(
            (r) =>
                r.url.path.endsWith('/home') ||
                r.url.path.endsWith('/safety') ||
                r.url.path.endsWith('/personal-skin-model'),
          ),
          isFalse,
        );
        c.dispose();
      });
    },
  );
  test(
    'doctor snapshot reauthorizes selected original patient grant',
    () async {
      final w = SnapshotWire(doctor: true);
      await w.run(() async {
        await w.login();
        final parent = DoctorWorkspaceController(
          AccessSession(userId: w.owner, role: UserRole.doctor),
        );
        await parent.refresh();
        final conn = DoctorConnectionController(parent, w.patient);
        await conn.refresh();
        final c = ClinicalSnapshotController(connection: conn);
        await c.refresh();
        expect(c.value!.patient, w.patient);
        conn.invalidate();
        expect(c.value, isNull);
        c.dispose();
        conn.dispose();
        parent.dispose();
      });
    },
  );
  for (final status in [401, 403, 404, 500, 503]) {
    test(
      'snapshot $status shows unavailable, not a reassuring fallback',
      () async {
        final w = SnapshotWire();
        await w.run(() async {
          await w.login();
          final c = ClinicalSnapshotController();
          await c.refresh();
          expect(c.value, isNotNull);
          w.status = status;
          await c.refresh();
          expect(c.value, isNull);
          expect(c.error != null || !c.current, isTrue);
          expect(
            w.requests.any(
              (r) =>
                  r.url.path.endsWith('/home') ||
                  r.url.path.endsWith('/safety'),
            ),
            isFalse,
          );
          c.dispose();
        });
      },
    );
  }
  for (final change in ['hide', 'logout', 'switch', 'old401']) {
    test('late snapshot after $change cannot resurrect private data', () async {
      final w = SnapshotWire();
      await w.run(() async {
        await w.login();
        final c = ClinicalSnapshotController();
        w.delayed = Completer();
        final read = c.refresh();
        await Future<void>.delayed(Duration.zero);
        if (change == 'hide') {
          c.hide();
        } else if (change == 'logout') {
          await api.logout();
        } else {
          w.owner = 'patient-2';
          await w.login();
        }
        w.delayed!.complete(f.json(w.data, change == 'old401' ? 401 : 200));
        await read;
        expect(c.value, isNull);
        if (change == 'old401') expect(api.authenticatedOwner, 'patient-2');
        c.dispose();
      });
    });
  }
  test(
    'replacement grant while doctor snapshot arrives cannot restore original access',
    () async {
      final w = SnapshotWire(doctor: true);
      await w.run(() async {
        await w.login();
        final parent = DoctorWorkspaceController(
          AccessSession(userId: w.owner, role: UserRole.doctor),
        );
        await parent.refresh();
        final conn = DoctorConnectionController(parent, w.patient);
        await conn.refresh();
        final c = ClinicalSnapshotController(connection: conn);
        w.delayed = Completer();
        final future = c.refresh();
        await Future<void>.delayed(Duration.zero);
        w.alternateGrant = true;
        w.delayed!.complete(f.json(w.data));
        await future;
        expect(c.value, isNull);
        expect(conn.confirmed, isFalse);
        c.dispose();
        conn.dispose();
        parent.dispose();
      });
    },
  );
  test('GET-only snapshot transport denies fabricated mutations', () async {
    final w = SnapshotWire();
    await w.run(() async {
      await w.login();
      await expectLater(
        api.integrationResource(
          'clinical-snapshot',
          api.sessionGeneration,
          method: 'POST',
        ),
        throwsArgumentError,
      );
      expect(w.snapshots, 0);
    });
  });
  for (final dark in [false, true]) {
    testWidgets('snapshot is readable 320px 200% dark=$dark', (tester) async {
      final w = SnapshotWire();
      await w.run(() async {
        await w.login();
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const ClinicalSnapshotScreen(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Combined clinical snapshot'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Structured observation on snapshot day: recorded'),
          300,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        expect(
          find.text('Confirmed measurement on snapshot day: not recorded'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await api.logout();
      });
    });
  }
}
