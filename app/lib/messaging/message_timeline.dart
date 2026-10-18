import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import 'messaging_models.dart';

String messageUtcDay(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);
String messageUtcClock(DateTime value) =>
    '${value.toUtc().toIso8601String().substring(11, 19)} UTC';

/// Presentation only: retain authenticated server sequence order and peer read
/// watermark. Day grouping never invents delivery or reorders by device clocks.
List<Widget> buildCareMessageTimeline({
  required List<CareMessage> messages,
  required String owner,
  required String role,
  required int peerRead,
}) => [
  for (var i = 0; i < messages.length; i++)
    CareMessageRow(
      key: ValueKey(messages[i].id),
      message: messages[i],
      owner: owner,
      role: role,
      peerRead: peerRead,
      startsDay:
          i == 0 ||
          messageUtcDay(messages[i].createdAt) !=
              messageUtcDay(messages[i - 1].createdAt),
    ),
];

class CareMessageRow extends StatelessWidget {
  const CareMessageRow({
    super.key,
    required this.message,
    required this.owner,
    required this.role,
    required this.peerRead,
    required this.startsDay,
  });
  final CareMessage message;
  final String owner, role;
  final int peerRead;
  final bool startsDay;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (startsDay)
        Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Messages · ${messageUtcDay(message.createdAt)} UTC',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ),
      bubble(context, message),
    ],
  );
  Widget bubble(BuildContext context, CareMessage message) => Align(
    key: ValueKey(message.id),
    alignment: message.actor == owner
        ? Alignment.centerRight
        : Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: DermaireCard(
        color: message.actor == owner
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.actor == owner
                  ? 'You'
                  : role == 'patient'
                  ? 'Doctor'
                  : 'Patient',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(message.body),
            Semantics(
              label:
                  'Saved ${messageUtcDay(message.createdAt)} ${messageUtcClock(message.createdAt)}, server sequence ${message.sequence}',
              excludeSemantics: true,
              child: Text(
                '${messageUtcClock(message.createdAt)} · sequence ${message.sequence}',
              ),
            ),
            if (message.actor == owner && peerRead >= message.sequence)
              const Text('Acknowledged read in app'),
          ],
        ),
      ),
    ),
  );
}
