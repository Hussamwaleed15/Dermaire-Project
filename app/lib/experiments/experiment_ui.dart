import 'activation_review.dart';
import 'package:flutter/material.dart';
import 'experiment_controller.dart';
import '../services/api_service.dart';
import '../services/recovery_notice.dart';
import '../routine/routine_ui.dart';
import '../routine/routine_controller.dart';
import 'experiment_contract.dart';
import '../dermaire_state.dart';
import '../clinical/clinical_ui.dart';
import '../psm/psm_screen.dart';
import '../entry/entry_motion.dart';

class ExperimentsView extends StatefulWidget {
  const ExperimentsView({
    super.key,
    required this.controller,
    this.autoLoad = true,
    this.header,
    this.state,
    this.routineEntryId,
  });
  final ExperimentController controller;
  final bool autoLoad;
  final Widget? header;
  final DermaireState? state;
  final String? routineEntryId;
  @override
  State<ExperimentsView> createState() => _ExperimentsViewState();
}

class _ExperimentsViewState extends State<ExperimentsView> {
  late final int generation;
  bool get current =>
      !widget.controller.remote ||
      ApiService.instance.isCurrentSession(generation) &&
          ApiService.instance.canReadPatientClinicalStatus;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    if (widget.autoLoad &&
        widget.controller.rows == null &&
        !widget.controller.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            current &&
            !widget.controller.loading &&
            widget.controller.rows == null) {
          widget.controller.refresh();
        }
      });
    }
  }

  bool get activationForeground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool checkingActivation = false;
  Future<void> _activate(
    ExperimentController c,
    Map<String, dynamic> row,
  ) async {
    if (checkingActivation ||
        c.saving ||
        c.stale ||
        !current ||
        !activationForeground) {
      return;
    }
    if (!c.remote) {
      await c.write('${row['id']}/activate', {}, expected: row);
      return;
    }
    setState(() => checkingActivation = true);
    try {
      final entry =
          await ApiService.instance.patientResource(
                'routine/entries/${row['routine_entry_id']}',
                generation,
              )
              as Map<String, dynamic>;
      if (!mounted || !current || !activationForeground) return;
      if (!RoutineController.validRow(entry, 'user_configured') ||
          entry['id'] != row['routine_entry_id'] ||
          entry['product_id'] != row['product_id']) {
        throw const FormatException('Invalid linked routine');
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => ExperimentActivationReview(
          generation: generation,
          entry: entry,
          experiment: row,
        ),
      );
      if (!mounted || !current || !activationForeground || confirmed != true) {
        return;
      }
      await c.write(
        '${row['id']}/activate',
        {},
        expected: row,
        expectedRoutine: entry,
      );
    } catch (_) {
      if (mounted && current) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Linked routine could not be verified. Refresh before activating.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => checkingActivation = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      if (!current) {
        return const SafeArea(
          child: Center(
            child: Text(
              'Session ended. Reopen experiments from your current account.',
            ),
          ),
        );
      }
      final c = widget.controller;
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.state != null)
              ClinicalHomePanel(controller: widget.state!.clinical),
            if (widget.header != null) widget.header!,
            Text(
              'Controlled experiments',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Change one routine variable. Results describe observations and associations, not diagnosis or causality.',
            ),
            if (c.configurationPending != null) ...[
              const Text(
                'An experiment request needs confirmation. Current records and the original result are separate.',
              ),
              OutlinedButton(
                onPressed: c.saving || c.loading
                    ? null
                    : () => c.recoverConfiguration(),
                child: const Text('Check original experiment request'),
              ),
              if (c.configurationPending?.lookupStatus == 'unknown')
                OutlinedButton(
                  onPressed: c.saving || c.loading
                      ? null
                      : () => c.recoverConfiguration(retryOriginal: true),
                  child: const Text('Retry original experiment request'),
                ),
              if (c.configurationPending?.lookupStatus == 'expired' ||
                  c.configurationPending?.availability == 'erased')
                OutlinedButton(
                  onPressed: c.saving || c.loading || c.stale
                      ? null
                      : () => c.recoverConfiguration(
                          finishUnavailableReview: true,
                        ),
                  child: const Text('Finish experiment receipt review'),
                ),
            ],
            if (checkingActivation) const Text('Loading linked routine…'),
            if (c.error != null ||
                c.stale ||
                c.loading ||
                c.uncertain.isNotEmpty)
              RecoveryNotice(
                message: c.error,
                messageKey: c.error == null
                    ? null
                    : const Key('experimentError'),
                hasPreviousData: c.stale && c.rows != null,
                confirmedAt: c.lastConfirmedAt,
                uncertainWrite: c.uncertain.isNotEmpty,
                busy: c.loading || c.saving || c.loadingMore,
                onRefresh: c.refresh,
                refreshLabel: 'Refresh experiments',
              )
            else
              OutlinedButton(
                onPressed: c.saving || c.loadingMore ? null : c.refresh,
                child: const Text('Refresh experiments'),
              ),
            FilledButton(
              onPressed:
                  c.loading || c.saving || c.stale || c.uncertain.contains('')
                  ? null
                  : () => Navigator.of(context).push(
                      entryRoute<void>(context, _DraftForm(controller: c)),
                    ),
              child: const Text('Plan one change'),
            ),
            if (!c.loading && !c.stale && c.rows?.isEmpty == true)
              const Text('No experiments yet.'),
            if (c.hasMore)
              TextButton(
                onPressed: c.loadingMore ? null : c.loadMore,
                child: Text(
                  c.loadingMore ? 'Loading history…' : 'Load older experiments',
                ),
              ),
            if (widget.routineEntryId != null &&
                c.rows != null &&
                !c.loading &&
                !c.stale &&
                !c.rows!.any(
                  (r) => r['routine_entry_id'] == widget.routineEntryId,
                ))
              const Text(
                'No related experiment in loaded records. Load older history if available.',
              ),
            for (final row in (c.rows ?? <Map<String, dynamic>>[]).where(
              (r) =>
                  widget.routineEntryId == null ||
                  r['routine_entry_id'] == widget.routineEntryId,
            ))
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row['definition_snapshot']?['product']?['name']
                                ?.toString() ??
                            'Routine entry ${row['routine_entry_id'] ?? 'legacy'}',
                      ),
                      Text('Status: ${row['status']}'),
                      if (row['engine_version'] != 2)
                        const Text(
                          'Legacy history; no v2 result is available.',
                        ),
                      if (row['intervention'] != null)
                        Text(
                          'One change: ${row['intervention']['type']} ${row['intervention']['schedule'] ?? ''}',
                        ),
                      if (row['goal'] != null) Text(row['goal']),
                      if (row['engine_version'] == 2 &&
                          row['status'] == 'active')
                        TextButton(
                          onPressed: () => Navigator.of(context).push(
                            entryRoute<void>(
                              context,
                              RoutineScreen(
                                state: widget.state,
                                stopEntryId:
                                    row['intervention']['type'] == 'stop_entry'
                                    ? row['routine_entry_id'] as String
                                    : null,
                              ),
                            ),
                          ),
                          child: const Text('Record actual routine adherence'),
                        ),
                      Text(
                        'Start: ${row['start_date']} · ${row['target_days']} days',
                      ),
                      Text(
                        'Complete days: ${row['coverage']['elapsed_days']} · Observed days: ${row['coverage']['observed_days']}',
                      ),
                      Text(
                        'Adherence coverage: ${row['coverage']['adherence_coverage']} · Context coverage: ${row['coverage']['context_coverage']}',
                      ),
                      const Text(
                        'Current coverage is refreshed from the server. Evaluation below is a saved snapshot.',
                      ),
                      if (row['status'] == 'draft' &&
                          row['engine_version'] == 2)
                        TextButton(
                          onPressed: c.saving || c.stale
                              ? null
                              : () => Navigator.of(context).push(
                                  entryRoute<void>(
                                    context,
                                    _DraftForm(controller: c, original: row),
                                  ),
                                ),
                          child: const Text('Edit draft'),
                        ),
                      if (row['status'] == 'draft' &&
                          row['engine_version'] == 2)
                        TextButton(
                          onPressed:
                              checkingActivation ||
                                  c.saving ||
                                  c.stale ||
                                  c.uncertain.any(
                                    (p) => p.startsWith('${row['id']}/'),
                                  )
                              ? null
                              : () => _activate(c, row),
                          child: const Text('Activate today'),
                        ),
                      if (row['engine_version'] == 2 &&
                          [
                            'active',
                            'paused',
                            'baseline',
                            'draft',
                          ].contains(row['status']))
                        TextButton(
                          onPressed:
                              c.saving ||
                                  c.stale ||
                                  c.uncertain.any(
                                    (p) => p.startsWith('${row['id']}/'),
                                  )
                              ? null
                              : () => _finish(
                                  context,
                                  c,
                                  row,
                                  row['status'] == 'draft'
                                      ? 'cancelled'
                                      : 'stopped',
                                ),
                          child: Text(
                            row['status'] == 'draft'
                                ? 'Cancel draft'
                                : 'Stop experiment',
                          ),
                        ),
                      if (row['status'] == 'active' &&
                          row['engine_version'] == 2)
                        TextButton(
                          onPressed:
                              c.saving ||
                                  c.stale ||
                                  c.uncertain.any(
                                    (p) => p.startsWith('${row['id']}/'),
                                  )
                              ? null
                              : () => c.write('${row['id']}/finish', {
                                  'status': 'completed',
                                }, expected: row),
                          child: const Text('Complete elapsed experiment'),
                        ),
                      if (row['engine_version'] == 2 &&
                          [
                            'active',
                            'completed',
                            'stopped',
                          ].contains(row['status']))
                        TextButton(
                          onPressed:
                              c.saving ||
                                  c.stale ||
                                  c.uncertain.any(
                                    (p) => p.startsWith('${row['id']}/'),
                                  )
                              ? null
                              : () => c.write(
                                  '${row['id']}/evaluate',
                                  {},
                                  expected: row,
                                ),
                          child: const Text('Evaluate evidence'),
                        ),
                      if (row['result'] != null) ...[
                        Text(
                          row['result']['result']['label']
                              .toString()
                              .replaceAll('_', ' '),
                        ),
                        Text(row['result']['result']['evidence_summary']),
                        Text(
                          'Evidence: ${row['result']['result']['evidence_strength']} · Evaluated: ${row['result']['result']['evaluated_at']}',
                        ),
                        for (final limitation
                            in row['result']['result']['limitations'])
                          Text('• $limitation'),
                        ExpansionTile(
                          title: const Text('Evidence and source references'),
                          children: [
                            _EvidenceDetails(
                              result: row['result']['result'] as Map,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (widget.state != null)
              PersonalSkinModelEntry(state: widget.state!),
          ],
        ),
      );
    },
  );
}

Future<void> _finish(
  BuildContext context,
  ExperimentController c,
  Map<String, dynamic> row,
  String status,
) async {
  final generation = ApiService.instance.sessionGeneration;
  final yes = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(status == 'cancelled' ? 'Cancel draft?' : 'Stop experiment?'),
      content: const Text(
        'History remains. Stopping does not restore the previous routine or schedule an image comparison.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Keep experiment'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  if (yes == true &&
      context.mounted &&
      (!c.remote || ApiService.instance.isCurrentSession(generation))) {
    await c.write('${row['id']}/finish', {'status': status}, expected: row);
  }
}

class _EvidenceDetails extends StatelessWidget {
  const _EvidenceDetails({required this.result});
  final Map result;
  @override
  Widget build(BuildContext context) {
    final comparison = result['comparison'] as Map? ?? const {};
    final change = result['observed_change'] as Map? ?? const {};
    final provenance = result['provenance'] as Map;
    final snapshot = provenance['definition_snapshot'] is Map
        ? provenance['definition_snapshot'] as Map
        : null;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Saved evaluation: ${result['evaluated_at']}'),
          Text(
            'Source: ${provenance['source']} · ${provenance['algorithm'] ?? 'Not supplied'}',
          ),
          if (snapshot != null)
            Text(
              'Frozen definition: ${snapshot['frozen_at'] ?? 'Not supplied'} · Routine ${snapshot['expected'] is Map ? snapshot['expected']['id'] ?? 'Not supplied' : 'Not supplied'}',
            ),
          Text(
            'Baseline window: ${comparison['start'] ?? 'Not supplied'} to ${comparison['end_exclusive'] ?? 'Not supplied'} (end excluded)',
          ),
          Text(
            'Source compared: ${comparison['measurement_source'] ?? 'Not supplied'} · Baseline days: ${comparison['baseline_days'] ?? 'Unknown'} · Experiment days: ${comparison['experiment_days'] ?? 'Unknown'}',
          ),
          if (change.isNotEmpty)
            Text(
              'Metric: ${change['metric'] ?? 'Unknown'} · Baseline value: ${change['baseline_mean'] ?? 'Unavailable'} · Experiment value: ${change['experiment_mean'] ?? 'Unavailable'} · Difference: ${change['delta_points'] ?? 'Unavailable'}',
            ),
          const Text(
            'Numeric values keep the server scale. This API does not provide explicit units; values are not interpreted as percentages or capture fractions.',
          ),
          const Text(
            'Rule-based observational evidence. Not image comparison, causal proof, diagnosis or an AI-directed treatment plan.',
          ),
          for (final item
              in provenance['experiment_checkins'] is List
                  ? provenance['experiment_checkins'] as List
                  : const [])
            if (item is Map)
              Text(
                'Observation ${item['id']} · ${item['created_at']} · Source ${item['source'] ?? 'user report; measurement unknown'}',
              ),
        ],
      ),
    );
  }
}

class _DraftForm extends StatefulWidget {
  const _DraftForm({required this.controller, this.original});
  final Map<String, dynamic>? original;
  final ExperimentController controller;
  @override
  State<_DraftForm> createState() => _DraftFormState();
}

class _DraftFormState extends State<_DraftForm> {
  late final int generation;
  bool get current =>
      !widget.controller.remote ||
      ApiService.instance.isCurrentSession(generation) &&
          ApiService.instance.canReadPatientClinicalStatus;
  List<Map<String, dynamic>>? entries;
  String? entryId;
  String type = 'change_schedule';
  String schedule = 'PM';
  String metric = 'texture';
  String? error;
  final goal = TextEditingController();
  final notes = TextEditingController();
  final duration = TextEditingController(text: '28');
  final date = TextEditingController(
    text: DateTime.now().toUtc().toIso8601String().substring(0, 10),
  );
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    ApiService.instance.addListener(sessionChanged);
    final row = widget.original;
    if (row != null) {
      entryId = row['routine_entry_id'];
      type = row['intervention']['type'];
      schedule = row['intervention']['schedule'] ?? 'PM';
      metric = row['primary_concern'];
      goal.text = row['goal'] ?? '';
      notes.text = row['notes'] ?? '';
      duration.text = '${row['target_days']}';
      date.text = (row['start_date'] as String).substring(0, 10);
    }
    load();
  }

  void sessionChanged() {
    if (!current && mounted) {
      for (final c in [goal, notes, duration, date]) {
        c.clear();
      }
      setState(() {
        entries = null;
        entryId = null;
      });
    }
  }

  Future<void> load() async {
    try {
      final response = await RemoteRoutineRepository().read(
        'entries?active=true',
      );
      if (mounted && current) {
        setState(() {
          entries = response;
          error = null;
        });
      }
    } catch (_) {
      if (mounted && current) {
        setState(
          () => error = 'Routine unavailable. Retry to choose a target.',
        );
      }
    }
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(sessionChanged);
    for (final c in [goal, notes, duration, date]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.original == null ? 'Plan one change' : 'Edit draft'),
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => !current
          ? const Center(child: Text('Session ended. Draft cleared.'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Add a new daily entry today for a start experiment, or choose an existing entry to stop or change its schedule. Activation applies the planned configuration. Stopping the experiment does not restore your previous routine.',
                ),
                if (error != null) ...[
                  Text(error!),
                  TextButton(
                    onPressed: load,
                    child: const Text('Retry routine'),
                  ),
                ],
                if (entries == null && error == null)
                  const LinearProgressIndicator(),
                if (entries?.isEmpty == true)
                  const Text('Add an active routine entry in Products first.'),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: entryId,
                  decoration: const InputDecoration(
                    labelText: 'One routine entry',
                  ),
                  items: [
                    for (final e in entries ?? <Map<String, dynamic>>[])
                      DropdownMenuItem(
                        value: e['id'] as String,
                        child: Text('${e['product_name']} · ${e['schedule']}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => entryId = v),
                ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: type,
                  items: [
                    for (final v in [
                      'start_entry',
                      'stop_entry',
                      'change_schedule',
                    ])
                      DropdownMenuItem(
                        value: v,
                        child: Text(v.replaceAll('_', ' ')),
                      ),
                  ],
                  onChanged: (v) => setState(() => type = v!),
                ),
                if (type != 'stop_entry')
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: schedule,
                    items: [
                      for (final v in ['AM', 'PM', 'BOTH'])
                        DropdownMenuItem(value: v, child: Text(v)),
                    ],
                    onChanged: (v) => setState(() => schedule = v!),
                  ),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: metric,
                  items: [
                    for (final v in ['texture', 'hydration', 'redness'])
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => setState(() => metric = v!),
                ),
                TextField(
                  controller: date,
                  decoration: const InputDecoration(
                    labelText: 'Start date (UTC YYYY-MM-DD)',
                  ),
                ),
                TextField(
                  controller: duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (7–90 days)',
                  ),
                ),
                TextField(
                  maxLength: 500,
                  controller: goal,
                  decoration: const InputDecoration(
                    labelText: 'Goal or question (optional)',
                  ),
                ),
                TextField(
                  maxLength: 2000,
                  controller: notes,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                if (widget.controller.error != null)
                  Text(widget.controller.error!),
                FilledButton(
                  onPressed:
                      entryId == null ||
                          widget.controller.saving ||
                          widget.controller.stale ||
                          widget.controller.uncertain.contains(
                            widget.original?['id'] ?? '',
                          )
                      ? null
                      : () async {
                          if (!current) return;
                          final payload = <String, dynamic>{
                            'routine_entry_id': entryId,
                            'intervention': {
                              'type': type,
                              if (type != 'stop_entry') 'schedule': schedule,
                            },
                            'start_date': date.text.trim(),
                            'target_days': int.tryParse(duration.text),
                            'primary_concern': metric,
                            'goal': goal.text.trim().isEmpty
                                ? null
                                : goal.text.trim(),
                            'notes': notes.text.trim().isEmpty
                                ? null
                                : notes.text.trim(),
                          };
                          if (!ExperimentContract.draft(payload)) {
                            setState(
                              () => error =
                                  'Choose a valid entry, date, duration, goal and notes.',
                            );
                            return;
                          }
                          final success = await widget.controller.write(
                            widget.original?['id'] as String? ?? '',
                            widget.original == null
                                ? payload
                                : {
                                    'definition': payload,
                                    'notes': payload['notes'],
                                  },
                            method: widget.original == null ? 'POST' : 'PATCH',
                            expected: widget.original,
                          );
                          if (success && current && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  child: const Text('Save draft on server'),
                ),
              ],
            ),
    ),
  );
}
