import 'package:flutter/material.dart';
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../clinical/clinical_ui.dart';
import '../clinical/clinical_models.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import 'assistance_models.dart';
import 'assistance_controller.dart';

class AssistanceSafetySnapshot extends StatelessWidget {
  const AssistanceSafetySnapshot({super.key, required this.response});
  final AssistanceResponse response;
  @override
  Widget build(BuildContext context) => DermaireCard(
    borderColor: response.safety.level == SafetyLevel.urgent
        ? Theme.of(context).colorScheme.error
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Safety Engine · response snapshot'),
        Semantics(
          liveRegion: true,
          child: Text(
            response.safety.supported
                ? response.safety.level.label
                : response.safety.level == SafetyLevel.urgent
                ? 'Unsupported safety format — server reports urgent'
                : 'Unsupported safety status — no clearance',
          ),
        ),
        SelectableText(response.safety.guidance),
        Text('Evaluated: ${clinicalTime(response.safety.evaluatedAt)}'),
        Text('Server escalation: ${response.escalation}'),
        if (response.safety.riskScreenComplete != true)
          const Text(
            'Risk-screen evidence is incomplete. Missing information does not rule out risk.',
          ),
        for (final limitation in response.safety.limitations) Text(limitation),
        if (response.clinician != null) ...[
          const Text('Clinician-authored decision · response snapshot'),
          Text(
            'Decision: ${response.clinician!.id} · Sequence: ${response.clinician!.sequence}',
          ),
          Text(
            'Clinician recommendation: ${response.clinician!.recommendation}',
          ),
        ],
        const Text(
          'Response snapshots do not replace separately retrieved current safety or clinician guidance. The device does not resolve conflicts.',
        ),
      ],
    ),
  );
}

class AssistanceEvidence extends StatelessWidget {
  const AssistanceEvidence({
    super.key,
    required this.response,
    this.showMessage = true,
    this.showSafety = true,
  });
  final AssistanceResponse response;
  final bool showMessage, showSafety;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (showSafety) AssistanceSafetySnapshot(response: response),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Assistance response',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (showMessage) SelectableText(response.message),
            Text(
              'Response source mode: ${response.provider.mode} · Availability: ${response.provider.availability}',
            ),
            Text('Provider invoked: ${response.provider.invoked}'),
            if (response.provider.provider != null)
              Text('Reported provider: ${response.provider.provider}'),
            if (response.provider.model != null)
              Text('Reported model: ${response.provider.model}'),
            if (response.provider.reason != null)
              Text('Reported reason: ${response.provider.reason}'),
            Text('Versions: ${response.schema} · ${response.contextVersion}'),
            const Text(
              'This is informational contextual assistance, not an autonomous agent or clinician diagnosis.',
            ),
          ],
        ),
      ),
      ExpansionTile(
        title: const Text('Why this response? Supporting information'),
        expansionAnimationStyle: EntryMotion.reduced(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(duration: Duration(milliseconds: 180)),
        children: [
          const Text(
            'Only facts selected by this response are shown. The complete context/source availability inventory is not returned.',
          ),
          if (response.facts.isEmpty)
            const Text(
              'No supporting facts were returned. No citations are invented.',
            ),
          for (final fact in response.facts)
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Source: ${fact.source}${fact.knownSource ? '' : ' (unknown source identifier)'} · ${fact.category}',
                  ),
                  Text(
                    'Fact: ${fact.id} · Record: ${fact.sourceId} · Field: ${fact.field}',
                  ),
                  Text('Freshness: ${fact.freshness}'),
                  if (fact.recordedAt != null)
                    Text('Recorded: ${clinicalTime(fact.recordedAt!)}'),
                  SelectableText('Returned value: ${fact.valueJson}'),
                  SelectableText('Returned provenance: ${fact.provenanceJson}'),
                  if (fact.confidence != null)
                    Text(
                      'Returned evidence label: ${fact.confidence} (not an inferred percentage)',
                    ),
                  const Text(
                    'Reported facts, image-property proxies and deterministic findings are distinct; no clinical score is calculated here.',
                  ),
                ],
              ),
            ),
        ],
      ),
      if (response.inferences.isNotEmpty)
        DermaireCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI-inferred suggestions — separate from recorded facts',
              ),
              for (final inference in response.inferences) ...[
                Text(inference.statement),
                Text(
                  'Returned evidence references: ${inference.evidenceIds.join(', ')}',
                ),
              ],
            ],
          ),
        ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('What remains uncertain'),
            if (response.uncertainties.isEmpty)
              const Text(
                'No uncertainty list was supplied. This does not establish certainty.',
              ),
            for (final u in response.uncertainties) Text(u),
          ],
        ),
      ),
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Server-provided next steps'),
            for (final step in response.nextSteps) Text(step),
            const Text(
              'Informational suggestions only; no action is executed by this response.',
            ),
          ],
        ),
      ),
    ],
  );
}

class ContextualAssistanceScreen extends StatefulWidget {
  const ContextualAssistanceScreen({
    super.key,
    required this.state,
    this.repository,
  });
  final DermaireState state;
  final AssistanceRepository? repository;
  @override
  State<ContextualAssistanceScreen> createState() =>
      _ContextualAssistanceScreenState();
}

class _ContextualAssistanceScreenState
    extends State<ContextualAssistanceScreen> {
  late final AssistanceController controller;
  final input = TextEditingController();
  @override
  void initState() {
    super.initState();
    controller = AssistanceController(
      ApiService.instance,
      repository: widget.repository,
    )..addListener(changed);
  }

  void changed() {
    if (!controller.current) input.clear();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(changed);
    controller.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !controller.current
      ? const DermairePage(
          title: 'Session ended',
          children: [
            Text(
              'Private assistance has been cleared. Reopen from your current account.',
            ),
          ],
        )
      : DermairePage(
          title: 'Contextual assistance',
          subtitle:
              'Ask about your recorded evidence. Only the current question is sent; no local model, photos or conversation history is added.',
          children: [
            ClinicalHomePanel(controller: widget.state.clinical),
            TextField(
              key: const Key('assistanceQuestion'),
              controller: input,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Your question'),
            ),
            FilledButton(
              key: const Key('requestAssistance'),
              onPressed: controller.busy
                  ? null
                  : () => controller.send(input.text),
              child: const Text('Ask about my records'),
            ),
            if (controller.busy)
              Semantics(
                liveRegion: true,
                child: const Text('Waiting for the server response…'),
              ),
            if (controller.error != null)
              Semantics(liveRegion: true, child: Text(controller.error!)),
            if (controller.canRetry)
              OutlinedButton(
                onPressed: controller.retry,
                child: const Text(
                  'Retry once — may repeat the provider request',
                ),
              ),
            if (controller.response != null)
              AssistanceEvidence(response: controller.response!),
          ],
        );
}
