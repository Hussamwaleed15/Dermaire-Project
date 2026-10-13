import 'package:flutter/material.dart';
import '../capture/private_capture_image.dart';
import '../clinical/clinical_models.dart';
import '../clinical/clinical_ui.dart' show clinicalTime;
import '../dermaire_widgets.dart';
import '../entry/entry_motion.dart';
import 'doctor_connection.dart';
import 'doctor_evidence_models.dart';
import 'doctor_records_controller.dart';

class DoctorSafetySnapshot extends StatelessWidget {
  const DoctorSafetySnapshot({
    super.key,
    required this.value,
    required this.source,
  });
  final SafetyAssessment value;
  final String source;
  @override
  Widget build(BuildContext context) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(source, style: Theme.of(context).textTheme.titleLarge),
        StatusPill(
          value.supported
              ? value.level.label
              : 'Unsupported status; no clearance',
          kind: value.level == SafetyLevel.urgent
              ? StatusKind.conflict
              : value.level == SafetyLevel.doctorReview || !value.supported
              ? StatusKind.warning
              : StatusKind.neutral,
        ),
        Text('Server status: ${value.rawStatus}'),
        Text(
          value.guidance,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text('Evaluated: ${clinicalTime(value.evaluatedAt)}'),
        const Text(
          'A server evaluation snapshot is not medical clearance. Missing or outdated evidence does not rule out risk.',
        ),
        if (value.riskScreenComplete != true)
          const Text('Risk-screen information is incomplete or unknown.'),
        for (final reason in value.reasons) Text(reason.summary),
        for (final limit in value.limitations) Text(limit),
      ],
    ),
  );
}

class DoctorReviewSnapshot extends StatelessWidget {
  const DoctorReviewSnapshot({
    super.key,
    required this.data,
    required this.patient,
  });
  final Map<String, dynamic> data;
  final String patient;
  @override
  Widget build(BuildContext context) {
    SafetyAssessment? safety;
    DoctorReviewRead? read;
    try {
      safety = SafetyAssessment.fromApi(object(data['safety']));
    } catch (_) {}
    try {
      read = DoctorReviewRead.fromApi(data, patient);
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (safety != null)
          DoctorSafetySnapshot(
            value: safety,
            source: 'Safety Engine · access-read snapshot',
          )
        else
          const Text(
            'Safety information is unavailable. No clearance is established.',
          ),
        if (read == null)
          const Text('Current clinician review could not be verified.')
        else ...[
          Text(
            'Current review returned by this read: ${read.state}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Current sequence: ${read.sequence}'),
          if (read.decision == null)
            const Text('No current clinician decision was returned.')
          else
            _decision(context, read.decision!, false),
          if (read.history.length > 1)
            Text(
              'Historical clinician reviews',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          for (final decision in read.history.where(
            (v) => v.id != read!.decision?.id,
          ))
            _decision(context, decision, true),
          const Text(
            'History is a returned snapshot. Prior decisions do not replace the current one.',
          ),
        ],
      ],
    );
  }

  Widget _decision(
    BuildContext context,
    DoctorDecision value,
    bool historical,
  ) => DermaireCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${historical ? 'Historical' : 'Current'} clinician-authored review · sequence ${value.sequence}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text('Author account: ${value.doctor}'),
        Text('Recorded: ${clinicalTime(value.createdAt)}'),
        Text(
          value.visible
              ? 'Patient-visible server record (not a delivery receipt)'
              : 'Private clinician record',
        ),
        Text('Review state: ${value.state}'),
        Text('Recommendation: ${value.recommendation ?? 'Not recorded'}'),
        if (value.rationale != null) Text(value.rationale!),
        if (value.diverges || value.lower)
          const Text(
            'The server reports disagreement with the current Safety Engine assessment. Safety guidance remains separate and visible.',
          ),
        if (value.urgentPreserved)
          const Text('The server preserves urgent Safety Engine guidance.'),
        if (value.state == 'follow_up_needed')
          const Text(
            'Follow-up needed is a review state, not a scheduled appointment or reminder.',
          ),
      ],
    ),
  );
}

class DoctorEvidenceScreen extends StatefulWidget {
  const DoctorEvidenceScreen({super.key, required this.connection});
  final DoctorConnectionController connection;
  @override
  State<DoctorEvidenceScreen> createState() => _DoctorEvidenceScreenState();
}

class _DoctorEvidenceScreenState extends State<DoctorEvidenceScreen> {
  late final records = DoctorRecordsController(widget.connection);
  late final images = PrivateCaptureImages(
    widget.connection.parent.api,
    reader: records.readImage,
    authorization: (generation) =>
        records.confirmed && widget.connection.parent.generation == generation,
    scope: records,
  );
  String? openedImage;
  bool ended = false;
  @override
  void initState() {
    super.initState();
    records.addListener(changed);
    records.refresh();
  }

  void changed() {
    if (ended) return;
    if (!records.confirmed) openedImage = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ended = true;
    records.removeListener(changed);
    images.dispose();
    records.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.connection.confirmed) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Text('Patient authorization ended. Return and verify access.'),
        ),
      );
    }
    final page = records.page;
    return DermairePage(
      eyebrow: 'Authorized clinical evidence',
      title: widget.connection.record!['full_name'] as String,
      children: [
        DoctorReviewSnapshot(
          data: widget.connection.record!['review'] is Map<String, dynamic>
              ? object(widget.connection.record!['review'])
              : <String, dynamic>{},
          patient: widget.connection.patientId,
        ),
        OutlinedButton(
          onPressed: records.loading || records.loadingMore
              ? null
              : records.refresh,
          child: const Text('Refresh clinical evidence'),
        ),
        if (records.loading)
          if (EntryMotion.reduced(context))
            const Text('Reading current evidence…')
          else
            const LinearProgressIndicator(
              semanticsLabel: 'Reading authorized evidence',
            ),
        if (records.error != null) Text(records.error!),
        if (records.confirmed && page != null) ...[
          DoctorSafetySnapshot(
            value: page.safety,
            source: 'Safety Engine · timeline-read snapshot',
          ),
          Text('Timeline built: ${clinicalTime(page.builtAt)}'),
          Text(
            'Loaded ${records.items.length} records; current returned total ${page.total}. Oldest first. Pages can change while reading.',
          ),
          const Text(
            'This is not a complete medical history. PSM facts here are bounded deterministic projections, not the future AI image model.',
          ),
          for (final limit in page.limitations) Text(limit),
          if (page.unknowns.isNotEmpty)
            Text('Unknown or missing evidence: ${page.unknowns.join('; ')}'),
          for (final entry in page.availability.entries)
            Text(
              '${entry.key.replaceAll('_', ' ')}: ${entry.value['state']} · ${entry.value['included']} included · ${entry.value['truncated'] == true ? 'truncated' : 'no truncation reported by this projection'}',
            ),
          if (records.items.isEmpty)
            const Text(
              'The server returned no timeline records for this read.',
            ),
          for (final item in records.items)
            DermaireCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.source.replaceAll('_', ' ')} · ${item.field.replaceAll('_', ' ')}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(item.sourceLabel),
                  Text(
                    item.recordedAt == null
                        ? 'Recorded timestamp unavailable'
                        : 'Recorded: ${clinicalTime(item.recordedAt!)}',
                  ),
                  for (final line in item.lines) Text(line),
                  if (item.provenance['freshness'] != null)
                    Text('Recorded freshness: ${item.provenance['freshness']}'),
                  if (item.storedCapture) ...[
                    OutlinedButton(
                      onPressed: () => setState(
                        () => openedImage = openedImage == item.sourceId
                            ? null
                            : item.sourceId,
                      ),
                      child: Text(
                        openedImage == item.sourceId
                            ? 'Close private image'
                            : 'Open private image',
                      ),
                    ),
                    if (openedImage == item.sourceId)
                      PrivateCaptureImage(
                        id: item.sourceId,
                        generation: widget.connection.parent.generation,
                        stored: true,
                        viewer: true,
                        images: images,
                      ),
                  ],
                ],
              ),
            ),
          if (records.hasMore)
            OutlinedButton(
              onPressed: records.loadingMore ? null : records.loadMore,
              child: Text(
                records.loadingMore
                    ? 'Reading more history…'
                    : 'Load next timeline page',
              ),
            ),
          if (!records.hasMore && page.nextOffset != null)
            const Text(
              'Display limit reached at 500 records. Additional history is not shown.',
            ),
        ],
      ],
    );
  }
}
