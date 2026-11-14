import 'dart:async';
import 'package:dermaire_app/dermaire_state.dart';
import 'package:dermaire_app/home_controller.dart';
import 'package:dermaire_app/observations/observation_models.dart';
import 'package:dermaire_app/observations/observation_controller.dart';
import 'package:dermaire_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'baseline_authority_test.dart' as b;
import 'home_authority_test.dart' as h;
import 'home_observation_status_test.dart' as p;
import 'home_state_integration_test.dart' as f;
import 'observation_test.dart' as o;

class UncertainRepository extends f.HistoryRepo {
  @override
  Future<ObservationRecord> save(ObservationDraft draft, int generation) async {
    writes++;
    throw const ObservationWriteException(ObservationFailure.uncertain);
  }
}

void main() {
  final api = ApiService.instance;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  tearDown(() => api.init());

  for (final contradiction in [
    'measurement flag',
    'same record in metric journal',
  ]) {
    test(
      'Home rejects cross-projection contradiction: $contradiction',
      () async {
        final data = p.projection(
          measured: contradiction == 'measurement flag',
        );
        if (contradiction == 'measurement flag') {
          data['today_checked_in'] = false;
        } else {
          data['journal'] = [
            {
              ...((h.snapshot()['journal'] as List).single
                  as Map<String, dynamic>),
              'id': 'report-only-record',
            },
          ];
        }
        final home = HomeController(h.Repository()..data = data);
        expect(await home.refresh(), isFalse);
        expect(home.observationStatus, isNull);
        expect(home.current, isNull);
        expect(home.loading, isFalse);
        home.dispose();
      },
    );
  }

  test(
    'measurement-only and measured observation remain distinct valid server cases',
    () async {
      final repo = h.Repository()
        ..data = p.projection(completed: false, measured: true);
      final home = HomeController(repo);
      expect(await home.refresh(), isTrue);
      expect(home.observationStatus!.completedToday, isFalse);
      expect(home.current!['today_checked_in'], isTrue);
      repo.data = p.projection(measured: true);
      expect(await home.refresh(), isTrue);
      expect(home.observationStatus!.completedToday, isTrue);
      expect(
        home.observationStatus!.recent.single.kind,
        'report_and_measurement',
      );
      home.dispose();
    },
  );

  for (final ending in ['fresh aggregate', 'failure', 'session change']) {
    test(
      'uncertain original observation invalidates old Home and never resolves from $ending',
      () async {
        final transport = f.Fixture();
        final home = f.HomeRepo()..data = p.projection(completed: false);
        final history = UncertainRepository();
        final state = DermaireState(
          homeRepository: home,
          baselineRepository: b.FakeBaseline(),
          clinicalRepository: f.ClinicalRepo(),
          observationRepository: history,
        );
        await http.runWithClient(() async {
          await o.login('a');
          await state.account.hydrate();
          await state.refreshPatientHome(generation: api.sessionGeneration);
          final baselineBefore = state.baseline.completedDays;
          expect(state.home.observationStatus!.completedToday, isFalse);
          home.pending = Completer<Map<String, dynamic>>();
          final generation = api.sessionGeneration;
          state.observations.begin(generation: generation);
          state.observations.edit(o.draft(), generation: generation);
          expect(state.observations.review(generation: generation), isTrue);
          expect(
            await state.observations.submit(generation: generation),
            isFalse,
          );
          expect(state.home.current, isNull);
          expect(state.home.loading, isTrue);
          expect(state.observations.historyStale, isTrue);
          expect(state.observations.phase, ObservationPhase.uncertain);
          if (ending == 'session change') await api.init();
          if (ending == 'failure') {
            home.pending!.completeError(StateError('Synthetic unavailable'));
          } else {
            home.pending!.complete(p.projection());
          }
          await Future<void>.delayed(Duration.zero);
          if (ending == 'fresh aggregate') {
            expect(state.home.observationStatus!.completedToday, isTrue);
            expect(state.observations.phase, ObservationPhase.uncertain);
            expect(state.observations.saved, isNull);
            expect(state.baseline.completedDays, baselineBefore);
          } else {
            expect(state.home.current, isNull);
          }
          expect(history.writes, 1);
          state.dispose();
        }, () => o.isolated(transport.transport));
      },
    );
  }

  for (final ending in ['rollover', 'clear', 'dispose']) {
    testWidgets('Home UTC-day expiry is scoped to $ending', (t) async {
      var clock = DateTime.utc(2026, 11, 14, 23, 59, 59);
      Map<String, dynamic> data() => {
        ...h.snapshot(),
        'as_of': clock.toIso8601String(),
        'date': clock.toIso8601String().split('T').first,
        'experiment': null,
        'observation_status': {
          'schema_version': 1,
          'day_basis': 'UTC',
          'today_completed': true,
          'recent': [
            {
              'id': 'today-record',
              'created_at': clock.toIso8601String(),
              'time_of_day': 'Evening',
              'kind': 'report_only',
              'measurement_available': false,
            },
          ],
        },
      };
      final repo = h.Repository()..data = data();
      final home = HomeController(repo, now: () => clock);
      var notifications = 0;
      home.addListener(() => notifications++);
      expect(await home.refresh(), isTrue);
      expect(home.observationStatus!.completedToday, isTrue);
      if (ending == 'clear') home.clear();
      if (ending == 'dispose') home.dispose();
      final before = notifications;
      clock = clock.add(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
      expect(home.current, isNull);
      expect(home.observationStatus, isNull);
      expect(notifications, ending == 'rollover' ? before + 1 : before);
      if (ending == 'rollover') {
        expect(home.stale, isTrue);
        repo.data = data();
        expect(await home.refresh(), isTrue);
        expect(home.observationStatus!.completedToday, isTrue);
      }
      if (ending != 'dispose') home.dispose();
    });
  }
}
