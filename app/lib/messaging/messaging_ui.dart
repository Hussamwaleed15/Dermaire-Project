import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../integration/private_view.dart';
import 'messaging_controller.dart';
import 'messaging_models.dart';
import 'anchored_conversation.dart';

class CareThreadsScreen extends StatefulWidget {
  const CareThreadsScreen({super.key, this.patient});
  final String? patient;
  @override
  State<CareThreadsScreen> createState() => _CareThreadsState();
}

class _CareThreadsState extends State<CareThreadsScreen> {
  late ThreadsController controller = ThreadsController(
    patient: widget.patient,
  );
  @override
  void didUpdateWidget(covariant CareThreadsScreen old) {
    super.didUpdateWidget(old);
    if (old.patient != widget.patient) {
      controller = ThreadsController(patient: widget.patient);
    }
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) => DermairePage(
      eyebrow: 'Connected care',
      title: 'Care conversations',
      subtitle:
          'Private participant messages. Not an emergency service or a replacement for clinical care.',
      children: [
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh conversations'),
        ),
        if (c.busy) const Text('Reading authorized conversations…'),
        if (c.error != null) Text(c.error!),
        if (!c.busy && c.error == null && c.threads.isEmpty)
          const Text('No current consented conversations returned.'),
        for (final thread in c.threads)
          DermaireCard(
            onTap: () =>
                openEntry(context, CareConversationScreen(thread: thread)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.role == 'patient'
                      ? 'Doctor account ${thread.doctor}'
                      : 'Patient account ${thread.patient}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text('Conversation opened ${clinicalTime(thread.createdAt)}'),
                Text('Latest recorded sequence: ${thread.latest}'),
                const Text(
                  'Original grant and messaging consent are checked on every read.',
                ),
              ],
            ),
          ),
        if (c.next != null)
          OutlinedButton(
            onPressed: c.busy ? null : () => c.load(more: true),
            child: const Text('Load more conversations'),
          ),
        if (c.role == 'patient') ...[
          const Divider(),
          const Text(
            'Start a conversation only after explicit consent. Withdrawing closes this conversation; another grant does not reopen it.',
          ),
          for (final grant in c.grants)
            _EnrollConversation(
              key: ValueKey(grant['id']),
              controller: c,
              grant: grant['id'] as String,
              doctor: grant['doctor_id'] as String,
            ),
        ],
      ],
    ),
  );
}

class _EnrollConversation extends StatefulWidget {
  const _EnrollConversation({
    super.key,
    required this.controller,
    required this.grant,
    required this.doctor,
  });
  final ThreadsController controller;
  final String grant, doctor;
  @override
  State<_EnrollConversation> createState() => _EnrollConversationState();
}

class _EnrollConversationState extends State<_EnrollConversation> {
  bool consent = false;
  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          onChanged: widget.controller.busy
              ? null
              : (v) => setState(() => consent = v == true),
          title: Text(
            'Allow care messages with doctor account ${widget.doctor}',
          ),
          subtitle: const Text(
            'Separate from safety, image viewing and export permission.',
          ),
        ),
        FilledButton(
          onPressed: !consent || widget.controller.busy
              ? null
              : () async {
                  final c = widget.controller;
                  final thread = await c.enroll(widget.grant);
                  if (!context.mounted ||
                      !c.current ||
                      ModalRoute.of(context)?.isCurrent != true) {
                    return;
                  }
                  if (thread != null) {
                    setState(() => consent = false);
                    await openEntry(
                      context,
                      CareConversationScreen(thread: thread),
                    );
                  }
                },
          child: const Text('Consent and open conversation'),
        ),
      ],
    ),
  );
}

class CareConversationScreen extends StatefulWidget {
  const CareConversationScreen({super.key, required this.thread});
  final CareThread thread;
  @override
  State<CareConversationScreen> createState() => _CareConversationState();
}

class _CareConversationState extends State<CareConversationScreen> {
  CareThread get thread => widget.thread;
  late ConversationController controller = ConversationController(thread);
  @override
  void didUpdateWidget(covariant CareConversationScreen old) {
    super.didUpdateWidget(old);
    if (old.thread != widget.thread) {
      controller = ConversationController(thread);
    }
  }

  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    unavailableBuilder: (context, c) => DermairePage(
      title: 'Messaging permission',
      children: [
        const Text(
          'Conversation content is unavailable. You may withdraw your own messaging consent without accepting a new policy.',
        ),
        if (c.error != null) Text(c.error!),
        if (c.role == 'patient' && c.thread.patient == c.owner)
          TextButton(
            onPressed: c.busy ? null : c.withdraw,
            child: const Text('Withdraw messaging consent'),
          ),
      ],
    ),
    builder: (context, c) => AnchoredConversation(
      key: ValueKey('messages:${c.generation}:${thread.id}'),
      messages: c.messages,
      owner: c.owner,
      role: c.role,
      peerRead: c.role == 'patient' ? c.doctorRead : c.patientRead,
      header: [
        const Eyebrow('Consented care conversation'),
        Text(
          c.role == 'patient'
              ? 'Messages with your doctor'
              : 'Messages with patient',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text(
          'Not monitored for emergencies. Messages are participant-authored; they do not establish a diagnosis or medical clearance.',
        ),
        const SizedBox(height: 18),
        Text('Patient ${thread.patient} · Doctor ${thread.doctor}'),
        OutlinedButton(
          onPressed: c.busy ? null : c.refresh,
          child: const Text('Refresh messages'),
        ),
        if (c.busy)
          Semantics(
            liveRegion: true,
            child: Text('Confirming conversation state…'),
          ),
        if (c.error != null) Semantics(liveRegion: true, child: Text(c.error!)),
        if (c.outcome != null)
          Semantics(liveRegion: true, child: Text(c.outcome!)),
        if (c.hasEarlier)
          OutlinedButton(
            onPressed: c.busy ? null : c.earlier,
            child: const Text('Load earlier messages'),
          ),
        if (c.complete && c.messages.isEmpty)
          const Text(
            'No messages yet. Send only information you choose to share.',
          ),
        const Text(
          'Messages are grouped by UTC day. Read acknowledgements reflect saved in-app reading state.',
        ),
      ],
      footer: [
        if (c.messages.length >= 500)
          const Text('Displaying a bounded window of 500 messages.'),
        OutlinedButton(
          onPressed: c.busy || c.messages.isEmpty ? null : c.markRead,
          child: const Text('Acknowledge visible messages read'),
        ),
        if (c.pending != null) ...[
          const Text(
            'An original send is unresolved. Its body and key are retained only for this authenticated session.',
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(),
            child: const Text('Check original send'),
          ),
          OutlinedButton(
            onPressed: c.busy ? null : () => c.reconcile(retryOriginal: true),
            child: const Text('Reconcile, then retry original send if unknown'),
          ),
        ] else
          _MessageComposer(
            key: ValueKey('${c.generation}:${thread.id}'),
            controller: c,
          ),
        if (c.role == 'patient')
          TextButton(
            onPressed: c.busy
                ? null
                : () async {
                    if (await c.withdraw() && context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
            child: const Text('Withdraw messaging consent'),
          ),
        const Text(
          'A saved message is not push delivery or a guaranteed response. Pull current state using Refresh messages.',
        ),
      ],
    ),
  );
}

class _MessageComposer extends StatefulWidget {
  const _MessageComposer({super.key, required this.controller});
  final ConversationController controller;
  @override
  State<_MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<_MessageComposer> {
  final text = TextEditingController();
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        key: const Key('careMessageBody'),
        controller: text,
        maxLength: 4000,
        minLines: 2,
        maxLines: 6,
        enabled: !widget.controller.busy && widget.controller.complete,
        decoration: const InputDecoration(
          labelText: 'Message',
          helperText: 'No emergency response or delivery guarantee',
        ),
      ),
      FilledButton(
        key: const Key('careMessageSend'),
        onPressed: widget.controller.busy || !widget.controller.complete
            ? null
            : () async {
                final c = widget.controller;
                final result = await c.send(text.text);
                if (context.mounted &&
                    c.current &&
                    ModalRoute.of(context)?.isCurrent == true &&
                    result) {
                  text.clear();
                }
              },
        child: const Text('Send message'),
      ),
    ],
  );
}
