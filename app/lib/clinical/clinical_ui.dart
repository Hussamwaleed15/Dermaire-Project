import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import '../services/api_service.dart';
import 'clinical_controller.dart';
import 'clinical_models.dart';

String clinicalTime(DateTime value) =>
    '${value.toUtc().toIso8601String().replaceFirst('T', ' ').split('.').first} UTC';

class ClinicalHomePanel extends StatefulWidget {
  const ClinicalHomePanel({
    super.key,
    required this.controller,
    this.compact = true,
  });
  final ClinicalController controller;
  final bool compact;
  @override
  State<ClinicalHomePanel> createState() => _ClinicalHomePanelState();
}

class _ClinicalHomePanelState extends State<ClinicalHomePanel> {
  late final int generation;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.controller.allowed &&
          widget.controller.safety.phase == ClinicalPhase.empty &&
          !widget.controller.loading) {
        widget.controller.refresh(expectedGeneration: generation);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      if (!ApiService.instance.isCurrentSession(generation) ||
          !controller.allowed) {
        return const DermaireCard(
          child: Text(
            'Safety and clinician information is not loaded. Sign in and confirm safety acceptance to view your own guidance.',
          ),
        );
      }
      return ClinicalStatusPanel(
        controller: controller,
        compact: widget.compact,
        generation: generation,
      );
    },
  );
}

class ClinicalStatusScreen extends StatelessWidget {
  const ClinicalStatusScreen({super.key, required this.controller});
  final ClinicalController controller;
  @override
  Widget build(BuildContext context) => DermairePage(
    title: 'Safety & clinician guidance',
    subtitle:
        'Server-provided information for your account. Dermaire does not replace professional medical care.',
    children: [ClinicalHomePanel(controller: controller, compact: false)],
  );
}

/// Ordering is presentation only. No merged diagnosis/status is computed.
/// Clinician decisions remain distinct, and neither source can hide urgent
/// Safety Engine guidance, including a differing embedded server evaluation.
class ClinicalStatusPanel extends StatelessWidget {
  const ClinicalStatusPanel({
    super.key,
    required this.controller,
    required this.compact,
    required this.generation,
  });
  final ClinicalController controller;
  final bool compact;
  final int generation;
  @override
  Widget build(BuildContext context) {
    final s = controller.safety;
    final r = controller.review;
    final embedded = r.value?.safety;
    final showEmbedded =
        embedded != null &&
        (s.value == null ||
            embedded.rawStatus != s.value!.rawStatus ||
            embedded.engineVersion != s.value!.engineVersion ||
            (s.stale && !r.stale));
    final urgent =
        (s.value?.level == SafetyLevel.urgent) ||
        (showEmbedded && embedded.level == SafetyLevel.urgent);
    final actionable =
        !r.stale &&
        r.value?.supported == true &&
        (r.value!.state == ReviewState.followUp ||
            r.value!.decision?.level == SafetyLevel.urgent ||
            r.value!.decision?.level == SafetyLevel.doctorReview);
    final directPanel = _engine(
      context,
      s.value,
      s.phase,
      s.stale,
      s.error,
      s.retrievedAt,
      'Safety Engine',
    );
    final embeddedPanel = showEmbedded
        ? _engine(
            context,
            embedded,
            r.phase,
            r.stale,
            null,
            r.retrievedAt,
            'Safety Engine · clinician-status read',
          )
        : null;
    int presentationOrder(SafetyAssessment? value) =>
        value?.level == SafetyLevel.urgent
        ? 0
        : value?.supported != true
        ? 3
        : switch (value!.level) {
            SafetyLevel.urgent => 0,
            SafetyLevel.doctorReview => 1,
            _ => 2,
          };
    final embeddedFirst =
        showEmbedded &&
        presentationOrder(embedded) < presentationOrder(s.value);
    final engine = <Widget>[
      if (embeddedFirst) embeddedPanel!,
      directPanel,
      if (showEmbedded && !embeddedFirst) embeddedPanel!,
    ];
    final clinician = _clinician(context, r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Safety & clinician guidance',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        if (actionable && !urgent) ...[
          clinician,
          ...engine,
        ] else ...[
          ...engine,
          clinician,
        ],
        OutlinedButton(
          key: const Key('refreshClinicalStatus'),
          onPressed: controller.loading
              ? null
              : () => controller.refresh(expectedGeneration: generation),
          child: Text(
            controller.loading ? 'Refreshing guidance…' : 'Refresh guidance',
          ),
        ),
        if (compact)
          TextButton(
            key: const Key('clinicalDetails'),
            onPressed: () {
              if (ApiService.instance.isCurrentSession(generation)) {
                openPage(context, ClinicalStatusScreen(controller: controller));
              }
            },
            child: const Text('View safety details'),
          ),
      ],
    );
  }

  Widget _frame(
    BuildContext context, {
    required String source,
    required String title,
    required IconData icon,
    required bool urgent,
    required bool caution,
    required bool stale,
    required ClinicalPhase phase,
    required String? error,
    required DateTime? retrievedAt,
    required List<Widget> children,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = urgent
        ? (dark ? const Color(0xFFFFB9B9) : const Color(0xFF92282D))
        : caution
        ? (dark ? const Color(0xFFF4D18B) : const Color(0xFF75520F))
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return DermaireCard(
      borderColor: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            source,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            liveRegion:
                urgent || error != null || phase == ClinicalPhase.loading,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (stale)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Previously retrieved — current information is unconfirmed. Refresh for an updated view.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          if (phase == ClinicalPhase.loading) ...[
            const SizedBox(height: 8),
            const Text('Loading the latest server information…'),
            if (!EntryMotion.reduced(context))
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(),
              ),
          ],
          if (error != null)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error),
              ),
            ),
          if (retrievedAt != null)
            Text(
              'Retrieved: ${clinicalTime(retrievedAt)}',
              style: const TextStyle(fontSize: 12),
            ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _engine(
    BuildContext context,
    SafetyAssessment? value,
    ClinicalPhase phase,
    bool stale,
    String? error,
    DateTime? retrievedAt,
    String source,
  ) {
    final recognized = value?.supported == true;
    final level = value?.level ?? SafetyLevel.unknown;
    return _frame(
      context,
      source: source,
      title: value == null
          ? (phase == ClinicalPhase.loading
                ? 'Safety guidance loading'
                : 'Safety guidance unavailable')
          : recognized
          ? level.label
          : level == SafetyLevel.urgent
          ? 'Unsupported safety format — server reports urgent'
          : 'Unsupported safety status',
      icon: level == SafetyLevel.urgent
          ? Icons.emergency_outlined
          : level == SafetyLevel.doctorReview
          ? Icons.warning_amber_rounded
          : Icons.info_outline,
      urgent: level == SafetyLevel.urgent,
      caution: level == SafetyLevel.doctorReview || !recognized || stale,
      stale: stale,
      phase: phase,
      error: error,
      retrievedAt: retrievedAt,
      children: [
        if (value == null)
          const Text('No safety conclusion is available from this view.')
        else ...[
          Text('Server status: ${value.rawStatus}'),
          if (!recognized || value.hasUnknownReasons)
            const Text(
              'The server returned an unsupported value. This view cannot establish medical clearance.',
            ),
          Text(
            value.guidance,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (value.staleOrAbsent == true || value.currentReportCount == 0)
            const Text(
              'Current symptom assessment unavailable: evidence is absent or outdated.',
            ),
          if (value.riskScreenComplete != true)
            const Text(
              'Risk-screen information is incomplete or unknown. Missing information does not rule out risk.',
            ),
          Text(
            'Evaluated: ${clinicalTime(value.evaluatedAt)}',
            style: const TextStyle(fontSize: 12),
          ),
          if (!compact) ...[
            for (final reason in value.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  '${reason.summary}\nReason: ${reason.code} · ${reason.rawState}',
                ),
              ),
            if (value.limitations.isNotEmpty)
              ExpansionTile(
                title: const Text('Evidence and limitations'),
                expansionAnimationStyle: EntryMotion.reduced(context)
                    ? AnimationStyle.noAnimation
                    : const AnimationStyle(
                        duration: Duration(milliseconds: 180),
                      ),
                children: [
                  for (final limitation in value.limitations)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(limitation),
                    ),
                ],
              ),
          ],
          const Text(
            'Safety Engine guidance is not a diagnosis or a safety guarantee.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _clinician(BuildContext context, ClinicalRead<ClinicianReview> read) {
    final value = read.value;
    final supported = value?.supported == true;
    final decision = supported ? value!.decision : null;
    final level = decision?.level;
    return _frame(
      context,
      source: 'Clinician review',
      title: value == null
          ? (read.phase == ClinicalPhase.loading
                ? 'Clinician status loading'
                : 'Clinician status unavailable')
          : supported
          ? value.state.label
          : 'Unsupported review status',
      icon: Icons.medical_services_outlined,
      urgent: level == SafetyLevel.urgent,
      caution:
          level == SafetyLevel.doctorReview ||
          value?.state == ReviewState.followUp ||
          !supported ||
          read.stale,
      stale: read.stale,
      phase: read.phase,
      error: read.error,
      retrievedAt: read.retrievedAt,
      children: [
        if (value != null) ...[
          Text('Server workflow: ${value.rawState}'),
          if (value.changedAt != null)
            Text(
              'Workflow recorded: ${clinicalTime(value.changedAt!)}',
              style: const TextStyle(fontSize: 12),
            ),
          if (!supported)
            const Text(
              'This review format is unsupported. No clinician approval can be inferred.',
            )
          else if (decision == null)
            Text(
              read.stale
                  ? 'The previously retrieved view had no patient-visible decision. Current clinician status is unconfirmed.'
                  : 'No current patient-visible clinician decision. This does not mean clinician approval.',
            )
          else ...[
            if (decision.recommendation == null)
              Text(
                read.stale
                    ? 'The previously retrieved clinician action had no recommendation.'
                    : 'The current clinician action has no recommendation.',
              )
            else
              Text(
                '${read.stale ? 'Previously retrieved clinician recommendation' : 'Clinician recommendation'}: ${decision.recommendation}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            if (level == SafetyLevel.unknown)
              const Text(
                'Unsupported clinician recommendation. No clearance can be inferred.',
              ),
            if (decision.rationale != null) Text(decision.rationale!),
            Text(
              'Clinician-authored · ${clinicalTime(decision.createdAt)}',
              style: const TextStyle(fontSize: 12),
            ),
            if (decision.lowerThanCurrentSafety ||
                decision.urgentSafetyPreserved)
              const Text(
                'The server preserves Safety Engine guidance independently of this clinician recommendation.',
              ),
            if (decision.diverges)
              const Text(
                'The server reports a difference between this recommendation and its current safety evaluation.',
              ),
          ],
        ] else
          const Text('No clinician approval or decision can be inferred.'),
        if (!compact && supported && value != null) ...[
          Text(
            read.stale
                ? 'Previously retrieved clinician notes'
                : 'Patient-visible clinician notes',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (value.notes == null)
            const Text('Clinician notes could not be verified.')
          else if (value.notes!.isEmpty)
            const Text('No patient-visible notes returned.')
          else
            for (final note in value.notes!) ...[
              Text(note.content),
              Text(
                'Clinician author: ${note.author} · ${clinicalTime(note.createdAt)}',
              ),
              if (note.followUp != null)
                Text('Follow-up guidance: ${note.followUp}'),
              const Text(
                'Recorded guidance only; no appointment, reminder, message delivery or medical clearance is established.',
              ),
            ],
        ],
        if (!compact)
          Text(
            read.stale
                ? 'This is a previous view, not confirmation of the current clinician action. Messaging is not available here.'
                : 'This shows the current patient-visible action only. Historical notes/actions are not substituted for it. Messaging is not available here.',
            style: const TextStyle(fontSize: 12),
          ),
      ],
    );
  }
}
