import 'dart:async';
import 'package:dermaire_app/home_controller.dart';
import 'package:dermaire_app/home/home_response.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_authority_test.dart' as h;
import 'home_state_integration_test.dart' as f;

Map<String, dynamic> projection({
  bool completed = true,
  bool measured = false,
}) {
  final home = {
    ...h.snapshot(),
    'experiment': null,
    'today_checked_in': measured,
    'journal': <Object>[],
  };
  home['observation_status'] = {
    'schema_version': 1,
    'day_basis': 'UTC',
    'today_completed': completed,
    'recent': [
      if (completed)
        {
          'id': 'report-only-record',
          'created_at': home['as_of'],
          'time_of_day': 'Morning',
          'kind': measured ? 'report_and_measurement' : 'report_only',
          'measurement_available': measured,
        },
    ],
  };
  return home;
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  test(
    'report-only server completion never increments measured completion',
    () async {
      final repo = h.Repository()..data = projection();
      final c = HomeController(repo);
      addTearDown(c.dispose);
      expect(await c.refresh(), isTrue);
      expect(c.observationStatus!.completedToday, isTrue);
      expect(c.observationStatus!.recent.single.kind, 'report_only');
      expect(c.current!['today_checked_in'], isFalse);
      expect(c.current!['journal'], isEmpty);
      c.current!['observation_status']['today_completed'] = false;
      expect(c.observationStatus!.completedToday, isTrue);
    },
  );

  test(
    'missing legacy projection is unavailable while explicit empty is false',
    () async {
      final repo = h.Repository();
      final c = HomeController(repo);
      addTearDown(c.dispose);
      expect(await c.refresh(), isTrue);
      expect(c.observationStatus, isNull);
      repo.data = projection(completed: false);
      expect(await c.refresh(), isTrue);
      expect(c.observationStatus!.completedToday, isFalse);
      expect(c.observationStatus!.recent, isEmpty);
    },
  );

  test('yesterday report remains history without completing today', () {
    final home = projection();
    final status = home['observation_status'] as Map;
    status['today_completed'] = false;
    (status['recent'] as List).single['created_at'] = DateTime.parse(
      home['as_of'],
    ).subtract(const Duration(days: 1)).toIso8601String();
    final parsed = HomeObservationStatus.fromHome(home);
    expect(parsed.completedToday, isFalse);
    expect(parsed.recent.single.id, 'report-only-record');
  });

  for (final invalid in [
    'null',
    'version',
    'basis',
    'missing boolean',
    'string boolean',
    'missing time',
    'future time',
    'contradictory completion',
    'contradictory measurement',
    'unsupported kind',
    'duplicate',
    'unordered',
  ]) {
    test(
      'invalid $invalid observation projection fails Home read closed',
      () async {
        final home = projection();
        final status = home['observation_status'] as Map;
        final row = (status['recent'] as List).single as Map;
        switch (invalid) {
          case 'null':
            home['observation_status'] = null;
          case 'version':
            status['schema_version'] = 2;
          case 'basis':
            status['day_basis'] = 'local';
          case 'missing boolean':
            status.remove('today_completed');
          case 'string boolean':
            status['today_completed'] = 'true';
          case 'missing time':
            row.remove('created_at');
          case 'future time':
            row['created_at'] = DateTime.parse(
              home['as_of'],
            ).add(const Duration(seconds: 1)).toIso8601String();
          case 'contradictory completion':
            status['today_completed'] = false;
          case 'contradictory measurement':
            row['measurement_available'] = true;
          case 'unsupported kind':
            row['kind'] = 'capture';
          case 'duplicate':
            (status['recent'] as List).add(Map<String, dynamic>.from(row));
          case 'unordered':
            (status['recent'] as List).add(<String, dynamic>{
              ...row,
              'id': 'z-record',
            });
        }
        final c = HomeController(h.Repository()..data = home);
        addTearDown(c.dispose);
        expect(await c.refresh(), isFalse);
        expect(c.current, isNull);
        expect(c.observationStatus, isNull);
        expect(c.error, isNotNull);
        expect(c.loading, isFalse);
      },
    );
  }

  test(
    'refresh failure and stale marker cannot present old completion as current',
    () async {
      final repo = h.Repository()..data = projection();
      final c = HomeController(repo);
      addTearDown(c.dispose);
      await c.refresh();
      c.markStale();
      expect(c.observationStatus, isNull);
      repo.fail = true;
      expect(await c.refresh(), isFalse);
      expect(c.observationStatus, isNull);
      repo.fail = false;
      repo.data = projection(completed: false);
      expect(await c.refresh(), isTrue);
      expect(c.observationStatus!.completedToday, isFalse);
    },
  );

  for (final scenario in ['session', 'dispose', 'superseded']) {
    test(
      'late $scenario response cannot publish observation completion',
      () async {
        final repo = h.Repository()
          ..pending = Completer<Map<String, dynamic>>();
        final c = HomeController(repo);
        final pending = c.refresh();
        if (scenario == 'session') await api.init();
        if (scenario == 'dispose') c.dispose();
        if (scenario == 'superseded') {
          final old = repo.pending!;
          repo.pending = null;
          repo.data = projection(completed: false);
          await c.refresh();
          old.complete(projection());
        } else {
          repo.pending!.complete(projection());
        }
        expect(await pending, isFalse);
        if (scenario == 'superseded') {
          expect(c.observationStatus!.completedToday, isFalse);
        } else {
          expect(c.observationStatus, isNull);
        }
        if (scenario != 'dispose') c.dispose();
      },
    );
  }

  for (final dark in [false, true]) {
    testWidgets(
      'Home shows independent observation status and legacy unavailable dark=$dark',
      (t) async {
        t.view.physicalSize = const Size(320, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final fixture = f.Fixture();
        await http.runWithClient(
          () async {
            fixture.home.data = projection();
            await fixture.ready();
            final baselineDays = fixture.state.baseline.completedDays;
            await f.mount(t, fixture, dark: dark, scale: 2, reduced: true);
            await f.reveal(t, find.text('Observation recorded today (UTC)'));
            expect(
              find.text('Observation recorded today (UTC)'),
              findsOneWidget,
            );
            expect(
              find.text(
                'No confirmed tracking measurement recorded today (UTC)',
              ),
              findsOneWidget,
            );
            expect(fixture.state.baseline.completedDays, baselineDays);
            expect(t.takeException(), isNull);
            fixture.home.data = {...h.snapshot(), 'experiment': null};
            await fixture.state.home.refresh();
            await t.pumpAndSettle();
            expect(find.text('Observation recorded today (UTC)'), findsNothing);
            await f.reveal(
              t,
              find.textContaining('Observation completion is unavailable'),
            );
            expect(
              find.textContaining('This does not mean no observation'),
              findsOneWidget,
            );
            await api.init();
            await t.pumpAndSettle();
            expect(
              find.textContaining('Record report-only-record'),
              findsNothing,
            );
            await f.finish(t, fixture);
          },
          () => MockClient((r) {
            if (r.url.host != 'flutter-tests.invalid') {
              throw StateError('HTTP host denied');
            }
            return fixture.transport(r);
          }),
        );
      },
    );
  }
}
