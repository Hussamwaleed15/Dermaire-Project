import 'package:flutter/material.dart';
import '../dermaire_widgets.dart';
import '../integration/private_view.dart';
import '../doctor/doctor_connection.dart';
import '../doctor/doctor_evidence_ui.dart' show DoctorReviewSnapshot;
import '../psm/psm_screen.dart' show PsmEvidenceView;
import 'clinical_snapshot.dart';
import 'clinical_models.dart';
import 'clinical_ui.dart' show clinicalTime;

class ClinicalSnapshotScreen extends StatefulWidget {
  const ClinicalSnapshotScreen({super.key, this.connection});
  final DoctorConnectionController? connection;
  @override
  State<ClinicalSnapshotScreen> createState() => _ClinicalSnapshotState();
}

class _ClinicalSnapshotState extends State<ClinicalSnapshotScreen> {
  late final controller = ClinicalSnapshotController(
    connection: widget.connection,
  );
  @override
  Widget build(BuildContext context) => PrivateView(
    controller: controller,
    builder: (context, c) {
      final b = c.value;
      return DermairePage(
        eyebrow: 'One verified database read',
        title: 'Combined clinical snapshot',
        subtitle:
            'Safety, clinician status, Home and deterministic evidence from one server transaction. This is not medical clearance.',
        children: [
          OutlinedButton(
            onPressed: c.busy ? null : c.refresh,
            child: const Text('Read new combined snapshot'),
          ),
          if (c.busy) const Text('Reading one authorized clinical snapshot…'),
          if (c.error != null)
            Semantics(
              liveRegion: true,
              child: Text(
                'Combined snapshot unavailable. ${c.error!} Separate screens remain separate reads; no atomic snapshot is inferred.',
              ),
            ),
          if (b != null) ...[
            Text('Evaluated together: ${clinicalTime(b.asOf)}'),
            const Text(
              'Database rows visible in one PostgreSQL repeatable-read transaction. Image bytes, external services, AI inference and later changes are outside this snapshot.',
            ),
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Safety Engine at this read',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  StatusPill(
                    b.safety.level.label,
                    kind: b.safety.level == SafetyLevel.urgent
                        ? StatusKind.conflict
                        : b.safety.level == SafetyLevel.doctorReview
                        ? StatusKind.warning
                        : StatusKind.neutral,
                  ),
                  Text(b.safety.guidance),
                  for (final reason in b.safety.reasons) Text(reason.summary),
                  for (final limit in b.safety.limitations) Text(limit),
                  if (b.safety.staleOrAbsent == true)
                    const Text(
                      'Report evidence is stale or absent. Missing evidence does not rule out risk.',
                    ),
                ],
              ),
            ),
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Home at the shared read',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    b.observationCompleted
                        ? 'Structured observation on snapshot day: recorded'
                        : 'Structured observation on snapshot day: not recorded',
                  ),
                  Text(
                    b.home['today_checked_in'] == true
                        ? 'Confirmed measurement on snapshot day: recorded'
                        : 'Confirmed measurement on snapshot day: not recorded',
                  ),
                  Text(
                    'Snapshot UTC day: ${b.home['date']}. A report-only observation does not create measurement scores or a baseline.',
                  ),
                  if (b.home['experiment'] is Map)
                    Text(
                      'Recorded experiment state: ${(b.home['experiment'] as Map)['status']}',
                    ),
                ],
              ),
            ),
            if (c.role == 'doctor')
              DoctorReviewSnapshot(data: b.review, patient: b.patient)
            else if (b.patientReview != null)
              DermaireCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Patient-visible clinician status',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Recorded state: ${b.patientReview!.rawState.replaceAll('_', ' ')}',
                    ),
                    if (b.patientReview!.decision != null) ...[
                      Text(
                        'Clinician recommendation: ${b.patientReview!.decision!.recommendation ?? 'Not recorded'}',
                      ),
                      if (b.patientReview!.decision!.rationale != null)
                        Text(b.patientReview!.decision!.rationale!),
                    ] else
                      const Text(
                        'No current patient-visible clinician decision. Older visible notes do not substitute for a private current decision.',
                      ),
                    for (final note
                        in b.patientReview!.notes ?? <PatientClinicianNote>[])
                      Text('Clinician-authored note: ${note.content}'),
                  ],
                ),
              ),
            PsmEvidenceView(model: b.model),
            for (final limitation in b.limitations) Text(limitation),
            const Text(
              'Refresh after new evidence, a conflicting change or returning to the app. Snapshot identity is correlation only; it cannot replay history or establish current clinical clearance.',
            ),
          ],
        ],
      );
    },
  );
}
