import 'package:flutter/material.dart';
import '../dermaire_state.dart';
import '../dermaire_theme.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart';
import '../capture/guided_camera_screen.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import 'observation_controller.dart';
import 'observation_models.dart';

class ObservationScreen extends StatefulWidget {
  const ObservationScreen({
    super.key,
    required this.state,
    required this.onHistory,
    this.onContext,
  });
  final DermaireState state;
  final VoidCallback onHistory;
  final VoidCallback? onContext;
  @override
  State<ObservationScreen> createState() => _ObservationScreenState();
}

class _ObservationScreenState extends State<ObservationScreen> {
  late final int generation;
  final notes = TextEditingController();
  final scroll = ScrollController();
  ObservationController get c => widget.state.observations;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    c.begin(generation: generation);
    notes.text = c.draft.notes;
    c.addListener(changed);
  }

  ObservationPhase? _lastPhase;
  void changed() {
    if (!mounted) return;
    if (_lastPhase != c.phase &&
        [
          ObservationPhase.review,
          ObservationPhase.confirmed,
          ObservationPhase.uncertain,
        ].contains(c.phase)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && active && scroll.hasClients) scroll.jumpTo(0);
      });
    }
    _lastPhase = c.phase;
    if (!ApiService.instance.isCurrentSession(generation)) notes.clear();
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    notes.dispose();
    scroll.dispose();
    super.dispose();
  }

  bool get active =>
      ApiService.instance.isCurrentSession(generation) && c.current;
  void edit({
    String? change,
    String? moment,
    String? routine,
    bool clearRoutine = false,
    Set<String>? symptoms,
    String? note,
    String? severity,
    bool clearSeverity = false,
    String? pain,
    bool clearPain = false,
    Map<String, bool?>? flags,
  }) {
    if (!active) return;
    final d = c.draft;
    c.edit(
      ObservationDraft(
        change: change ?? d.change,
        moment: moment ?? d.moment,
        symptoms: symptoms ?? d.symptoms,
        routine: clearRoutine ? null : routine ?? d.routine,
        notes: note ?? d.notes,
        severity: clearSeverity ? null : severity ?? d.severity,
        pain: clearPain ? null : pain ?? d.pain,
        flags: flags ?? d.flags,
      ),
      generation: generation,
    );
  }

  Future<void> startNew() async {
    if (!active) return;
    if (c.phase == ObservationPhase.uncertain) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a separate observation?'),
          content: const Text(
            'The previous attempt may already be saved. Starting again can create a duplicate. Review history first; an empty history does not prove a write failed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep uncertain attempt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Start separate observation'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted || !active) return;
    }
    c.startNew(generation: generation);
    notes.clear();
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  final messageKey = GlobalKey();
  void review() {
    if (!active) return;
    c.review(generation: generation);
    if (scroll.hasClients) scroll.jumpTo(0);
    if (c.message != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && active && messageKey.currentContext != null) {
          Scrollable.ensureVisible(messageKey.currentContext!, alignment: .2);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!active) {
      return const DermairePage(
        title: 'Observation session ended',
        children: [
          Text(
            'Sign in and confirm safety acceptance before recording or viewing your observations.',
          ),
        ],
      );
    }
    final phase = c.phase;
    final d = c.draft;
    return DermairePage(
      title: 'Observe your skin',
      subtitle:
          'Record changes over time. Your observations are not a diagnosis or a measurement.',
      scrollController: scroll,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClinicalHomePanel(controller: widget.state.clinical),
            const SizedBox(height: 16),
            if (c.message != null)
              Semantics(
                liveRegion: true,
                child: DermaireCard(
                  key: messageKey,
                  child: Text(c.message!, key: const Key('observationMessage')),
                ),
              ),
            if (phase == ObservationPhase.editing ||
                phase == ObservationPhase.rejected) ...[
              _section(
                context,
                'What changed?',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Overall skin change (required)'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final value in observationChanges)
                          ChoiceChip(
                            key: Key('change_$value'),
                            label: Text(
                              value == 'same'
                                  ? 'About the same'
                                  : value[0].toUpperCase() + value.substring(1),
                            ),
                            selected: d.change == value,
                            onSelected: (_) => edit(change: value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Observation time (required)'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final value in ['Morning', 'Evening'])
                          ChoiceChip(
                            key: Key('moment_$value'),
                            label: Text(value),
                            selected: d.moment == value,
                            onSelected: (_) => edit(moment: value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _section(
                context,
                'Concerns you want to record',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Optional — no selection means not reported, not a negative symptom assessment.',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final value in observationSymptoms)
                          FilterChip(
                            key: Key('symptom_$value'),
                            label: Text(value),
                            selected: d.symptoms.contains(value),
                            onSelected: (yes) {
                              final selected = d.symptoms.toSet();
                              yes
                                  ? selected.add(value)
                                  : selected.remove(value);
                              edit(symptoms: selected);
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Routine report (optional)'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Not reported'),
                          selected: d.routine == null,
                          onSelected: (_) => edit(clearRoutine: true),
                        ),
                        for (final value in observationRoutines)
                          ChoiceChip(
                            key: Key('routine_$value'),
                            label: Text(value.replaceAll('_', ' ')),
                            selected: d.routine == value,
                            onSelected: (_) => edit(routine: value),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              DermaireCard(
                child: ExpansionTile(
                  key: const Key('optionalSafety'),
                  title: const Text('Optional safety observations'),
                  subtitle: const Text(
                    'Only share what you know. Unanswered stays unknown.',
                  ),
                  expansionAnimationStyle: EntryMotion.reduced(context)
                      ? AnimationStyle.noAnimation
                      : const AnimationStyle(
                          duration: Duration(milliseconds: 180),
                        ),
                  children: [
                    _levels(
                      'Reported severity',
                      d.severity,
                      (v) => edit(severity: v, clearSeverity: v == null),
                      'severity',
                    ),
                    _levels(
                      'Reported pain',
                      d.pain,
                      (v) => edit(pain: v, clearPain: v == null),
                      'pain',
                    ),
                    for (final question in safetyQuestions.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(question.value),
                            Wrap(
                              spacing: 6,
                              children: [
                                for (final value in [null, false, true])
                                  ChoiceChip(
                                    key: Key(
                                      'flag_${question.key}_${value ?? 'unknown'}',
                                    ),
                                    label: Text(
                                      value == null
                                          ? 'Unknown'
                                          : value
                                          ? 'Yes'
                                          : 'No',
                                    ),
                                    selected: d.flags[question.key] == value,
                                    onSelected: (_) => edit(
                                      flags: {...d.flags, question.key: value},
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const Text(
                      'These are your reports. The server Safety Engine evaluates available information; this form does not classify medical risk.',
                    ),
                  ],
                ),
              ),
              _section(
                context,
                'Notes (optional)',
                TextField(
                  key: const Key('observationNotes'),
                  controller: notes,
                  minLines: 2,
                  maxLines: 5,
                  maxLength: 1500,
                  onChanged: (value) => edit(note: value),
                  decoration: const InputDecoration(
                    hintText:
                        'Anything you want to remember about this observation?',
                  ),
                ),
              ),
              DermaireCard(
                child: ExpansionTile(
                  title: const Text('Photo quality check — separate'),
                  subtitle: const Text(
                    'An uploaded capture is not linked to this observation by this flow.',
                  ),
                  expansionAnimationStyle: EntryMotion.reduced(context)
                      ? AnimationStyle.noAnimation
                      : const AnimationStyle(
                          duration: Duration(milliseconds: 180),
                        ),
                  children: [GuidedCaptureEntry(state: widget.state)],
                ),
              ),
              EntryPress(
                child: FilledButton(
                  key: const Key('reviewObservation'),
                  onPressed: review,
                  child: const Text('Review observation'),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (active) widget.onHistory();
                },
                child: const Text('View saved observations'),
              ),
            ] else if (phase == ObservationPhase.review) ...[
              _section(context, 'Review before saving', _draftReview(d)),
              const Text(
                'This sends a report-only observation. It does not create measurements or confirm today’s Home completion.',
              ),
              const SizedBox(height: 12),
              EntryPress(
                child: FilledButton(
                  key: const Key('submitObservation'),
                  onPressed: () => c.submit(generation: generation),
                  child: const Text('Save observation'),
                ),
              ),
              TextButton(
                key: const Key('editObservation'),
                onPressed: () => c.edit(d, generation: generation),
                child: const Text('Edit observations'),
              ),
            ] else if (phase == ObservationPhase.submitting) ...[
              Semantics(
                liveRegion: true,
                child: const Text(
                  'Submitting your observation…',
                  key: Key('observationSubmitting'),
                ),
              ),
              if (!EntryMotion.reduced(context))
                const LinearProgressIndicator(),
              const Text(
                'Saving is not confirmed yet. This request is sent once; it will not be automatically repeated.',
              ),
            ] else if (phase == ObservationPhase.confirmed &&
                c.saved != null) ...[
              Semantics(
                liveRegion: true,
                child: Column(
                  key: const Key('observationReceipt'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Observation saved',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      c.confirmedByHistory
                          ? 'Confirmed by exact server history ID and recorded fields.'
                          : 'Confirmed by the server save response.',
                    ),
                    ObservationRecordCard(record: c.saved!),
                  ],
                ),
              ),
              const Text(
                'Saving a report does not establish clinical improvement, create measurements or complete the metric-based Home/baseline. Those projections remain server-authoritative.',
              ),
              FilledButton(
                onPressed: () {
                  if (active) widget.onHistory();
                },
                child: const Text('View saved observations'),
              ),
              if (widget.onContext != null)
                OutlinedButton(
                  onPressed: () {
                    if (active) widget.onContext?.call();
                  },
                  child: const Text("View or edit today's context"),
                ),
              TextButton(
                onPressed: startNew,
                child: const Text('Start another observation'),
              ),
            ] else if (phase == ObservationPhase.uncertain) ...[
              const Text(
                'Save outcome uncertain',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              OutlinedButton(
                key: const Key('reconcileObservation'),
                onPressed: c.historyPhase == ObservationHistoryPhase.loading
                    ? null
                    : () => c.reconcile(generation: generation),
                child: const Text('Refresh history to check'),
              ),
              if (c.historyError != null) Text(c.historyError!),
              if (c.historyPhase == ObservationHistoryPhase.loading)
                const Text('Reading history — no observation is being resent.'),
              TextButton(
                onPressed: () {
                  if (active) widget.onHistory();
                },
                child: const Text('View saved observations'),
              ),
              TextButton(
                key: const Key('startSeparateObservation'),
                onPressed: startNew,
                child: const Text('Start a separate observation'),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String title, Widget child) =>
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );
  Widget _levels(
    String title,
    String? current,
    void Function(String?) change,
    String key,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final value in [null, ...observationLevels])
              ChoiceChip(
                key: Key('${key}_${value ?? 'unknown'}'),
                label: Text(value ?? 'Not reported'),
                selected: current == value,
                onSelected: (_) => change(value),
              ),
          ],
        ),
      ],
    ),
  );
  Widget _draftReview(ObservationDraft d) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Your reported change: ${d.change}'),
      Text('Reported time: ${d.moment}'),
      Text(
        'Selected concerns: ${d.symptoms.isEmpty ? 'Not reported' : d.symptoms.join(', ')}',
      ),
      Text('Routine: ${d.routine ?? 'Not reported'}'),
      Text(
        'Severity: ${d.severity ?? 'Unknown'} · Pain: ${d.pain ?? 'Unknown'}',
      ),
      for (final entry in safetyQuestions.entries)
        Text(
          '${entry.value}: ${d.flags[entry.key] == null
              ? 'Unknown'
              : d.flags[entry.key]!
              ? 'Yes'
              : 'No'}',
        ),
      Text('Notes: ${d.submittedNotes ?? 'Not reported'}'),
    ],
  );
}

class ObservationRecordCard extends StatelessWidget {
  const ObservationRecordCard({super.key, required this.record});
  final ObservationRecord record;
  @override
  Widget build(BuildContext context) {
    final report = record.report;
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clinicalTime(record.createdAt),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            'Server record ID: ${record.id}',
            style: TextStyle(
              fontSize: 12,
              color: EntryTokens.of(context).secondary,
            ),
          ),
          Text('Reported time: ${record.moment}'),
          Text(
            report == null
                ? 'Overall change: not reported'
                : 'User reported: ${report.change}',
          ),
          if (report != null) ...[
            if (report.unsupported)
              const Text(
                'Unsupported recorded values are shown as returned; they are not interpreted.',
              ),
            Text(
              'Selected concerns: ${report.symptoms.isEmpty ? 'Not reported' : report.symptoms.join(', ')}',
            ),
            Text('Routine: ${report.routine ?? 'not reported'}'),
            if (report.safety.isNotEmpty)
              ExpansionTile(
                title: const Text('Recorded safety observations'),
                expansionAnimationStyle: EntryMotion.reduced(context)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 180),
                      ),
                children: [
                  Text(
                    'Severity: ${report.safety['severity'] ?? 'Unknown'} · Pain: ${report.safety['pain'] ?? 'Unknown'}',
                  ),
                  for (final entry in safetyQuestions.entries)
                    Text(
                      '${entry.value}: ${report.safety[entry.key] == null
                          ? 'Unknown'
                          : report.safety[entry.key] == true
                          ? 'Yes'
                          : 'No'}',
                    ),
                ],
              ),
          ],
          if (record.kind == ObservationKind.reportOnly)
            const Text('User-reported observation — no measurements recorded.')
          else if (record.kind == ObservationKind.unsupported)
            const Text(
              'Measurement source is unsupported or unavailable; no confirmed measurements are displayed.',
            )
          else
            Text(
              '${record.kind == ObservationKind.manual ? 'User-entered tracking metrics' : 'Nonclinical image estimates'}: hydration ${record.scores['hydration']}, redness ${record.scores['redness']}, texture ${record.scores['texture']}. These are not clinical assessments.',
            ),
          if (record.notes != null) Text('User notes: ${record.notes}'),
          if (record.imageEndpoint != null)
            const Text(
              'Server-linked check-in photo recorded. Standalone captures are separate.',
            ),
          if (record.contextDate != null)
            Text(
              'Daily context: ${record.contextDate} · ${record.contextLinked ? 'linked' : 'not linked at submission'}',
            ),
        ],
      ),
    );
  }
}

class ObservationHistoryScreen extends StatefulWidget {
  const ObservationHistoryScreen({
    super.key,
    required this.state,
    required this.onRecord,
  });
  final DermaireState state;
  final Future<void> Function() onRecord;
  @override
  State<ObservationHistoryScreen> createState() =>
      _ObservationHistoryScreenState();
}

class _ObservationHistoryScreenState extends State<ObservationHistoryScreen> {
  late final int generation;
  ObservationController get c => widget.state.observations;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    c.addListener(changed);
    c.begin(generation: generation);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ApiService.instance.isCurrentSession(generation)) {
        c.loadHistory(generation: generation);
      }
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ApiService.instance.isCurrentSession(generation) || !c.current) {
      return const DermairePage(
        title: 'History session ended',
        children: [
          Text(
            'Sign in and confirm safety acceptance to view your own observations.',
          ),
        ],
      );
    }
    final rows = c.rows;
    return DermairePage(
      eyebrow: 'Longitudinal skin history',
      title: 'Your observations',
      children: [
        if (c.historyPhase == ObservationHistoryPhase.loading) ...[
          const Text('Loading saved observations…'),
          if (!EntryMotion.reduced(context)) const CircularProgressIndicator(),
        ],
        if (c.historyError != null)
          Semantics(liveRegion: true, child: Text(c.historyError!)),
        if (c.historyStale)
          const Text(
            'Previously retrieved history — current records are unconfirmed.',
          ),
        if (c.historyPhase == ObservationHistoryPhase.ready &&
            rows?.isEmpty == true)
          const Text(
            'No saved observations yet. Record your first observation.',
          ),
        ...?rows?.map(
          (row) => ObservationRecordCard(key: ValueKey(row.id), record: row),
        ),
        if (c.saved != null &&
            c.historyPhase == ObservationHistoryPhase.ready &&
            rows?.any((r) => r.id == c.saved!.id) != true)
          const Text(
            'The save response confirmed your record, but this history read does not show it yet. Refresh history; do not resend the write.',
          ),
        OutlinedButton(
          key: const Key('refreshObservations'),
          onPressed: c.historyPhase == ObservationHistoryPhase.loading
              ? null
              : () => c.loadHistory(generation: generation),
          child: const Text('Refresh history'),
        ),
        FilledButton(
          onPressed: () async {
            if (!ApiService.instance.isCurrentSession(generation)) return;
            await widget.onRecord();
            if (mounted && ApiService.instance.isCurrentSession(generation)) {
              c.loadHistory(generation: generation);
            }
          },
          child: const Text('Record an observation'),
        ),
      ],
    );
  }
}
