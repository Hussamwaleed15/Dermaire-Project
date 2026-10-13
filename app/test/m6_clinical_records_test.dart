import 'dart:async';
import 'package:dermaire_app/access_control.dart';
import 'package:dermaire_app/doctor/doctor_controller.dart';
import 'package:dermaire_app/doctor/doctor_connection.dart';
import 'package:dermaire_app/doctor/doctor_evidence_models.dart';
import 'package:dermaire_app/doctor/doctor_evidence_ui.dart';
import 'package:dermaire_app/doctor/doctor_records_controller.dart';
import 'package:dermaire_app/capture/private_capture_image.dart';
import 'package:dermaire_app/dermaire_theme.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'm6_doctor_fixture.dart' as f;
import 'clinical_status_test.dart' as c;
import 'guided_capture_test.dart' as g;

final api = ApiService.instance;
Map<String, dynamic> item({
  String source = 'capture',
  String id = 'capture-1',
  String field = 'record',
  String category = 'system_observed',
  Map<String, dynamic>? data,
  Map<String, dynamic>? provenance,
}) => {
  'id': '$source:$id:$field',
  'source': source,
  'source_id': id,
  'field': field,
  'category': category,
  'recorded_at': '2026-10-01T12:00:00Z',
  'provenance': provenance ?? {},
  'data':
      data ??
      {
        'state': 'accepted',
        'storage': 'azure_blob',
        'view': 'front',
        'source': 'camera',
        'server_version': 1,
      },
};

class EvidenceWire extends f.DoctorWire {
  String mode = 'success';
  int total = 1, imageReads = 0;
  Completer<http.Response>? timelineDelay;
  Completer<http.Response>? imageDelay;
  Map<String, dynamic> page(int offset) => {
    'schema_version': 'doctor-timeline-2.0',
    'built_at': '2026-10-14T12:00:00Z',
    'items': List.generate(
      (total - offset).clamp(0, 100),
      (i) => item(id: 'capture-${offset + i + 1}'),
    ),
    'total': total,
    'offset': offset,
    'limit': 100,
    'next_offset': offset + 100 < total ? offset + 100 : null,
    'unknowns': ['No complete medical history'],
    'limitations': ['Derived context is bounded'],
    'derived_source_availability': {
      'personal_skin_model': {
        'state': 'partial',
        'included': 1,
        'truncated': true,
      },
    },
    'safety': c.safety(status: 'urgent'),
  };
  @override
  Future<http.Response> call(http.Request request) async {
    expectHost(request);
    if (request.url.path.endsWith('/timeline')) {
      requests.add(request);
      if (timelineDelay != null) return timelineDelay!.future;
      if (['401', '403', '404', '500'].contains(mode)) {
        return f.json({}, int.parse(mode));
      }
      if (mode == 'offline') throw http.ClientException('synthetic');
      if (mode == 'timeout') throw TimeoutException('synthetic');
      final offset = int.parse(request.url.queryParameters['offset']!);
      final value = page(offset);
      if (mode == 'schema') value['schema_version'] = 'future';
      if (mode == 'overlap' && offset > 0) (value['items'] as List)[0] = item();
      return f.json(value);
    }
    if (request.url.path.endsWith('/image')) {
      requests.add(request);
      imageReads++;
      if (imageDelay != null) return imageDelay!.future;
      if (['image401', 'image403', 'image500'].contains(mode)) {
        return f.json({}, int.parse(mode.substring(5)));
      }
      return http.Response.bytes(
        g.pngBytes(),
        200,
        headers: {'content-type': mode == 'mime' ? 'text/html' : 'image/png'},
      );
    }
    return super.call(request);
  }
}

Future<
  (
    DoctorWorkspaceController,
    DoctorConnectionController,
    DoctorRecordsController,
  )
>
records(EvidenceWire wire) async {
  await wire.login();
  final parent = DoctorWorkspaceController(
    AccessSession(userId: wire.owner, role: UserRole.doctor),
  );
  await parent.refresh();
  final connection = DoctorConnectionController(parent, wire.patient);
  await connection.refresh();
  final read = DoctorRecordsController(connection);
  await read.refresh();
  return (parent, connection, read);
}

void cleanup(
  (
    DoctorWorkspaceController,
    DoctorConnectionController,
    DoctorRecordsController,
  )
  values,
) {
  values.$3.dispose();
  values.$2.dispose();
  values.$1.dispose();
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());
  for (final mode in [
    'success',
    '401',
    '403',
    '404',
    '500',
    'offline',
    'timeout',
    'schema',
  ]) {
    test(
      'doctor evidence $mode never becomes false empty or permission',
      () async {
        final wire = EvidenceWire()..mode = mode;
        await wire.run(() async {
          final values = await records(wire);
          expect(values.$3.confirmed, mode == 'success');
          expect(values.$3.items.length, mode == 'success' ? 1 : 0);
          expect(wire.imageReads, 0);
          if (mode == '500') {
            wire.mode = 'success';
            expect(await values.$3.refresh(), true);
          }
          cleanup(values);
        });
      },
    );
  }
  for (final mode in ['normal', 'overlap', 'changed total']) {
    test(
      'timeline actual paging $mode does not claim a stable snapshot',
      () async {
        final wire = EvidenceWire()..total = 101;
        await wire.run(() async {
          final values = await records(wire);
          expect(values.$3.items.length, 100);
          expect(values.$3.hasMore, true);
          if (mode == 'overlap') wire.mode = 'overlap';
          if (mode == 'changed total') wire.total = 102;
          await values.$3.loadMore();
          expect(values.$3.confirmed, mode == 'normal');
          expect(values.$3.items.length, mode == 'normal' ? 101 : 0);
          expect(
            wire.requests.any((r) => r.url.queryParameters['offset'] == '100'),
            true,
          );
          cleanup(values);
        });
      },
    );
  }
  for (final mode in [
    'logout',
    'account switch',
    'patient switch',
    'dispose',
  ]) {
    test('late timeline $mode cannot restore sensitive records', () async {
      final wire = EvidenceWire();
      await wire.run(() async {
        final values = await records(wire);
        wire.timelineDelay = Completer();
        final reading = values.$3.refresh();
        await Future<void>.delayed(Duration.zero);
        if (mode == 'logout') await api.logout();
        if (mode == 'account switch') {
          await api.init();
          wire.owner = 'doctor-b';
          await wire.login();
        }
        if (mode == 'patient switch') values.$1.selectPatient('not-authorized');
        if (mode == 'dispose') values.$3.dispose();
        wire.timelineDelay!.complete(f.json(wire.page(0)));
        expect(await reading, false);
        expect(values.$3.items, isEmpty);
        if (mode != 'dispose') values.$3.dispose();
        values.$2.dispose();
        values.$1.dispose();
      });
    });
  }
  for (final mode in ['success', 'mime', 'image401', 'image403', 'image500']) {
    test('explicit doctor image $mode uses guarded real image route', () async {
      final wire = EvidenceWire()..mode = mode;
      await wire.run(() async {
        final values = await records(wire);
        final images = PrivateCaptureImages(
          api,
          reader: values.$3.readImage,
          authorization: (_) => values.$3.confirmed,
          scope: values.$3,
        );
        await expectLater(
          values.$3.readImage('foreign-capture', api.sessionGeneration),
          throwsA(isA<ApiException>()),
        );
        expect(wire.imageReads, 0);
        final result = images.load(
          'capture-1',
          api.sessionGeneration,
          1600,
          active: () => true,
        );
        if (mode == 'success') {
          final lease = await result;
          expect(lease.image, isNotNull);
          values.$2.invalidate();
          expect(lease.image, isNull);
        } else {
          await expectLater(result, throwsA(anything));
        }
        final request = wire.requests.firstWhere(
          (r) => r.url.path.endsWith('/image'),
        );
        expect(request.url.path, '/api/v1/captures/capture-1/image');
        expect(request.url.query, isEmpty);
        expect(request.headers['Authorization'], 'Bearer reused-doctor-token');
        images.dispose();
        cleanup(values);
      });
    });
  }
  test(
    'late doctor image bytes after patient selection cannot decode',
    () async {
      final wire = EvidenceWire();
      await wire.run(() async {
        final values = await records(wire);
        final images = PrivateCaptureImages(
          api,
          reader: values.$3.readImage,
          authorization: (_) => values.$3.confirmed,
          scope: values.$3,
        );
        wire.imageDelay = Completer();
        final result = images.load(
          'capture-1',
          api.sessionGeneration,
          1600,
          active: () => true,
        );
        final assertion = expectLater(result, throwsA(anything));
        await Future<void>.delayed(Duration.zero);
        values.$1.selectPatient('not-authorized');
        wire.imageDelay!.complete(
          http.Response.bytes(
            g.pngBytes(),
            200,
            headers: {'content-type': 'image/png'},
          ),
        );
        await assertion;
        expect(images.decodedPixels, 0);
        images.dispose();
        cleanup(values);
      });
    },
  );
  test('PSM colon source identities and unknown sources stay honest', () {
    final p = DoctorTimelineItem.fromApi(
      item(
        source: 'personal_skin_model',
        id: 'finding:subject',
        field: 'value',
        category: 'deterministic_derived',
        data: {'value': 'Recorded context'},
      ),
      'patient-1',
    );
    expect(p.lines, contains('Recorded projection: Recorded context'));
    final unknown = DoctorTimelineItem.fromApi(
      item(source: 'future', data: {'diagnosis': 'secret unsupported'}),
      'patient-1',
    );
    expect(unknown.lines.join(), isNot(contains('secret unsupported')));
  });
  test('measurement fraction provenance remains nonclinical and exact', () {
    final p = DoctorTimelineItem.fromApi(
      item(
        source: 'measurement',
        id: 'measure-1',
        data: {
          'status': 'measured',
          'capture_id': 'capture-1',
          'values': {
            'red_chromaticity_proxy': {
              'status': 'measured',
              'unit': 'fraction_0_to_1',
              'source_capture_id': 'capture-1',
              'method_version': 'image-1',
              'value': 0.2,
            },
          },
        },
        provenance: {'clinical_measurement': false, 'algorithm': 'image-1'},
      ),
      'patient-1',
    );
    expect(p.lines.join(), contains('0.2 fraction'));
    expect(p.lines.join(), isNot(contains('20%')));
    expect(p.lines.join(), contains('texture_contrast_proxy: unavailable'));
  });
  test('manual tracking does not turn missing values into zero', () {
    final p = DoctorTimelineItem.fromApi(
      item(
        source: 'checkin',
        field: 'tracking_scores',
        category: 'patient_reported',
        data: {'redness': 70},
        provenance: {
          'clinical_measurement': false,
          'measurement_source': 'manual',
        },
      ),
      'patient-1',
    );
    expect(p.lines.join(), contains('redness tracking score: 70'));
    expect(p.lines.join(), contains('hydration tracking score: Not reported'));
  });
  test('evaluation numbers do not invent units or efficacy', () {
    final p = DoctorTimelineItem.fromApi(
      item(
        source: 'experiment_evaluation',
        category: 'deterministic_derived',
        data: {
          'result': {'label': 'unclear', 'observed_change': 0.3},
        },
      ),
      'patient-1',
    );
    expect(p.lines.join(), contains('unspecified units'));
    expect(p.lines.join(), contains('not causality'));
    expect(p.lines.join(), isNot(contains('30%')));
  });
  for (final mode in [
    'foreign profile',
    'wrong category',
    'future date',
    'duplicate ID',
    'wrong offset',
    'unknown availability',
  ]) {
    test('malformed timeline $mode cannot be displayed', () {
      final wire = EvidenceWire();
      final data = wire.page(0);
      switch (mode) {
        case 'foreign profile':
          data['items'] = [item(source: 'profile', id: 'other-patient')];
        case 'wrong category':
          data['items'] = [item(category: 'diagnosis')];
        case 'future date':
          (data['items'] as List).first['recorded_at'] = '2090-10-01T00:00:00Z';
        case 'duplicate ID':
          data['items'] = [item(), item()];
          data['total'] = 2;
        case 'wrong offset':
          data['offset'] = 10;
        case 'unknown availability':
          data['derived_source_availability'] = {
            'psm': {'state': 'complete'},
          };
      }
      expect(
        () => DoctorTimelinePage.fromApi(data, 'patient-1', 0),
        throwsFormatException,
      );
    });
  }
  for (final dark in [false, true]) {
    testWidgets('evidence theme=$dark at 320px/200% has no automatic images', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final wire = EvidenceWire();
      await wire.run(() async {
        final values = await records(wire);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? DermaireTheme.dark : DermaireTheme.light,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 1000),
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: DoctorEvidenceScreen(connection: values.$2),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Safety Engine'), findsWidgets);
        expect(wire.imageReads, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        cleanup(values);
        await api.logout();
      });
    });
  }
}
