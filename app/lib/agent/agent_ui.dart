import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import 'agent_controller.dart';
import 'agent_domain.dart';

/// Unwired prepared component. Synthetic proposals live only in tests. Never
/// mounted by Home/chat/nav; current assistant suggestions remain informational.
class AgentProposalCard extends StatelessWidget {
  const AgentProposalCard({super.key, required this.controller});
  final AgentController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final p = controller.proposal;
      if (!controller.current) {
        return const DermaireCard(
          child: Text(
            'Agent proposal cleared. Current account authorization is required.',
          ),
        );
      }
      if (p == null) {
        return DermaireCard(
          child: Semantics(
            liveRegion: true,
            child: Text(switch (controller.state) {
              AgentReadState.loading => 'Reading a server-confirmed proposal…',
              AgentReadState.stale =>
                'Proposal is stale, cancelled or superseded. No action is available.',
              AgentReadState.failed => 'Proposal could not be verified.',
              AgentReadState.empty => 'No proposal was returned.',
              _ =>
                'Future agent capability unavailable. No action or conversation memory is enabled.',
            }),
          ),
        );
      }
      return DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Proposed action',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('Source authority: ${p.authority.name}'),
            Text('Action: ${p.kind.name} · State: ${p.status.name}'),
            if (p.authority == AgentAuthority.aiSuggestion)
              const Text('AI suggestion is not a clinician instruction.'),
            if (p.forbiddenMedicalAction)
              const Text(
                'Medical authority or scheduling cannot be executed by this client. Clinician/backend review is required.',
              ),
            for (final parameter in p.parameters.entries)
              Text('${parameter.key}: ${parameter.value}'),
            Text(
              'Consent state: ${p.consent.state.name} · Purpose: ${p.consent.purpose}',
            ),
            Text(
              '${p.consent.state == AgentConsentState.serverConfirmed ? 'Provided server receipt scopes' : 'Proposed scopes — not server permission'}: ${p.consent.scopes.map((s) => s.name).join(', ')}',
            ),
            if (p.consent.receiptId != null)
              Text('Provided receipt reference: ${p.consent.receiptId}'),
            Text(
              'Local review: ${controller.locallyReviewed ? 'reviewed on device only' : 'not reviewed'}',
            ),
            const Text(
              'Local selection/review is not server consent, authorization or execution. No health context is sent by this component.',
            ),
            Text(
              'Provider: ${p.provider ?? 'not provided'} · Version: ${p.modelVersion ?? 'not provided'}',
            ),
            if (p.evidenceIds.isNotEmpty)
              Text('Provided evidence: ${p.evidenceIds.join(', ')}'),
            if (p.status == AgentActionState.succeeded) ...[
              Text('Server result record: ${p.resultRecordId}'),
              Text(
                'Server-reported completion: ${p.completedAt!.toIso8601String()}',
              ),
            ],
            OutlinedButton(
              onPressed: controller.reviewLocally,
              child: const Text('Review parameters on this device'),
            ),
            const FilledButton(
              onPressed: null,
              child: Text(
                'Execution unavailable until verified backend authorization',
              ),
            ),
          ],
        ),
      );
    },
  );
}
