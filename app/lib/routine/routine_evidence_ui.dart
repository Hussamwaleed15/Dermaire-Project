import 'package:flutter/material.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../dermaire_widgets.dart';
import '../integration/private_view.dart';
import 'routine_evidence_controller.dart';

class RoutineEvidenceScreen extends StatefulWidget {
  const RoutineEvidenceScreen({super.key, this.entry});
  final String? entry;
  @override
  State<RoutineEvidenceScreen> createState() => _RoutineEvidenceState();
}

class _RoutineEvidenceState extends State<RoutineEvidenceScreen> {
  late RoutineEvidenceController controller = RoutineEvidenceController(
    entry: widget.entry,
  );
  final zone = TextEditingController();
  bool consent = false;
  @override
  void didUpdateWidget(covariant RoutineEvidenceScreen old) {
    super.didUpdateWidget(old);
    if (old.entry != widget.entry) {
      zone.clear();
      consent = false;
      controller = RoutineEvidenceController(entry: widget.entry);
    }
  }

  @override
  void dispose() {
    zone.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    final submitted = zone.text.trim(), c = controller;
    if (!consent || !c.current || c.busy) return;
    await c.changeZone(submitted);
    if (mounted && identical(c, controller)) setState(() => consent = false);
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Recorded routine evidence',
      title: 'Routine history & calendar',
      children: [
        const Text(
          'Prospective configuration events only. No historical backfill. A recorded change is not verification of your current routine or a medical outcome.',
        ),
        OutlinedButton(
          key: const Key('refreshRoutineEvidence'),
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh history & policy'),
        ),
        if (c.busy) const Text('Reading server evidence…'),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        if (c.policy case final policy?)
          DermaireCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Current timezone: ${policy.zone}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Policy revision: ${policy.revision}'),
                Text('Local date reported by server: ${policy.localToday}'),
                Text(
                  policy.effective == null
                      ? 'Default UTC policy; no recorded change.'
                      : 'Effective: ${clinicalTime(policy.effective!)}',
                ),
                const Text(
                  'Adherence dates remain UTC. Old reports are not relabeled. Reminder timezone, overlap and gap rules stay independently approved.',
                ),
                TextField(
                  key: const Key('routineCalendarZone'),
                  controller: zone,
                  enabled: !c.busy && c.pending == null,
                  decoration: const InputDecoration(
                    labelText: 'New IANA timezone',
                    hintText: 'Example: Africa/Cairo',
                  ),
                  onChanged: (_) => setState(() => consent = false),
                ),
                CheckboxListTile(
                  key: const Key('routineCalendarConsent'),
                  value: consent,
                  title: const Text(
                    'Apply this timezone prospectively. Existing UTC adherence and reminder schedules are unchanged.',
                  ),
                  onChanged: c.busy || c.pending != null
                      ? null
                      : (v) => setState(() => consent = v == true),
                ),
                FilledButton(
                  key: const Key('saveRoutineCalendar'),
                  onPressed: !consent || c.busy || c.pending != null
                      ? null
                      : submit,
                  child: const Text('Apply timezone policy'),
                ),
              ],
            ),
          ),
        if (c.pending case final original?)
          DermaireCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Original timezone update remains unconfirmed. No new policy request will replace it.',
                ),
                const Text(
                  'The exact original draft is retained for authorized review in this session.',
                ),
                const Text(
                  'Refresh first. A newer current revision fences the old precondition; it is not an original operation receipt.',
                ),
                if (c.policy != null)
                  OutlinedButton(
                    onPressed: c.busy
                        ? null
                        : () => c.changeZone(
                            original.body['timezone'] as String,
                            retryOriginal: true,
                          ),
                    child: const Text('Retry exact original timezone update'),
                  ),
              ],
            ),
          ),
        if (c.page case final history?) ...[
          Text('History cutoff: ${clinicalTime(history.asOf)}'),
          Text(
            history.coverageSince == null
                ? 'No prospective evidence returned. Earlier routine history is unknown.'
                : 'Coverage starts: ${clinicalTime(history.coverageSince!)}',
          ),
          const Text(
            'Timestamp cutoff, not an atomic snapshot. Event history does not establish current clinical clearance.',
          ),
          if (c.events.isEmpty)
            const Text('No recorded routine changes in this history.'),
          for (final event in c.events)
            DermaireCard(
              key: ValueKey(event.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    event.kind.replaceAll('_', ' '),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(event.name ?? 'Product evidence unavailable'),
                  Text(
                    '${clinicalTime(event.created)} · ${event.schedule} · revision ${event.revision}',
                  ),
                  Text(
                    event.active
                        ? 'Recorded active configuration'
                        : 'Recorded stopped configuration',
                  ),
                  Text('Writer: ${event.writer}'),
                  Text(
                    event.actor == null
                        ? 'Actor attribution unavailable'
                        : 'Recorded actor: ${event.actor}',
                  ),
                ],
              ),
            ),
          if (c.more)
            OutlinedButton(
              onPressed: c.busy ? null : c.loadMore,
              child: const Text('Load earlier routine changes'),
            ),
        ],
      ],
    ),
  );
}
