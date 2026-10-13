import 'package:flutter/material.dart';

import 'dermaire_state.dart';
import 'clinical/clinical_ui.dart';
import 'entry/entry_motion.dart';
import 'chat/chat_controller.dart';
import 'assistance/assistance_ui.dart';
import 'dermaire_widgets.dart';
import 'services/api_service.dart';

enum AssistantReplyKind { education, uncertainty, escalation }

class AssistantReply {
  const AssistantReply(this.text, this.kind);
  final String text;
  final AssistantReplyKind kind;
}

abstract final class SkinAssistantSafety {
  static const redFlags = [
    'difficulty breathing',
    'trouble breathing',
    'face swelling',
    'facial swelling',
    'swollen lips',
    'severe pain',
    'rapidly spreading',
    'bleeding',
    'infection',
    'صعوبة تنفس',
    'ضيق تنفس',
    'تورم الوجه',
    'تورم الشفاه',
    'ألم شديد',
    'انتشار سريع',
    'نزيف',
    'عدوى',
  ];

  static bool hasRedFlag(String message) {
    final normalized = message.trim().toLowerCase();
    return redFlags.any(normalized.contains);
  }

  static AssistantReply reply(String message) {
    if (hasRedFlag(message)) {
      return const AssistantReply(
        'Your symptoms may need urgent medical assessment. If you have trouble breathing, facial or lip swelling, severe pain, or a rapidly worsening reaction, contact emergency services now. You can also share your Dermaire report with your clinician.',
        AssistantReplyKind.escalation,
      );
    }
    final normalized = message.toLowerCase();
    if (normalized.contains('measurement') || normalized.contains('قياس')) {
      return const AssistantReply(
        'Measurements show changes compared with your own baseline. They are estimates affected by lighting and context, and they are not a diagnosis.',
        AssistantReplyKind.education,
      );
    }
    if (normalized.contains('product') || normalized.contains('منتج')) {
      return const AssistantReply(
        'Open Products, add the product and its active ingredients, then review the interaction check. Patch test new products and change one variable at a time.',
        AssistantReplyKind.education,
      );
    }
    return const AssistantReply(
      'I can explain Dermaire, products, journals and measurements. I cannot diagnose a condition or prescribe treatment. For a personal medical decision, contact a qualified clinician.',
      AssistantReplyKind.uncertainty,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.text,
    required this.fromUser,
    required this.kind,
  });
  final String text;
  final bool fromUser;
  final AssistantReplyKind kind;
}

class SkinAssistantScreen extends StatefulWidget {
  const SkinAssistantScreen({super.key, this.state, this.repository});
  final DermaireState? state;
  final PatientChatRepository? repository;
  @override
  State<SkinAssistantScreen> createState() => _SkinAssistantScreenState();
}

class _SkinAssistantScreenState extends State<SkinAssistantScreen> {
  late final DermaireState state;
  late final PatientChatController chat;
  final input = TextEditingController();
  final scroll = ScrollController();
  bool followEnd = true;
  @override
  void initState() {
    super.initState();
    state = widget.state ?? DermaireState();
    chat = PatientChatController(
      ApiService.instance,
      repository: widget.repository,
    )..addListener(changed);
  }

  void changed() {
    if (!chat.current) input.clear();
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients && followEnd) {
        if (EntryMotion.reduced(context)) {
          scroll.jumpTo(scroll.position.maxScrollExtent);
        } else {
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  Future<void> send() async {
    if (!chat.current || chat.busy) return;
    final value = input.text;
    if (value.trim().isNotEmpty &&
        value.trim().runes.length <= 1000 &&
        chat.turns.length < 20) {
      input.clear();
      followEnd = true;
    }
    await chat.send(value);
  }

  @override
  void dispose() {
    chat.removeListener(changed);
    chat.dispose();
    input.dispose();
    scroll.dispose();
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!chat.current) {
      return const DermairePage(
        title: 'Session ended',
        children: [
          Text(
            'Temporary chat messages have been cleared. Reopen after sign-in and safety acceptance.',
          ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dermaire guide'),
        actions: [
          IconButton(
            tooltip: 'Clear conversation',
            onPressed: chat.turns.isEmpty
                ? null
                : () {
                    input.clear();
                    chat.clear();
                  },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n is UserScrollNotification) {
                    followEnd = scroll.position.extentAfter < 100;
                  }
                  return false;
                },
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Temporary device view only. Each question is sent alone; earlier messages may not inform the next reply. No saved conversation, streaming, image analysis or automatic actions.',
                    ),
                    ClinicalHomePanel(controller: state.clinical),
                    if (chat.turns.isEmpty)
                      const DermaireCard(
                        child: Text(
                          'Ask about recorded changes, tracking, routines or questions for your clinician. This guide cannot diagnose or prescribe.',
                        ),
                      ),
                    for (final turn in chat.turns) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: DermaireCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('You'),
                              SelectableText(turn.question),
                              Text(
                                'Submitted on this device: ${clinicalTime(turn.submittedAt)}',
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (turn.response != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DermaireCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Dermaire informational response · ${turn.response!.kind}',
                                ),
                                AssistanceSafetySnapshot(
                                  response: turn.response!.assistance,
                                ),
                                SelectableText(turn.response!.textReply),
                                Text(
                                  'Received on this device: ${clinicalTime(turn.receivedAt!)}',
                                ),
                                ExpansionTile(
                                  title: const Text(
                                    'Response evidence and limits',
                                  ),
                                  expansionAnimationStyle:
                                      EntryMotion.reduced(context)
                                      ? AnimationStyle.noAnimation
                                      : const AnimationStyle(
                                          duration: Duration(milliseconds: 180),
                                        ),
                                  children: [
                                    AssistanceEvidence(
                                      response: turn.response!.assistance,
                                      showMessage: false,
                                      showSafety: false,
                                    ),
                                    Text(
                                      'Server compatibility source label: ${turn.response!.compatibilitySource}',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (turn.error != null)
                        DermaireCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                liveRegion: true,
                                child: Text(turn.error!),
                              ),
                              const Text(
                                'No reply confirmed. This question is not evidence of server persistence.',
                              ),
                              if (turn.attempts == 1 && !chat.busy)
                                OutlinedButton(
                                  onPressed: () => chat.retry(turn),
                                  child: const Text(
                                    'Retry once — may repeat the provider request',
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                    if (chat.busy)
                      Semantics(
                        liveRegion: true,
                        child: const Text('Waiting for the server response…'),
                      ),
                    if (chat.validation != null)
                      Semantics(
                        liveRegion: true,
                        child: Text(chat.validation!),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('assistantInput'),
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => send(),
                      decoration: const InputDecoration(
                        labelText: 'Message Dermaire',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send message',
                    onPressed: chat.busy ? null : send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
