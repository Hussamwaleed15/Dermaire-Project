import 'dart:async';
import 'package:flutter/material.dart';
import '../dermaire_state.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import '../clinical/clinical_ui.dart';
import '../clinical/clinical_models.dart';
import '../observations/observation_ui.dart';
import '../capture/capture_history_screen.dart';
import 'psm_controller.dart';
import '../assistance/assistance_ui.dart';
import 'psm_models.dart';

class PersonalSkinModelEntry extends StatelessWidget {
  const PersonalSkinModelEntry({super.key, required this.state});
  final DermaireState state;
  @override
  Widget build(BuildContext context) {
    final generation = ApiService.instance.sessionGeneration;
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Understand your skin evidence',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'See what your recorded observations and image estimates support, and what remains unknown.',
          ),
          FilledButton.icon(
            key: const Key('openPersonalSkinModel'),
            icon: const Icon(Icons.insights_outlined),
            label: const Text('Open Personal Skin Model'),
            onPressed: () {
              final api = ApiService.instance;
              if (api.isCurrentSession(generation) &&
                  api.canReadPatientClinicalStatus) {
                openEntry(context, PersonalSkinModelScreen(state: state));
              }
            },
          ),
        ],
      ),
    );
  }
}

class PersonalSkinModelScreen extends StatefulWidget {
  const PersonalSkinModelScreen({
    super.key,
    required this.state,
    this.repository,
    this.timeout = const Duration(seconds: 20),
  });
  final DermaireState state;
  final PsmRepository? repository;
  final Duration timeout;
  @override
  State<PersonalSkinModelScreen> createState() =>
      _PersonalSkinModelScreenState();
}

class _PersonalSkinModelScreenState extends State<PersonalSkinModelScreen> {
  late final PsmController controller;
  @override
  void initState() {
    super.initState();
    controller = PsmController(
      ApiService.instance,
      repository: widget.repository,
      timeout: widget.timeout,
    )..addListener(changed);
    unawaited(controller.refresh());
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller.removeListener(changed);
    controller.dispose();
    super.dispose();
  }

  Future<void> open(Widget page) async {
    if (!controller.current) return;
    await openEntry(context, page);
    if (controller.current) await controller.refresh();
  }

  Future<void> recordObservation() => open(
    ObservationScreen(
      state: widget.state,
      onHistory: () => open(
        ObservationHistoryScreen(
          state: widget.state,
          onRecord: recordObservation,
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    if (!controller.current) {
      return const DermairePage(
        title: 'Session ended',
        children: [
          Text(
            'Your skin model has been cleared. Reopen it from your current account after sign-in.',
          ),
        ],
      );
    }
    final model = controller.model, safety = controller.safety;
    return DermairePage(
      title: 'Personal Skin Model',
      subtitle:
          'Understand your recorded evidence. This is a deterministic server model, not an autonomous AI agent or a diagnosis.',
      children: [
        if (safety != null)
          _PsmSafety(safety: safety, stale: controller.safetyStale),
        ClinicalHomePanel(controller: widget.state.clinical),
        OutlinedButton.icon(
          key: const Key('refreshPersonalSkinModel'),
          onPressed: controller.phase == PsmPhase.loading
              ? null
              : controller.refresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh skin evidence'),
        ),
        if (controller.phase == PsmPhase.loading)
          Semantics(
            liveRegion: true,
            child: const Text('Reading your skin evidence…'),
          ),
        if (controller.error != null)
          Semantics(liveRegion: true, child: Text(controller.error!)),
        if (model != null) EntryReveal(child: PsmEvidenceView(model: model)),
        DermaireCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Continue with your records',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'These are supported tracking destinations, not AI treatment recommendations.',
              ),
              FilledButton(
                key: const Key('psmRecordObservation'),
                onPressed: recordObservation,
                child: const Text('Record an observation'),
              ),
              OutlinedButton(
                key: const Key('psmImageHistory'),
                onPressed: () =>
                    open(CaptureHistoryScreen(state: widget.state)),
                child: const Text('View private image history'),
              ),
              TextButton(
                onPressed: () =>
                    open(ContextualAssistanceScreen(state: widget.state)),
                child: const Text('Ask about my evidence'),
              ),
              TextButton(
                key: const Key('psmClinicalGuidance'),
                onPressed: () => open(
                  ClinicalStatusScreen(controller: widget.state.clinical),
                ),
                child: const Text('Safety & clinician guidance'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PsmSafety extends StatelessWidget {
  const _PsmSafety({required this.safety, required this.stale});
  final SafetyAssessment safety;
  final bool stale;
  @override
  Widget build(BuildContext context) => DermaireCard(
    borderColor: safety.level == SafetyLevel.urgent
        ? Theme.of(context).colorScheme.error
        : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Safety Engine · PSM snapshot'),
        Semantics(
          liveRegion: true,
          child: Text(
            safety.supported
                ? safety.level.label
                : safety.level == SafetyLevel.urgent
                ? 'Unsupported safety format — server reports urgent'
                : 'Unsupported safety status',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (stale)
          const Text(
            'Previously received safety snapshot. Current PSM read is unconfirmed; refresh is required.',
          ),
        if (!safety.supported || safety.hasUnknownReasons)
          const Text(
            'The safety snapshot contains unsupported values. It cannot establish medical clearance.',
          ),
        if (safety.staleOrAbsent == true || safety.currentReportCount == 0)
          const Text(
            'Current symptom assessment is absent or outdated in this safety snapshot.',
          ),
        Text(safety.guidance),
        Text('Server status: ${safety.rawStatus}'),
        Text('Evaluated: ${clinicalTime(safety.evaluatedAt)}'),
        if (safety.riskScreenComplete != true)
          const Text(
            'Risk-screen evidence is incomplete or unknown. Missing data is not medical clearance.',
          ),
        for (final limitation in safety.limitations) Text(limitation),
        const Text(
          'This snapshot is separate from current safety and clinician readback below. Model findings cannot replace either source.',
        ),
      ],
    ),
  );
}

class PsmEvidenceView extends StatelessWidget {
  const PsmEvidenceView({super.key, required this.model});
  final PersonalSkinModel model;
  Widget section(BuildContext context, String title, List<Widget> children) =>
      DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      );
  @override
  Widget build(BuildContext context) {
    final p = model.profile, m = model.measurements, coverage = model.coverage;
    final unsupportedFindings = model.partialIssues.any(
      (s) =>
          s.startsWith('Changing findings') ||
          s.startsWith('Stable findings') ||
          s.startsWith('Associations'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section(context, 'Model overview', [
          Semantics(
            liveRegion: true,
            child: Text(switch (model.status) {
              'no_data' => 'No eligible skin evidence yet.',
              'insufficient_data' =>
                'Insufficient evidence for an overall trajectory.',
              'stale' => 'Historical evidence — current trajectory is unknown.',
              'meaningful_change' => 'Server model reports a tracking change.',
              _ => 'Server model reports no meaningful tracking change.',
            }),
          ),
          Text(
            unsupportedFindings
                ? 'Model statement withheld because supporting findings are unsupported.'
                : model.statement,
          ),
          Text(
            'Source: deterministic model output · ${model.contract} · ${model.derivation}',
          ),
          Text('Generated by server: ${clinicalTime(model.generatedAt)}'),
          Text(
            'Evidence strength: ${model.strength} — a rule-based label, not an accuracy percentage.',
          ),
          if (model.partialIssues.isNotEmpty) ...[
            const Text('Partial model data'),
            for (final issue in model.partialIssues) Text(issue),
          ],
          const Text(
            'No data does not mean healthy skin. No meaningful tracking change is not medical clearance.',
          ),
        ]),
        if (model.clinician != null)
          section(context, 'Clinician decision · PSM snapshot', [
            const Text(
              'Source: clinician-authored decision. Read current guidance independently above.',
            ),
            Text('Decision record: ${model.clinician!.id}'),
            Text('State: ${model.clinician!.state}'),
            if (ReviewState.parse(model.clinician!.state) ==
                    ReviewState.unknown ||
                model.clinician!.recommendation != null &&
                    SafetyLevel.parse(model.clinician!.recommendation!) ==
                        SafetyLevel.unknown)
              const Text(
                'Unsupported clinician snapshot value. Read current guidance separately.',
              ),
            if (model.clinician!.recommendation != null)
              Text('Server recommendation: ${model.clinician!.recommendation}'),
            if (model.clinician!.rationale != null)
              Text(model.clinician!.rationale!),
            Text(
              'Recorded: ${clinicalTime(model.clinician!.recordedAt)} · Freshness: ${model.clinician!.freshness.state}',
            ),
            const Text(
              'A lower clinician recommendation does not remove independent urgent Safety Engine guidance.',
            ),
          ]),
        section(context, 'Your reported profile', [
          if (p == null)
            const Text('Supported profile evidence is unavailable.')
          else ...[
            const Text(
              'Source: user-reported profile, not an inferred diagnosis.',
            ),
            Text('Skin type: ${p.skinType ?? 'not provided'}'),
            Text(
              'Concerns: ${p.concerns.isEmpty ? 'not provided' : p.concerns.join(', ')}',
            ),
            Text(
              'Goals: ${p.goals.isEmpty ? 'not provided' : p.goals.join(', ')}',
            ),
            if (p.freshness != null)
              Text('Profile freshness: ${p.freshness!.state}'),
            for (final evidence in p.evidence)
              _EvidenceReference(value: evidence),
          ],
          const Text(
            'Optional disclosures remain optional. Missing personal information is not guessed.',
          ),
        ]),
        section(context, 'What records support this model', [
          Text('Eligible record days: ${coverage.recordDays}'),
          Text('Structured report days: ${coverage.reportDays}'),
          Text(
            'Tracking-value days in the legacy stream: ${coverage.trackingDays}',
          ),
          Text(
            'Nonclinical image-estimate days: ${coverage.proxyDays ?? 'not provided'}',
          ),
          Text('Excluded records: ${coverage.excluded}'),
          Text('Skin-evidence recency: ${coverage.recency}'),
          if (coverage.latestEvidence != null)
            Text(
              'Latest eligible skin evidence: ${clinicalTime(coverage.latestEvidence!)}',
            ),
          if (coverage.latestProxy != null)
            Text(
              'Latest computed proxy: ${clinicalTime(coverage.latestProxy!)}',
            ),
          Text(
            'Legacy tracking reference: ${coverage.baselineReady ? 'reported ready' : 'not ready'}',
          ),
          const Text(
            'Report days and capture estimates do not create a clinical measurement baseline. These streams are distinct.',
          ),
        ]),
        for (final group in [
          ('Recorded changes', model.changing),
          ('Stable tracking findings', model.stable),
          ('Recorded associations', model.associations),
        ])
          section(context, group.$1, [
            if (group.$2.isEmpty)
              const Text(
                'No supported finding is available in this section. This is not a safety conclusion.',
              ),
            for (final finding in group.$2)
              _FindingCard(
                finding: finding,
                historical: model.status == 'stale',
              ),
          ]),
        section(context, 'Recorded observations', [
          const Text(
            'Source: user-reported observations. Presence of a symptom is not a severity grade.',
          ),
          if (model.reports.isEmpty)
            const Text('No supported report records were provided.'),
          for (final report in model.reports)
            ExpansionTile(
              title: Text(
                'Reported ${report.change} · ${clinicalTime(report.recordedAt)}',
              ),
              expansionAnimationStyle: EntryMotion.reduced(context)
                  ? AnimationStyle.noAnimation
                  : const AnimationStyle(duration: Duration(milliseconds: 180)),
              children: [
                Text(
                  'Record: ${report.id} · Freshness: ${report.freshness.state}',
                ),
                Text(
                  'Reported symptoms: ${report.symptoms.isEmpty ? 'none listed' : report.symptoms.join(', ')}',
                ),
                Text('Reported routine: ${report.routine ?? 'unknown'}'),
                const Text(
                  'This report is not linked to a capture by this view.',
                ),
              ],
            ),
        ]),
        section(context, 'Nonclinical image estimates', [
          const Text(
            'Fractional image appearance proxies, not medical scores, diagnoses or an AI before/after assessment.',
          ),
          if (m == null)
            const Text('Supported image estimate metadata is unavailable.')
          else ...[
            Text('Image-evidence freshness: ${m.freshness.state}'),
            Text('Server comparison status: ${m.trend}'),
            const Text(
              'No image delta or clinical change is computed or interpreted on this device.',
            ),
            if (m.latestUnsupported)
              const Text(
                'Latest image estimate format is unsupported. No values are shown.',
              ),
            if (m.latest == null && !m.latestUnsupported)
              const Text('No current image estimate was supplied.'),
            if (m.latest != null)
              _ImageEstimates(
                value: m.latest!,
                label: 'Latest image estimate record',
              ),
            if (m.historicalUnsupported)
              const Text('Historical image estimate format is unsupported.'),
            if (m.historical != null && m.historical!.id != m.latest?.id)
              _ImageEstimates(
                value: m.historical!,
                label:
                    'Earlier measured estimate — historical reference, not a replacement for the latest record',
              ),
          ],
        ]),
        section(context, 'Experiment evidence', [
          const Text(
            'Source: experiment definitions and deterministic server evaluation. An association does not establish causation or treatment effectiveness.',
          ),
          if (model.experiments.isEmpty)
            const Text('No supported experiment evidence was supplied.'),
          for (final experiment in model.experiments)
            ExpansionTile(
              title: Text('Experiment ${experiment.id} · ${experiment.status}'),
              expansionAnimationStyle: EntryMotion.reduced(context)
                  ? AnimationStyle.noAnimation
                  : const AnimationStyle(duration: Duration(milliseconds: 180)),
              children: [
                Text(
                  'Started: ${clinicalTime(experiment.start)} · Target days: ${experiment.targetDays}',
                ),
                if (experiment.changeType != null)
                  Text('Recorded intervention: ${experiment.changeType}'),
                if (experiment.evaluation == null)
                  const Text('No evaluation was supplied.')
                else ...[
                  Text(
                    'Evaluation record: ${experiment.evaluation!.id} · ${experiment.evaluation!.freshness.state}',
                  ),
                  Text(
                    'Backend evidence label: ${experiment.evaluation!.label.replaceAll('_', ' ')}',
                  ),
                  Text(experiment.evaluation!.statement),
                  Text('Evidence strength: ${experiment.evaluation!.strength}'),
                  if (experiment.evaluation!.evidenceCount != null)
                    Text(
                      'Returned evidence count: ${experiment.evaluation!.evidenceCount}',
                    ),
                  for (final caveat in experiment.evaluation!.caveats)
                    Text(caveat),
                ],
              ],
            ),
        ]),
        section(context, 'Missing information & limits', [
          for (final reason in coverage.reasons) Text(reason),
          for (final unknown in model.unknowns) Text(unknown),
          for (final limitation in model.limitations) Text(limitation),
          const Text(
            'The available model is a server read-time projection. It does not establish an AI diagnosis, product effect or autonomous follow-up plan.',
          ),
        ]),
      ],
    );
  }
}

class _EvidenceReference extends StatelessWidget {
  const _EvidenceReference({required this.value});
  final PsmEvidence value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${value.kind == 'user_reported'
              ? 'User-reported'
              : value.kind == 'image_proxy'
              ? 'Nonclinical image proxy'
              : 'Server-recorded'} · ${value.source} · ${value.id}',
        ),
        Text('Recorded: ${clinicalTime(value.recordedAt)}'),
        Text('Fields: ${value.fields.join(', ')}'),
      ],
    ),
  );
}

class _FindingCard extends StatelessWidget {
  const _FindingCard({required this.finding, required this.historical});
  final PsmFinding finding;
  final bool historical;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (historical)
        const Text('Historical finding — not a current condition.'),
      Text(finding.statement),
      Text('Deterministic finding: ${finding.code} · ${finding.direction}'),
      Text('Evidence strength: ${finding.strength}'),
      if (finding.confidence != null)
        Text(
          'Returned confidence label: ${finding.confidence} (not a probability)',
        ),
      ExpansionTile(
        title: Text('Supporting evidence · ${finding.subject}'),
        expansionAnimationStyle: EntryMotion.reduced(context)
            ? AnimationStyle.noAnimation
            : const AnimationStyle(duration: Duration(milliseconds: 180)),
        children: [
          Text('Rule: ${finding.rule}'),
          if (finding.evidenceCount != null)
            Text('Source reference count: ${finding.evidenceCount}'),
          for (final evidence in finding.evidence)
            _EvidenceReference(value: evidence),
          for (final caveat in finding.caveats) Text(caveat),
        ],
      ),
    ],
  );
}

class _ImageEstimates extends StatelessWidget {
  const _ImageEstimates({required this.value, required this.label});
  final PsmImageEstimates value;
  final String label;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      Text('Estimate: ${value.id} · Capture: ${value.captureId}'),
      Text('Method: ${value.algorithm} · Status: ${value.status}'),
      if (value.source != null) Text('Returned provenance: ${value.source}'),
      Text('Computed: ${clinicalTime(value.computedAt)}'),
      if (value.receivedAt != null)
        Text('Capture received by server: ${clinicalTime(value.receivedAt!)}'),
      if (value.freshness != null)
        Text('Reference freshness: ${value.freshness!.state}'),
      for (final metric in value.metrics.values) ...[
        Text(
          '${metric.key}: ${metric.value ?? 'unavailable'} · ${metric.unit}',
        ),
        Text(
          'Status: ${metric.status} · Region: fixed bilateral cheek rectangles from the frontal face detector',
        ),
        for (final limitation in metric.limitations) Text(limitation),
      ],
    ],
  );
}
