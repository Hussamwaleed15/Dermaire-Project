import 'dart:convert';
import 'package:flutter/material.dart';
import 'experiment_controller.dart';
import '../services/api_service.dart';
import '../routine/routine_ui.dart';

class ExperimentsView extends StatefulWidget {
  const ExperimentsView({
    super.key,
    required this.controller,
    this.autoLoad = true,
    this.header,
  });
  final ExperimentController controller;
  final bool autoLoad;
  final Widget? header;
  @override
  State<ExperimentsView> createState() => _ExperimentsViewState();
}

class _ExperimentsViewState extends State<ExperimentsView> {
  @override
  void initState() {
    super.initState();
    if (widget.autoLoad &&
        widget.controller.rows == null &&
        !widget.controller.loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !widget.controller.loading &&
            widget.controller.rows == null) {
          widget.controller.refresh();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.header != null) widget.header!,
            Text(
              'Controlled experiments',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Change one routine variable. Results describe observations and associations, not diagnosis or causality.',
            ),
            if (c.loading) const LinearProgressIndicator(),
            if (c.error != null)
              Text(c.error!, key: const Key('experimentError')),
            OutlinedButton(
              onPressed: c.loading || c.saving ? null : c.refresh,
              child: const Text('Refresh experiments'),
            ),
            FilledButton(
              onPressed: c.loading || c.saving
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _DraftForm(controller: c),
                      ),
                    ),
              child: const Text('Plan one change'),
            ),
            if (c.rows?.isEmpty == true) const Text('No experiments yet.'),
            for (final row in c.rows ?? <Map<String, dynamic>>[])
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
                            MaterialPageRoute<void>(
                              builder: (_) => RoutineScreen(
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
                      if (row['status'] == 'draft')
                        TextButton(
                          onPressed: c.saving
                              ? null
                              : () => c.write('${row['id']}/activate', {}),
                          child: const Text('Activate today'),
                        ),
                      if ([
                        'active',
                        'paused',
                        'baseline',
                        'draft',
                      ].contains(row['status']))
                        TextButton(
                          onPressed: c.saving
                              ? null
                              : () => c.write('${row['id']}/finish', {
                                  'status': row['status'] == 'draft'
                                      ? 'cancelled'
                                      : 'stopped',
                                }),
                          child: Text(
                            row['status'] == 'draft'
                                ? 'Cancel draft'
                                : 'Stop experiment',
                          ),
                        ),
                      if (row['status'] == 'active' &&
                          row['engine_version'] == 2)
                        TextButton(
                          onPressed: c.saving
                              ? null
                              : () => c.write('${row['id']}/finish', {
                                  'status': 'completed',
                                }),
                          child: const Text('Complete elapsed experiment'),
                        ),
                      if (row['engine_version'] == 2 &&
                          [
                            'active',
                            'completed',
                            'stopped',
                          ].contains(row['status']))
                        TextButton(
                          onPressed: c.saving
                              ? null
                              : () => c.write('${row['id']}/evaluate', {}),
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
                          title: const Text(
                            'Evidence, comparison and source references',
                          ),
                          children: [
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(row['result']['result']),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _DraftForm extends StatefulWidget {
  const _DraftForm({required this.controller});
  final ExperimentController controller;
  @override
  State<_DraftForm> createState() => _DraftFormState();
}

class _DraftFormState extends State<_DraftForm> {
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
    load();
  }

  Future<void> load() async {
    try {
      final response =
          (await ApiService.instance.routineRequest('entries?active=true')
                  as List)
              .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() {
          entries = response;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Routine unavailable. Retry to choose a target.',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in [goal, notes, duration, date]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Plan one change')),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Add a new daily entry today for a start experiment, or choose an existing entry to stop or change its schedule. Activation applies the planned configuration. Stopping the experiment does not restore your previous routine.',
          ),
          if (error != null) ...[
            Text(error!),
            TextButton(onPressed: load, child: const Text('Retry routine')),
          ],
          if (entries == null && error == null) const LinearProgressIndicator(),
          if (entries?.isEmpty == true)
            const Text('Add an active routine entry in Products first.'),
          DropdownButtonFormField<String>(
            initialValue: entryId,
            decoration: const InputDecoration(labelText: 'One routine entry'),
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
            initialValue: type,
            items: [
              for (final v in ['start_entry', 'stop_entry', 'change_schedule'])
                DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))),
            ],
            onChanged: (v) => setState(() => type = v!),
          ),
          if (type != 'stop_entry')
            DropdownButtonFormField<String>(
              initialValue: schedule,
              items: [
                for (final v in ['AM', 'PM', 'BOTH'])
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) => setState(() => schedule = v!),
            ),
          DropdownButtonFormField<String>(
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
            controller: goal,
            decoration: const InputDecoration(
              labelText: 'Goal or question (optional)',
            ),
          ),
          TextField(
            controller: notes,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          if (widget.controller.error != null) Text(widget.controller.error!),
          FilledButton(
            onPressed: entryId == null || widget.controller.saving
                ? null
                : () async {
                    final success = await widget.controller.write('', {
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
                    });
                    if (success && context.mounted) Navigator.pop(context);
                  },
            child: const Text('Save draft on server'),
          ),
        ],
      ),
    ),
  );
}
