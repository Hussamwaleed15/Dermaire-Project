import 'dart:async';
import 'package:flutter/material.dart';
import '../app_shell.dart' show CameraScreen, TimelineScreen, ContextScreen;
import '../clinical/clinical_ui.dart';
import '../clinical/clinical_models.dart' show timestamp;
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import '../observations/observation_controller.dart';
import '../observations/observation_models.dart';
import '../services/api_service.dart';
import 'home_policy.dart';
import '../routine/routine_ui.dart';

class PatientHome extends StatefulWidget {
  const PatientHome({super.key, required this.state});
  final DermaireState state;
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  late final int generation;
  bool get current =>
      mounted &&
      ApiService.instance.isCurrentSession(generation) &&
      ApiService.instance.canReadPatientClinicalStatus;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!current) return;
      final s = widget.state;
      if (s.home.retrievedAt == null &&
          !s.home.loading &&
          s.home.error == null) {
        unawaited(s.home.refresh());
      }
      if (s.baseline.retrievedAt == null &&
          !s.baseline.loading &&
          s.baseline.error == null) {
        unawaited(s.baseline.refresh());
      }
      if (s.observations.historyPhase == ObservationHistoryPhase.empty) {
        unawaited(s.observations.loadHistory(generation: generation));
      }
    });
  }

  void navigate(HomeAction action) {
    if (!current) return;
    final s = widget.state;
    switch (action) {
      case HomeAction.safety:
      case HomeAction.clinician:
      case HomeAction.verifyGuidance:
        openPage(context, ClinicalStatusScreen(controller: s.clinical));
      case HomeAction.uncertainObservation:
      case HomeAction.observe:
        openPage(context, CameraScreen(state: s));
      case HomeAction.history:
        openPage(context, TimelineScreen(state: s));
      case HomeAction.experiment:
        s.selectTab(1);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      if (!current) {
        return const SafeArea(
          child: Center(
            child: Text(
              'Home is unavailable for this session. Sign in and confirm safety acceptance.',
            ),
          ),
        );
      }
      final s = widget.state;
      final home = s.home.current;
      final experiment = home?['experiment'] as Map?;
      final name = s.account.ready ? s.account.value?.name.trim() ?? '' : '';
      final next = HomeNextAction.select(
        clinical: s.clinical,
        observations: s.observations,
        hasExperiment: experiment != null,
      );
      final loading =
          s.home.loading ||
          s.baseline.loading ||
          s.observations.historyPhase == ObservationHistoryPhase.loading ||
          s.clinical.loading;
      return SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => s.refreshPatientHome(
            generation: generation,
            refreshProfile: true,
          ),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            // Stable section identities retain focus as content changes.
            children: [
              Text(
                name.isEmpty
                    ? 'Welcome'
                    : 'Welcome, ${name.split(RegExp(r'\s+')).first}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Your skin health journey, grounded in what is recorded.',
              ),
              const SizedBox(height: 20),
              ClinicalHomePanel(
                key: const Key('homeGuidance'),
                controller: s.clinical,
              ),
              const SizedBox(height: 16),
              HomePersonalStatus(
                key: const Key('homePersonalStatus'),
                state: s,
              ),
              Text(
                'Next available action',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              DermaireCard(
                key: const Key('homeNextAction'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      next.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(next.reason),
                    const SizedBox(height: 12),
                    EntryPress(
                      child: FilledButton(
                        key: const Key('homeNextActionButton'),
                        onPressed: () => navigate(next.action),
                        child: Text(next.title),
                      ),
                    ),
                  ],
                ),
              ),
              HomeRecentActivity(
                key: const Key('homeRecentActivity'),
                controller: s.observations,
                onHistory: () => navigate(HomeAction.history),
              ),
              Text(
                'Continue your journey',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              DermaireCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      key: const Key('homeObserve'),
                      onPressed: () => navigate(HomeAction.observe),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Start observation'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('homeHistory'),
                      onPressed: () => navigate(HomeAction.history),
                      icon: const Icon(Icons.history_rounded),
                      label: const Text('Observation history'),
                    ),
                    if (experiment != null)
                      OutlinedButton(
                        onPressed: () => navigate(HomeAction.experiment),
                        child: const Text('Open experiment'),
                      ),
                    OutlinedButton(
                      key: const Key('homeProducts'),
                      onPressed: () {
                        if (current) s.selectTab(2);
                      },
                      child: const Text('Products & routines'),
                    ),
                    OutlinedButton(
                      key: const Key('homeRoutine'),
                      onPressed: current
                          ? () => openEntry(context, RoutineScreen(state: s))
                          : null,
                      child: const Text('My routine & reports'),
                    ),
                    OutlinedButton(
                      key: const Key('homeContext'),
                      onPressed: () {
                        if (current) openPage(context, ContextScreen(state: s));
                      },
                      child: const Text("View or edit today's context"),
                    ),
                    TextButton(
                      key: const Key('homeProfile'),
                      onPressed: () {
                        if (current) s.selectTab(5);
                      },
                      child: const Text('Account and skin profile'),
                    ),
                  ],
                ),
              ),
              Semantics(
                liveRegion: true,
                child: Text(
                  loading
                      ? 'Refreshing independent Home sources…'
                      : 'Refresh reads each source separately. No new observation is submitted.',
                ),
              ),
              OutlinedButton(
                key: const Key('homeRefresh'),
                onPressed: loading
                    ? null
                    : () => s.refreshPatientHome(
                        generation: generation,
                        refreshProfile: true,
                      ),
                child: const Text('Refresh Home'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class HomePersonalStatus extends StatelessWidget {
  const HomePersonalStatus({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) {
    final home = state.home.current;
    final experiment = home?['experiment'] as Map?;
    final baseline = state.baseline;
    return AnimatedSize(
      duration: EntryMotion.duration(context, 180),
      alignment: Alignment.topCenter,
      child: DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Your current status',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                home == null
                    ? state.home.loading
                          ? 'Loading tracking status…'
                          : state.home.error ??
                                'Tracking status unconfirmed. Refresh to verify.'
                    : home['today_checked_in'] == true
                    ? 'Confirmed tracking measurement recorded today (UTC)'
                    : 'No confirmed tracking measurement recorded today (UTC)',
              ),
            ),
            if (home != null)
              Text(
                'Tracking status as of ${clinicalTime(timestamp(home['as_of']))}',
              ),
            if (home == null && state.home.retrievedAt != null)
              const Text(
                'Previously retrieved Home data is not shown as current.',
              ),
            const SizedBox(height: 12),
            Text(
              baseline.available
                  ? 'Tracking reference: ${baseline.completedDays} of 5 confirmed UTC days'
                  : baseline.loading
                  ? 'Loading tracking reference…'
                  : baseline.error ??
                        'Tracking reference unconfirmed. Refresh to verify.',
            ),
            if (baseline.available && baseline.retrievedAt != null)
              Text(
                'Baseline retrieved ${clinicalTime(baseline.retrievedAt!)}. Calculation time is unavailable.',
              ),
            if (!baseline.available && baseline.retrievedAt != null)
              const Text(
                'Previously retrieved baseline data is not shown as current.',
              ),
            const Text(
              'Tracking measurements may be user-entered values or nonclinical image estimates. A reference is not a clinical assessment. Report-only observations do not count as measurement days.',
            ),
            if (home != null &&
                baseline.available &&
                home['today_checked_in'] != baseline.todayCheckedIn)
              const Text(
                'Home and the tracking reference differ about today’s measurements. Home includes experiment-linked values; the reference uses unlinked values. Separate read times may also differ.',
              ),
            const SizedBox(height: 12),
            if (home != null && experiment == null)
              const Text('No current experiment'),
            if (experiment != null) ...[
              Text(
                'Day ${experiment['current_day']} of ${experiment['target_days']}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Testing: ${experiment['product_name'] ?? 'No linked product'} · ${experiment['primary_concern']}',
              ),
              Text('Status: ${experiment['status']}'),
              const Text(
                'Scheduled experiment day, not adherence or improvement. Open the experiment for its recorded evidence.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class HomeRecentActivity extends StatelessWidget {
  const HomeRecentActivity({
    super.key,
    required this.controller,
    required this.onHistory,
  });
  final ObservationController controller;
  final VoidCallback onHistory;
  @override
  Widget build(BuildContext context) {
    final rows = controller.rows;
    final stale = controller.historyStale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Recent verified activity',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 10),
        Semantics(
          liveRegion: true,
          child: Text(
            controller.historyPhase == ObservationHistoryPhase.loading
                ? rows == null
                      ? 'Loading saved activity…'
                      : 'Refreshing activity; previous records are not current history.'
                : controller.historyError ??
                      (rows == null
                          ? 'Activity unconfirmed. Refresh to verify.'
                          : stale
                          ? 'Previously retrieved activity; current history unconfirmed.'
                          : rows.isEmpty
                          ? 'No saved observations in server history.'
                          : 'Saved records from your server history.'),
          ),
        ),
        if (controller.historyRetrievedAt != null)
          Text(
            'History retrieved ${clinicalTime(controller.historyRetrievedAt!)}',
          ),
        const SizedBox(height: 10),
        for (final row in rows?.take(2) ?? <ObservationRecord>[])
          DermaireCard(
            key: ValueKey('home-record-${row.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  stale ? 'Previously retrieved record' : 'Saved observation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('${clinicalTime(row.createdAt)} · ${row.moment}'),
                Text('Record: ${row.id}'),
                if (row.report != null)
                  Text(
                    row.report!.unsupported
                        ? 'Reported values include unsupported fields; open history for details.'
                        : 'User-reported change: ${row.report!.change}',
                  ),
                Text(switch (row.kind) {
                  ObservationKind.reportOnly =>
                    'Report-only observation · No recorded measurements',
                  ObservationKind.manual =>
                    'User-entered tracking measurements',
                  ObservationKind.imageEstimate =>
                    'Nonclinical image estimates · Not a diagnosis',
                  ObservationKind.unsupported =>
                    'Measurement source unsupported · No confirmed metrics shown',
                }),
                if (row.kind == ObservationKind.manual ||
                    row.kind == ObservationKind.imageEstimate)
                  Text(
                    'Hydration: ${row.scores['hydration']} · Redness: ${row.scores['redness']} · Texture: ${row.scores['texture']}',
                  ),
                TextButton(
                  onPressed: onHistory,
                  child: const Text('Open observation history'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
