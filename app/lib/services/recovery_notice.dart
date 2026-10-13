import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';

/// Feedback for an actual read/uncertain write. Refresh only invokes the caller's
/// guarded GET operation; this widget never replays or confirms a mutation.
class RecoveryNotice extends StatelessWidget {
  const RecoveryNotice({
    super.key,
    this.message,
    this.messageKey,
    this.hasPreviousData = false,
    this.confirmedAt,
    this.uncertainWrite = false,
    this.busy = false,
    this.onRefresh,
    this.refreshLabel = 'Refresh',
  });
  final String? message;
  final Key? messageKey;
  final bool hasPreviousData;
  final DateTime? confirmedAt;
  final bool uncertainWrite;
  final bool busy;
  final VoidCallback? onRefresh;
  final String refreshLabel;

  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            message ??
                (busy
                    ? 'Waiting for server information…'
                    : 'Review current information'),
            key: messageKey,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (hasPreviousData) ...[
          const SizedBox(height: 8),
          const Text(
            'Previously confirmed data may be stale. Changes are unavailable until refresh.',
          ),
        ],
        if (confirmedAt != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last confirmed read: ${confirmedAt!.toUtc().toIso8601String().substring(0, 16).replaceFirst('T', ' ')} UTC. This is a read time, not clinical clearance.',
          ),
        ],
        if (uncertainWrite) ...[
          const SizedBox(height: 8),
          const Text(
            'A previous change is still unconfirmed. Refresh does not resend it or prove it succeeded.',
          ),
        ],
        if (busy) ...[
          const SizedBox(height: 12),
          if (EntryMotion.reduced(context))
            const Text('Waiting for the server…')
          else
            const LinearProgressIndicator(
              semanticsLabel: 'Waiting for server information',
            ),
        ],
        if (onRefresh != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: busy ? null : onRefresh,
            child: Text(refreshLabel),
          ),
        ],
      ],
    ),
  );
}
