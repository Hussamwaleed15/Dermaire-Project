import '../agent/server_agent_ui.dart';
import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../integration/private_view.dart';
import '../plans/plan_ui.dart';
import '../messaging/messaging_ui.dart';
import 'notification_availability.dart';
import 'inbox_controller.dart';
import 'inbox_models.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});
  @override
  State<NotificationInboxScreen> createState() => _InboxState();
}

class _InboxState extends State<NotificationInboxScreen> {
  final controller = InboxController();
  String? category;
  bool unreadOnly = false;
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) {
      final visible = filterLoadedNotices(
        c.notices,
        category: category,
        unreadOnly: unreadOnly,
      );
      return DermairePage(
        eyebrow: 'Your updates',
        title: 'Notification inbox',
        subtitle:
            '${c.unreadLoaded} unread in loaded items. Refresh to check current authorized updates.',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: c.busy ? null : c.refresh,
                child: const Text('Refresh inbox'),
              ),
              OutlinedButton(
                onPressed: () =>
                    openEntry(context, const NotificationPreferencesScreen()),
                child: const Text('Preferences'),
              ),
              OutlinedButton(
                onPressed: () =>
                    openEntry(context, const NotificationAvailabilityScreen()),
                child: const Text('Device delivery'),
              ),
            ],
          ),
          const Text(
            'Device push delivery is unavailable. App read acknowledgments do not prove delivery. No sensitive notification bodies are stored on this device.',
          ),
          if (c.busy) const Text('Reading authorized updates…'),
          if (c.error != null)
            Semantics(liveRegion: true, child: Text(c.error!)),
          if (c.outcome != null)
            Semantics(liveRegion: true, child: Text(c.outcome!)),
          Wrap(
            spacing: 8,
            children: [
              for (final k in [null, ...noticeKinds])
                ChoiceChip(
                  label: Text(k?.replaceAll('_', ' ') ?? 'All'),
                  selected: k == category,
                  onSelected: (_) => setState(() => category = k),
                ),
            ],
          ),
          FilterChip(
            label: Text('Unread only (${c.unreadLoaded} loaded)'),
            selected: unreadOnly,
            onSelected: (v) => setState(() => unreadOnly = v),
          ),
          Text(
            '${visible.length} matching loaded updates. Counts do not include unloaded pages.',
          ),
          if (!c.busy &&
              c.error == null &&
              c.notices.isNotEmpty &&
              visible.isEmpty)
            const Text(
              'No loaded updates match this filter. Change filters or load earlier updates.',
            ),
          if (!c.busy && c.error == null && c.notices.isEmpty)
            const Text('No current notifications returned.'),
          for (final (index, n) in visible.indexed) ...[
            if (index == 0 ||
                noticeUtcDay(n) != noticeUtcDay(visible[index - 1]))
              Semantics(
                header: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Due · ${noticeUtcDay(n)} UTC',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.kind.replaceAll('_', ' '),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(n.read == null ? 'Unread in app' : 'Read in app'),
                  Text('Created: ${clinicalTime(n.created)}'),
                  Text('Due: ${clinicalTime(n.due)}'),
                  if (n.read != null)
                    Text('App read time: ${clinicalTime(n.read!)}'),
                  Text('Source: ${n.source} · revision ${n.revision}'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: c.busy
                            ? null
                            : () => c.mark(n, read: n.read == null),
                        child: Text(
                          n.read == null ? 'Mark read' : 'Mark unread',
                        ),
                      ),
                      if (['follow_up', 'comparison'].contains(n.kind))
                        OutlinedButton(
                          onPressed: () => openEntry(
                            context,
                            ClinicalPlanScreen(id: n.source),
                          ),
                          child: const Text('Open current plan'),
                        ),
                      if (n.kind == 'message')
                        OutlinedButton(
                          onPressed: () =>
                              openEntry(context, const CareThreadsScreen()),
                          child: const Text('Open care conversations'),
                        ),
                      if (n.kind == 'routine' && c.role == 'patient')
                        OutlinedButton(
                          onPressed: () => openEntry(
                            context,
                            NotificationPreferencesScreen(entryId: n.source),
                          ),
                          child: const Text('Open routine reminder'),
                        ),
                    ],
                  ),
                  if (n.kind == 'message')
                    const Text(
                      'The notification references a message. Select its authorized conversation to read current history.',
                    ),
                  if (n.kind == 'agent_request')
                    OutlinedButton(
                      onPressed: () => openEntry(
                        context,
                        c.role == 'doctor'
                            ? const ClinicianRequestsScreen()
                            : const ServerAgentScreen(),
                      ),
                      child: const Text('Open authorized Agent requests'),
                    ),
                ],
              ),
            ),
          ],
          if (c.next != null)
            OutlinedButton(
              onPressed: c.busy ? null : () => c.more(),
              child: const Text('Load earlier updates'),
            ),
          const Text(
            'Notification history',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          for (final n in c.history)
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${n.kind.replaceAll('_', ' ')} · ${n.state}'),
                  Text('Due: ${clinicalTime(n.due)}'),
                  if (n.jobs.isEmpty) const Text('No transport job returned.'),
                  for (final job in n.jobs) ...[
                    Text(
                      'Transport state: ${job['state']} · attempts ${job['attempts']}',
                    ),
                    for (final a in job['attempt_history'] as List)
                      Text('Attempt ${a['number']}: ${a['state']}'),
                  ],
                  const Text('Device delivery is unconfirmed.'),
                ],
              ),
            ),
          if (c.nextHistory != null)
            OutlinedButton(
              onPressed: c.busy ? null : () => c.more(history: true),
              child: const Text('Load earlier history'),
            ),
          const Text(
            'Updates and reminders do not replace clinical care or emergency guidance.',
          ),
        ],
      );
    },
  );
}

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key, this.entryId});
  final String? entryId;
  @override
  State<NotificationPreferencesScreen> createState() => _PreferencesState();
}

class _PreferencesState extends State<NotificationPreferencesScreen> {
  late NoticeSettingsController controller = NoticeSettingsController(
    entryId: widget.entryId,
  );
  @override
  void didUpdateWidget(covariant NotificationPreferencesScreen old) {
    super.didUpdateWidget(old);
    if (old.entryId != widget.entryId) {
      controller = NoticeSettingsController(entryId: widget.entryId);
    }
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    unavailableBuilder: (context, c) => DermairePage(
      eyebrow: 'Consent withdrawal',
      title: 'Notification settings unavailable',
      children: [
        const Text(
          'Verify the current safety policy before reading settings. You may withdraw all notification preferences using the last verified revision.',
        ),
        if (c.error != null) Text(c.error!),
        if (c.outcome != null) Text(c.outcome!),
        OutlinedButton(
          onPressed: c.canDisable ? c.disableAll : null,
          child: const Text('Disable all notification preferences'),
        ),
      ],
    ),
    builder: (context, c) => DermairePage(
      eyebrow: 'Consent & schedules',
      title: widget.entryId == null
          ? 'Notification preferences'
          : 'Routine reminder',
      children: [
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Read current settings'),
        ),
        if (c.busy) const Text('Confirming server settings…'),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        if (widget.entryId == null)
          OutlinedButton(
            onPressed: c.canDisable ? c.disableAll : null,
            child: const Text('Disable all notification preferences'),
          ),
        if (c.pending != null)
          OutlinedButton(
            onPressed: c.busy ? null : c.retryOriginal,
            child: const Text('Retry original settings'),
          ),
        if (c.value != null)
          _SettingsForm(
            key: ValueKey('${c.path}:${c.value!.revision}'),
            controller: c,
            value: c.value!,
          ),
        const Text(
          'Disabling a category cancels outstanding notices. Enabling it again does not restore canceled reminders. Delivery is unavailable; saved preferences do not register this device.',
        ),
        if (widget.entryId != null)
          const Text(
            'Enable routine notifications first. The server requires an active owned routine. Only future scheduled occurrences apply; UTC adherence days are not relabeled.',
          ),
      ],
    ),
  );
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({
    super.key,
    required this.controller,
    required this.value,
  });
  final NoticeSettingsController controller;
  final NoticeSettings value;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late final zone = TextEditingController(
    text: widget.value.data['timezone'] as String? ?? 'UTC',
  );
  late final first = TextEditingController(
    text: clockMinute(
      (widget.value.data[widget.value.reminder ? 'am_minute' : 'quiet_start']
              as int?) ??
          (widget.value.reminder ? 480 : 0),
    ),
  );
  late final second = TextEditingController(
    text: clockMinute(
      (widget.value.data[widget.value.reminder ? 'pm_minute' : 'quiet_end']
              as int?) ??
          (widget.value.reminder ? 1200 : 0),
    ),
  );
  late final kinds = (widget.value.data['enabled_kinds'] as List? ?? [])
      .cast<String>()
      .toSet();
  late bool enabled = widget.value.data['enabled'] == true;
  late int fold = widget.value.data['fold'] as int? ?? 0;
  bool confirmed = false;
  String? validation;
  @override
  void dispose() {
    zone.dispose();
    first.dispose();
    second.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final a = parseClock(first.text), b = parseClock(second.text);
    if (a == null || b == null || zone.text.trim().isEmpty) {
      setState(() => validation = 'Enter HH:mm times and an IANA timezone.');
      return;
    }
    setState(() => validation = null);
    await widget.controller.save(
      widget.value.reminder
          ? {
              'enabled': enabled,
              'timezone': zone.text.trim(),
              'am_minute': a,
              'pm_minute': b,
              'fold': fold,
              'gap_policy': 'skip',
            }
          : {
              'enabled_kinds': noticeKinds.where(kinds.contains).toList(),
              'push_enabled': widget.value.data['push_enabled'] == true,
              'timezone': zone.text.trim(),
              'quiet_start': a,
              'quiet_end': b,
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller,
        reminder = widget.value.reminder,
        editable = !c.busy && c.pending == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Current server revision: ${widget.value.revision}'),
        if (reminder && widget.value.data['configured'] == false)
          const Text(
            'No saved reminder. Times below are editable draft suggestions.',
          ),
        if (reminder)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable this routine reminder'),
            value: enabled,
            onChanged: editable
                ? (v) => setState(() {
                    enabled = v!;
                    confirmed = false;
                  })
                : null,
          ),
        if (!reminder)
          for (final kind in noticeKinds)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(kind.replaceAll('_', ' ')),
              value: kinds.contains(kind),
              onChanged: editable
                  ? (v) => setState(() {
                      confirmed = false;
                      if (v!) {
                        kinds.add(kind);
                      } else {
                        kinds.remove(kind);
                      }
                    })
                  : null,
            ),
        TextField(
          controller: zone,
          onChanged: (_) => setState(() => confirmed = false),
          enabled: editable,
          decoration: const InputDecoration(
            labelText: 'IANA timezone',
            hintText: 'Africa/Cairo',
          ),
        ),
        TextField(
          controller: first,
          onChanged: (_) => setState(() => confirmed = false),
          enabled: editable,
          decoration: InputDecoration(
            labelText: reminder
                ? 'Morning time · HH:mm'
                : 'Quiet hours start · HH:mm',
          ),
        ),
        TextField(
          controller: second,
          onChanged: (_) => setState(() => confirmed = false),
          enabled: editable,
          decoration: InputDecoration(
            labelText: reminder
                ? 'Evening time · HH:mm'
                : 'Quiet hours end · HH:mm',
          ),
        ),
        if (reminder) ...[
          const Text(
            'Repeated clock time: choose the first or second occurrence. Missing clock times are skipped, never shifted.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final f in [0, 1])
                ChoiceChip(
                  label: Text(
                    f == 0 ? 'First occurrence' : 'Second occurrence',
                  ),
                  selected: fold == f,
                  onSelected: editable
                      ? (_) => setState(() {
                          fold = f;
                          confirmed = false;
                        })
                      : null,
                ),
            ],
          ),
        ],
        if (!reminder)
          Text(
            'Stored push preference: ${widget.value.data['push_enabled'] == true ? 'enabled' : 'disabled'}. This app cannot acquire a push token or enable device delivery.',
          ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('I consent to save these notification settings.'),
          value: confirmed,
          onChanged: editable ? (v) => setState(() => confirmed = v!) : null,
        ),
        if (validation != null) Text(validation!),
        FilledButton(
          onPressed: editable && confirmed ? save : null,
          child: const Text('Save settings'),
        ),
      ],
    );
  }
}
