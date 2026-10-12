import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../capture/private_capture_image.dart';
import 'comparison_controller.dart';
import 'comparison_domain.dart';

/// Prepared presentation only. No production route, fake state or camera/write
/// action is installed. Future screens must retain authoritative clinical panels.
class ComparisonPanel extends StatelessWidget {
  const ComparisonPanel({super.key, required this.controller});
  final ComparisonController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      if (!controller.current) {
        return const DermaireCard(
          child: Text(
            'Comparison information cleared. Reopen after sign-in and safety acceptance.',
          ),
        );
      }
      final snapshot = controller.snapshot;
      if (snapshot == null) {
        return DermaireCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(switch (controller.phase) {
                  ComparisonPhase.loading =>
                    'Reading confirmed follow-up information…',
                  ComparisonPhase.unavailable =>
                    'Plan-linked comparison is unavailable. Scheduling and assessment contracts are not connected.',
                  ComparisonPhase.empty =>
                    'No confirmed follow-up plan was returned.',
                  ComparisonPhase.stale =>
                    'Follow-up information is stale or freshness is unknown. Read again before using images or results.',
                  ComparisonPhase.failed =>
                    controller.error ?? 'Follow-up information unavailable.',
                  _ => 'No follow-up information has been read.',
                }),
              ),
              if ([
                ComparisonPhase.failed,
                ComparisonPhase.stale,
                ComparisonPhase.empty,
                ComparisonPhase.idle,
              ].contains(controller.phase))
                OutlinedButton(
                  onPressed: controller.refresh,
                  child: const Text('Read follow-up information'),
                ),
            ],
          ),
        );
      }
      final plan = snapshot.plan;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DermaireCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Follow-up plan',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('Plan reference: ${plan.id} · Revision: ${plan.revision}'),
                Semantics(liveRegion: true, child: Text(plan.lifecycle.label)),
                Text(
                  plan.schedule?.instantUtc == null
                      ? 'Follow-up date not provided.'
                      : 'Follow-up instant: ${plan.schedule!.instantUtc!.toIso8601String()} (UTC)',
                ),
                Text(
                  plan.schedule?.reportedTimezone == null
                      ? 'Scheduling timezone not provided.'
                      : 'Server-reported timezone: ${plan.schedule!.reportedTimezone}',
                ),
                Text(switch (plan.schedule?.serverDue) {
                  true => 'Due status: due, as reported by the server.',
                  false => 'Due status: not due, as reported by the server.',
                  null =>
                    'Due status not provided. No due date is inferred on this device.',
                }),
                if (plan.lifecycle.inactive)
                  const Text(
                    'This plan is inactive. Its images and assessment are not shown as a current follow-up.',
                  ),
                if (plan.intervention == null)
                  const Text('No intervention relationship provided.')
                else
                  Text(
                    'Explicit relationship: ${plan.intervention!.kind.label} · ${plan.intervention!.recordId}',
                  ),
                const Text(
                  'A reference image is separate from a clinical measurement baseline. Routine completion does not schedule a comparison.',
                ),
              ],
            ),
          ),
          DermaireCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scheduling decisions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (plan.decisions.isEmpty)
                  const Text('Scheduling source unknown.'),
                for (final decision in plan.decisions)
                  Text(
                    '${decision.source.label} · Decision record: ${decision.recordId}',
                  ),
                Text(
                  plan.resolvedDecision == null
                      ? 'No authoritative server resolution provided. The device does not resolve conflicts.'
                      : 'Server-provided resolution: ${plan.resolvedDecision!.source.label} · ${plan.resolvedDecisionId}',
                ),
                if (plan.resolutionNote != null) Text(plan.resolutionNote!),
                Text('Patient confirmation: ${plan.confirmation.label}'),
                const Text(
                  'AI suggestions do not replace clinician decisions. Patient confirmation is not a clinician-authored instruction.',
                ),
              ],
            ),
          ),
          if (plan.confirmedSchedule)
            _AssessmentSummary(assessment: snapshot.assessment)
          else
            const DermaireCard(
              child: Text(
                'Current assessment is unavailable until the server confirms an active schedule.',
              ),
            ),
        ],
      );
    },
  );
}

class _AssessmentSummary extends StatelessWidget {
  const _AssessmentSummary({required this.assessment});
  final ComparisonAssessment? assessment;
  @override
  Widget build(BuildContext context) {
    final result = assessment;
    return DermaireCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Assessment', style: Theme.of(context).textTheme.titleLarge),
          Semantics(
            liveRegion: true,
            child: Text(switch (result?.status) {
              null || AssessmentStatus.unavailable =>
                'Assessment unavailable. No result has been confirmed.',
              AssessmentStatus.pending =>
                'Assessment pending. No result is available yet.',
              AssessmentStatus.processing =>
                'Assessment processing. No result is available yet.',
              AssessmentStatus.available => 'Assessment record available.',
              AssessmentStatus.failed =>
                'Assessment failed. No successful result is shown.',
              AssessmentStatus.insufficientEvidence =>
                'Insufficient evidence. No conclusion can be displayed.',
              AssessmentStatus.unknown =>
                'Unknown assessment status. No conclusion is shown.',
            }),
          ),
          if (result != null) ...[
            Text(switch (result.source) {
              AssessmentSource.aiObservation =>
                'Source: AI-generated observation — not a clinician diagnosis.',
              AssessmentSource.nonclinicalObservation =>
                'Source: nonclinical observation.',
              AssessmentSource.clinicianAuthored =>
                'Source: clinician-authored statement.',
              AssessmentSource.unknown =>
                'Source: unknown. Observations are not displayed.',
            }),
            Text('Source version: ${result.sourceVersion ?? 'not provided'}'),
            Text('Clinician review: ${result.review.label}'),
            if (result.reviewRecordId != null)
              Text('Review record: ${result.reviewRecordId}'),
            if (result.generatedAt != null)
              Text('Generated: ${result.generatedAt!.toIso8601String()} (UTC)'),
            if (result.status == AssessmentStatus.available &&
                result.source != AssessmentSource.unknown)
              for (final observation in result.observations) Text(observation),
            if (result.evidenceRecords.isNotEmpty)
              Text('Evidence records: ${result.evidenceRecords.join(', ')}'),
            for (final limit in result.limitations) Text('Limitation: $limit'),
            for (final uncertainty in result.uncertainties)
              Text('Uncertainty: $uncertainty'),
          ],
          const Text(
            'Scheduling, capture association and assessment requests are unavailable until their backend contracts are verified.',
          ),
        ],
      ),
    );
  }
}

/// Only controller-validated current plan links can reach the existing private
/// image renderer. There is no public two-ID picker or URL/image-byte parameter.
class PlanReferenceImages extends StatelessWidget {
  const PlanReferenceImages({super.key, required this.controller, this.images});
  final ComparisonController controller;
  final PrivateCaptureImages? images;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) {
      final snapshot = controller.snapshot, plan = snapshot?.plan;
      if (plan == null || !plan.confirmedSchedule) {
        return const DermaireCard(
          child: Text('Current plan-linked images unavailable.'),
        );
      }
      final baseline = _ReferenceImage(
        label: 'Baseline reference',
        association: plan.baseline,
        controller: controller,
        images: images,
      );
      final followUp = _ReferenceImage(
        label: 'Follow-up reference',
        association: plan.followUp,
        controller: controller,
        images: images,
      );
      return DermaireCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Plan-linked reference images',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text(
              'Explicit server-linked references only. Images are not clinically aligned or normalized; viewing them does not establish improvement or a diagnosis.',
            ),
            LayoutBuilder(
              builder: (context, constraints) =>
                  constraints.maxWidth >= 720 &&
                      MediaQuery.textScalerOf(context).scale(1) <= 1.3
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: baseline),
                        const SizedBox(width: 16),
                        Expanded(child: followUp),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        baseline,
                        const SizedBox(height: 16),
                        followUp,
                      ],
                    ),
            ),
          ],
        ),
      );
    },
  );
}

class _ReferenceImage extends StatelessWidget {
  const _ReferenceImage({
    required this.label,
    required this.association,
    required this.controller,
    this.images,
  });
  final String label;
  final PlanCaptureAssociation? association;
  final ComparisonController controller;
  final PrivateCaptureImages? images;
  @override
  Widget build(BuildContext context) {
    final link = association, metadata = link?.metadata;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        if (link == null)
          const Text('No explicit capture association provided.')
        else ...[
          Text('Capture reference: ${link.captureId}'),
          if (metadata == null)
            const Text(
              'Owned capture metadata unavailable. No image is inferred.',
            )
          else if (metadata.state != 'accepted' || !metadata.stored)
            const Text('Linked capture has no accepted stored image.')
          else
            PrivateCaptureImage(
              key: ValueKey(
                '${controller.context.generation}:${link.planId}:${link.planRevision}:${link.role.name}:${link.captureId}',
              ),
              id: link.captureId,
              generation: controller.context.generation,
              stored: metadata.stored,
              viewer: true,
              images: images,
            ),
        ],
      ],
    );
  }
}
