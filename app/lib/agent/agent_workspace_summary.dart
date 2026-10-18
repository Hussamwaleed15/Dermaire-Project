import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import 'server_agent_models.dart';

class AgentWorkspaceSummary extends StatelessWidget {
  const AgentWorkspaceSummary({
    super.key,
    required this.session,
    required this.actions,
    required this.selected,
    required this.busy,
    required this.failed,
  });
  final BrokerSession? session;
  final List<BrokerAction> actions;
  final String? selected;
  final bool busy, failed;
  @override
  Widget build(BuildContext context) {
    final s = session;
    final label = busy
        ? 'Verifying session'
        : s != null
        ? s.fresh
              ? 'Active consented session'
              : 'Context needs refresh'
        : selected == null
        ? 'No session selected'
        : 'Session unavailable';
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(label, style: Theme.of(context).textTheme.titleLarge),
          ),
          if (s == null)
            Text(
              selected == null
                  ? 'Create a session with explicit consent to use supported workflows.'
                  : 'The selected session could not be verified. No previous context or request content is shown.',
            ),
          if (failed)
            const Text(
              'The latest server read failed. Refresh or use the separate withdrawal controls.',
            ),
          if (s != null) ...[
            Text(
              'Read permission: ${s.scopes.contains('longitudinal_read') ? 'Granted for this session' : 'Unavailable'}',
            ),
            Text(
              'Proposal permission: ${s.scopes.contains('proposal_actions') ? 'Granted for this session' : 'Not granted'}',
            ),
            Text('Consent expires: ${clinicalTime(s.expires)}'),
            Text('Context read: ${clinicalTime(s.contextAt)}'),
            Text('${s.toolCalls}/8 tool calls used'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final stage in BrokerActionStage.values)
                  if (actions.any((a) => a.stage == stage))
                    Chip(
                      label: Text(
                        '${stage.label}: ${actions.where((a) => a.stage == stage).length}',
                      ),
                    ),
              ],
            ),
          ],
          const Text(
            'Model replies are unavailable. A request or clinician decision does not execute medical care.',
          ),
          const Text(
            'Only references from this login are available. Cross-login session discovery is not supported.',
          ),
        ],
      ),
    );
  }
}
