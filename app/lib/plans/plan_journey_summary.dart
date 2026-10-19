import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import 'plan_models.dart';

/// A next step from confirmed plan state, never elapsed-time completion or a
/// diagnosis. Comparison inference consent/result has its own separate lifecycle.
class PlanJourneySummary extends StatelessWidget {
  const PlanJourneySummary({super.key, required this.plan, required this.role});
  final ClinicalPlan plan;
  final String role;
  String get nextStep => switch (plan.state) {
    'proposed' =>
      role == 'patient'
          ? 'Review the plan and choose whether to participate.'
          : 'Waiting for the patient’s explicit participation.',
    'scheduled' =>
      plan.kind == 'comparison'
          ? role == 'patient'
                ? 'Take a guided follow-up, then explicitly attach the confirmed capture.'
                : 'Waiting for the patient’s follow-up capture.'
          : role == 'patient'
          ? 'Your participation is recorded. Review the saved follow-up time.'
          : 'Patient participation is recorded. Review or reschedule when needed.',
    'captured' =>
      role == 'doctor'
          ? 'The follow-up is attached. Review the current evidence.'
          : 'The follow-up is attached. Clinical review and image-processing consent are separate.',
    'reviewed' =>
      'The clinician’s plan review is recorded. Continue to follow current safety guidance.',
    'cancelled' =>
      'This plan is cancelled. No new capture or participation is requested by this plan.',
    _ => 'Refresh to verify the current plan before taking action.',
  };

  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            'Your next step',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(liveRegion: true, child: Text(nextStep)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusPill(
              plan.state.replaceAll('_', ' '),
              kind: StatusKind.neutral,
            ),
            Text('Server revision ${plan.revision}'),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'A plan status does not confirm recovery or completed image analysis.',
        ),
      ],
    ),
  );
}
