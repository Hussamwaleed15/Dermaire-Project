import 'dart:async';
import 'package:dermaire_app/capture/capture_history_controller.dart';
import 'package:dermaire_app/capture/capture_history_models.dart';
import 'package:dermaire_app/capture/capture_history_screen.dart';
import 'package:dermaire_app/capture/guided_capture_models.dart';
import 'package:dermaire_app/capture/measurement_evidence.dart';
import 'package:dermaire_app/capture/measurement_history_screen.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'guided_capture_test.dart' as g;
import 'private_capture_history_test.dart' as h;

CaptureMeasurement metric(String id, {String status = 'measured'}) =>
    CaptureMeasurement.fromApi(
      g.measurement(id: id, status: status),
      captureId: id,
    );
GuidedCaptureRecord capture(
  String id, {
  String state = 'accepted',
  String owner = 'a',
}) => GuidedCaptureRecord.fromApi(
  g.receipt(id: id, owner: owner, state: state, inline: false),
  owner: owner,
);

class Repository implements CaptureHistoryRepository {
  List<GuidedCaptureRecord> rows = List.generate(
    12,
    (i) => capture('capture-${i.toString().padLeft(2, '0')}'),
  );
  Future<List<GuidedCaptureRecord>> Function()? list;
  Future<CaptureMeasurement> Function(String)? read;
  Future<GuidedCaptureRecord> Function(String)? detail;
  final ids = <String>[];
  @override
  Future<List<GuidedCaptureRecord>> history(int generation) async =>
      list == null ? rows : await list!();
  @override
  Future<GuidedCaptureRecord> record(String id, int generation) async =>
      detail == null ? rows.firstWhere((r) => r.id == id) : await detail!(id);
  @override
  Future<CaptureMeasurement> measurement(String id, int generation) async {
    ids.add(id);
    return read == null ? metric(id) : await read!(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ApiService.instance.init();
  });
  tearDown(() async {
    await ApiService.instance.init();
  });
  test(
    'real controller reads two nonempty bounded pages then final receipt window',
    () async {
      final f = h.Fixture();
      final r = Repository();
      await f.run(() async {
        await f.login();
        final c = MeasurementHistoryController(h.api, repository: r);
        await c.refresh();
        expect(c.visibleCount, 5);
        expect(r.ids, [
          'capture-11',
          'capture-10',
          'capture-09',
          'capture-08',
          'capture-07',
        ]);
        await c.loadMore();
        expect(c.visibleCount, 10);
        expect(r.ids.length, 10);
        expect(
          c.visibleRecords.map((x) => x.id),
          List.generate(
            10,
            (i) => 'capture-${(11 - i).toString().padLeft(2, '0')}',
          ),
        );
        await c.loadMore();
        expect(c.visibleCount, 12);
        expect(c.hasMore, false);
        await c.loadMore();
        expect(r.ids.length, 12);
        expect(f.requests.where((x) => x.url.path.endsWith('/image')), isEmpty);
        c.dispose();
        await f.done();
      });
    },
  );
  test(
    'missing, unsupported, rejected and unavailable rows; retry only failed GET',
    () async {
      final f = h.Fixture();
      final r = Repository()
        ..rows = [
          capture('z'),
          capture('y'),
          capture('x', state: 'rejected'),
          capture('w'),
        ];
      r.read = (id) async {
        if (id == 'z') throw const PrivateCaptureException(404);
        if (id == 'y') throw const FormatException('bad');
        return metric(id, status: 'unavailable');
      };
      await f.run(() async {
        await f.login();
        final c = MeasurementHistoryController(h.api, repository: r);
        await c.refresh();
        expect(c.failures['z'], contains('No recorded measurement'));
        expect(c.failures['y'], contains('Unsupported'));
        expect(r.ids, ['z', 'y', 'w']);
        expect(c.measurements['w']!.metrics.values.first.value, isNull);
        r.read = (id) async => metric(id);
        await c.retry('z');
        expect(c.failures.containsKey('z'), false);
        expect(r.ids, ['z', 'y', 'w', 'z']);
        await c.retry('w');
        expect(r.ids.length, 4);
        c.dispose();
        await f.done();
      });
    },
  );
  for (final code in [401, 403, 409, 500]) {
    test('read-only measurement error $code is explicit', () async {
      final f = h.Fixture();
      final r = Repository()..rows = [capture('a')];
      r.read = (_) async => throw PrivateCaptureException(code);
      await f.run(() async {
        await f.login();
        final c = MeasurementHistoryController(h.api, repository: r);
        await c.refresh();
        expect(c.measurements, isEmpty);
        expect(
          c.failures['a'],
          contains(switch (code) {
            401 => 'Session expired',
            403 => 'Access was denied',
            409 => 'cannot be measured',
            _ => 'Server temporarily',
          }),
        );
        c.dispose();
        await f.done();
      });
    });
  }
  test('timeout ignores late values and permits explicit read retry', () async {
    final f = h.Fixture();
    final r = Repository()..rows = [capture('a')];
    final pending = Completer<CaptureMeasurement>();
    r.read = (_) => pending.future;
    await f.run(() async {
      await f.login();
      final c = MeasurementHistoryController(
        h.api,
        repository: r,
        timeout: const Duration(milliseconds: 5),
      );
      await c.refresh();
      expect(c.failures['a'], contains('timed out'));
      pending.complete(metric('a'));
      await Future<void>.delayed(Duration.zero);
      expect(c.measurements, isEmpty);
      r.read = (id) async => metric(id);
      await c.retry('a');
      expect(c.measurements.keys, ['a']);
      c.dispose();
      await f.done();
    });
  });
  for (final boundary in ['switch', 'dispose', 'refresh']) {
    test(
      'late value cannot cross $boundary or trigger subsequent requests',
      () async {
        final f = h.Fixture();
        final r = Repository();
        final pending = Completer<CaptureMeasurement>();
        r.read = (_) => pending.future;
        await f.run(() async {
          await f.login();
          final c = MeasurementHistoryController(h.api, repository: r);
          final reading = c.refresh();
          await Future<void>.delayed(Duration.zero);
          expect(r.ids.length, 1);
          if (boundary == 'switch') {
            await f.login('b');
          } else if (boundary == 'dispose') {
            c.dispose();
          } else {
            r.rows = [];
            await c.refresh();
          }
          pending.complete(metric('capture-11'));
          await reading;
          expect(c.measurements, isEmpty);
          expect(c.visibleRecords, isEmpty);
          expect(r.ids.length, 1);
          if (!c.disposed) c.dispose();
          await f.done();
        });
      },
    );
  }
  test('overlapping refresh ignores earlier receipt response', () async {
    final f = h.Fixture();
    final r = Repository();
    final old = Completer<List<GuidedCaptureRecord>>();
    r.list = () => old.future;
    await f.run(() async {
      await f.login();
      final c = MeasurementHistoryController(h.api, repository: r);
      final first = c.refresh();
      r.list = () async => [capture('new')];
      await c.refresh();
      old.complete([capture('old')]);
      await first;
      expect(c.measurements.keys, ['new']);
      expect(r.ids, ['new']);
      c.dispose();
      await f.done();
    });
  });
  test('foreign owner and fingerprint mismatch never publish values', () async {
    final f = h.Fixture();
    final r = Repository()..rows = [capture('a', owner: 'b')];
    await f.run(() async {
      await f.login();
      final c = MeasurementHistoryController(h.api, repository: r);
      await c.refresh();
      expect(c.confirmed, false);
      expect(r.ids, isEmpty);
      r.rows = [capture('a')];
      r.read = (id) async {
        final d = g.measurement(id: id);
        (d['capture_quality'] as Map)['request_fingerprint'] = 'f' * 64;
        return CaptureMeasurement.fromApi(d, captureId: id);
      };
      await c.refresh();
      expect(c.measurements, isEmpty);
      expect(c.failures['a'], contains('inconsistent'));
      c.dispose();
      await f.done();
    });
  });
  test('zero, provenance and non-comparability survive without deltas', () {
    final wire = g.measurement();
    ((wire['metrics'] as Map)['red_chromaticity_proxy'] as Map)['value'] = 0;
    wire['comparison'] = {
      'state': 'not_comparable',
      'reason': 'unknown_yaw',
      'deltas': null,
      'previous_comparable_measurement_id': null,
    };
    final m = CaptureMeasurement.fromApi(wire, captureId: 'capture-id');
    expect(m.metrics.values.first.value, 0);
    expect(m.provenance, 'server_computed_from_upload_bytes');
    expect(m.comparison.state, 'not_comparable');
    wire['comparison'] = {
      'state': 'comparable',
      'deltas': {'fake': 99},
    };
    expect(
      CaptureMeasurement.fromApi(
        wire,
        captureId: 'capture-id',
      ).comparison.state,
      'unsupported',
    );
  });
  for (final bad in [
    'unit',
    'method_version',
    'source_capture_id',
    'region',
    'reliability',
    'measured_at',
  ]) {
    test('invalid $bad cannot become numeric historical evidence', () {
      final wire = g.measurement();
      ((wire['metrics'] as Map)['red_chromaticity_proxy'] as Map)[bad] =
          'invalid';
      expect(
        () => CaptureMeasurement.fromApi(wire, captureId: 'capture-id'),
        throwsA(anything),
      );
    });
  }
  for (final dark in [false, true]) {
    testWidgets('history dark=$dark narrow 200% reduced motion and details', (
      t,
    ) async {
      final f = h.Fixture();
      final r = Repository()..rows = [capture('a')];
      await f.run(() async {
        await f.login();
        await h.mount(
          t,
          f,
          MeasurementHistoryScreen(
            state: f.state,
            repository: r,
            images: f.images,
          ),
          dark: dark,
          reduced: true,
          scale: 2,
          width: 320,
        );
        await t.pumpAndSettle();
        await t.scrollUntilVisible(
          find.text('Recorded nonclinical estimates'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Recorded nonclinical estimates'), findsOneWidget);
        await t.ensureVisible(find.text('Recorded nonclinical estimates'));
        await t.pumpAndSettle();
        await t.tap(find.text('Recorded nonclinical estimates'));
        await t.pumpAndSettle();
        expect(find.byType(MeasurementEvidence), findsOneWidget);
        expect(find.textContaining('Comparability is unknown'), findsOneWidget);
        expect(t.takeException(), isNull);
        final link = find.byKey(const ValueKey('measurementDetails:a'));
        await t.scrollUntilVisible(
          link,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await t.ensureVisible(link);
        await t.pumpAndSettle();
        await t.tap(link);
        await t.pumpAndSettle();
        expect(find.byType(CaptureDetailScreen), findsOneWidget);
        expect(t.takeException(), isNull);
        await f.done(t);
      });
    });
  }
  testWidgets('detail rebind fences pending prior capture', (t) async {
    final f = h.Fixture();
    final r = Repository();
    final old = Completer<GuidedCaptureRecord>();
    r.detail = (id) => id == 'old' ? old.future : Future.value(capture(id));
    await f.run(() async {
      await f.login();
      await h.mount(
        t,
        f,
        CaptureDetailScreen(
          state: f.state,
          id: 'old',
          repository: r,
          images: f.images,
        ),
      );
      await h.mount(
        t,
        f,
        CaptureDetailScreen(
          state: f.state,
          id: 'new',
          repository: r,
          images: f.images,
        ),
      );
      await t.pumpAndSettle();
      old.complete(capture('old'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Capture: new'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Capture: new'), findsOneWidget);
      expect(find.text('Capture: old'), findsNothing);
      await f.done(t);
    });
  });
  testWidgets('background hides evidence; resume rejects changed session', (
    t,
  ) async {
    final f = h.Fixture();
    final r = Repository()..rows = [capture('a')];
    await f.run(() async {
      await f.login();
      await h.mount(
        t,
        f,
        MeasurementHistoryScreen(state: f.state, repository: r),
      );
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      t.binding.scheduleForcedFrame();
      await t.pump();
      expect(find.textContaining('hidden while'), findsOneWidget);
      await f.login('b');
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.textContaining('Session ended.'), findsOneWidget);
      expect(r.ids, ['a']);
      await f.done(t);
    });
  });
}
