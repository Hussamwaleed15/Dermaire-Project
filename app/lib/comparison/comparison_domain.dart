/// Proposed integration concepts, NOT an existing API schema or wire DTO.
/// No JSON codecs, endpoints, inferred dates, numerical medical scores or local
/// state-machine transitions. A future verified adapter must supply evidence.
library;

import '../capture/guided_capture_models.dart';

void comparisonId(String value) {
  if (!RegExp(r'^[A-Za-z0-9_-]{1,255}$').hasMatch(value)) {
    throw const FormatException('Invalid comparison reference');
  }
}

void comparisonUtc(DateTime value) {
  if (!value.isUtc) {
    throw const FormatException('An explicit UTC instant is required');
  }
}

enum SchedulingSource {
  doctorDirected('Doctor-directed decision'),
  aiProposed('AI proposal — not a clinician instruction'),
  patientConfirmed('Patient confirmation'),
  unknown('Unknown scheduling source');

  const SchedulingSource(this.label);
  final String label;
}

enum PatientConfirmation {
  notRequired('Not required by the reported plan'),
  pending('Pending'),
  confirmed('Confirmed'),
  declined('Declined'),
  unknown('Unknown');

  const PatientConfirmation(this.label);
  final String label;
}

enum ComparisonLifecycle {
  notScheduled('Not scheduled'),
  pendingConfirmation('Pending patient confirmation'),
  scheduled('Schedule recorded'),
  awaitingDate('Awaiting follow-up date'),
  due('Follow-up due — server reported'),
  awaitingCapture('Awaiting follow-up capture'),
  requested('Assessment requested'),
  processing('Assessment processing'),
  available('Assessment available'),
  rescheduled('Follow-up rescheduled'),
  cancelled('Follow-up cancelled'),
  rejectedCapture('Capture rejected or invalid'),
  insufficientEvidence('Insufficient evidence'),
  failed('Assessment failed'),
  expired('Plan expired'),
  superseded('Plan superseded'),
  unknown('Unknown comparison status');

  const ComparisonLifecycle(this.label);
  final String label;
  bool get inactive =>
      this == cancelled || this == expired || this == superseded;
}

enum InterventionKind {
  routine('Routine'),
  experiment('Experiment'),
  productIntervention('Product intervention'),
  followUpPlan('Follow-up plan'),
  unknown('Unknown intervention');

  const InterventionKind(this.label);
  final String label;
}

enum CaptureRole { baseline, followUp }

enum ComparisonFreshness { fresh, stale, unknown }

enum AssessmentStatus {
  unavailable,
  pending,
  processing,
  available,
  failed,
  insufficientEvidence,
  unknown,
}

enum AssessmentSource {
  nonclinicalObservation,
  aiObservation,
  clinicianAuthored,
  unknown,
}

enum AssessmentReview {
  notRequested('Not requested'),
  pending('Pending'),
  recorded('Recorded'),
  unknown('Unknown');

  const AssessmentReview(this.label);
  final String label;
}

class SchedulingDecision {
  SchedulingDecision({
    required this.recordId,
    required this.source,
    required this.recordedAt,
  }) {
    comparisonId(recordId);
    comparisonUtc(recordedAt);
  }
  final String recordId;
  final SchedulingSource source;
  final DateTime recordedAt;
}

class FollowUpSchedule {
  FollowUpSchedule({this.instantUtc, this.reportedTimezone, this.serverDue}) {
    if (instantUtc != null) comparisonUtc(instantUtc!);
    if (reportedTimezone != null && reportedTimezone!.trim().isEmpty) {
      throw const FormatException('Invalid reported timezone');
    }
  }
  final DateTime? instantUtc;
  // Display-only server label; UTC instant is canonical. Never invent a zone,
  // interpret a naive timestamp, apply DST rules or compute clinical due status.
  final String? reportedTimezone;
  final bool? serverDue;
}

class InterventionReference {
  InterventionReference({
    required this.kind,
    required this.recordId,
    required this.relationshipRecordId,
  }) {
    comparisonId(recordId);
    comparisonId(relationshipRecordId);
  }
  final InterventionKind kind;
  final String recordId, relationshipRecordId;
}

class PlanCaptureAssociation {
  PlanCaptureAssociation({
    required this.planId,
    required this.planRevision,
    required this.owner,
    required this.role,
    required this.captureId,
    required this.relationshipRecordId,
    this.metadata,
  }) {
    for (final id in [planId, owner, captureId, relationshipRecordId]) {
      comparisonId(id);
    }
    if (planRevision < 1 ||
        (metadata != null &&
            (metadata!.id != captureId || metadata!.owner != owner))) {
      throw const FormatException('Capture association mismatch');
    }
  }
  final String planId, owner, captureId, relationshipRecordId;
  final int planRevision;
  final CaptureRole role;
  // Optional owned by-ID readback; unavailable metadata is never fabricated.
  final GuidedCaptureRecord? metadata;
}

class ComparisonPlan {
  ComparisonPlan({
    required this.id,
    required this.owner,
    required this.revision,
    required this.recordedAt,
    required this.lifecycle,
    required List<SchedulingDecision> decisions,
    this.resolvedDecisionId,
    this.resolutionNote,
    this.schedule,
    this.confirmation = PatientConfirmation.unknown,
    this.intervention,
    this.baseline,
    this.followUp,
  }) : decisions = List.unmodifiable(decisions) {
    comparisonId(id);
    comparisonId(owner);
    comparisonUtc(recordedAt);
    if (revision < 1 ||
        this.decisions.map((d) => d.recordId).toSet().length !=
            this.decisions.length ||
        (resolvedDecisionId != null &&
            !this.decisions.any((d) => d.recordId == resolvedDecisionId))) {
      throw const FormatException('Unverified plan authority');
    }
    for (final role in CaptureRole.values) {
      final link = role == CaptureRole.baseline ? baseline : followUp;
      if (link != null &&
          (link.owner != owner ||
              link.planId != id ||
              link.planRevision != revision ||
              link.role != role)) {
        throw const FormatException('Plan capture relationship mismatch');
      }
    }
    if (baseline != null &&
        followUp != null &&
        baseline!.captureId == followUp!.captureId) {
      throw const FormatException(
        'A reference pair requires distinct linked captures',
      );
    }
  }
  final String id, owner;
  final int revision;
  final DateTime recordedAt;
  final ComparisonLifecycle lifecycle;
  final List<SchedulingDecision> decisions;
  final String? resolvedDecisionId, resolutionNote;
  final FollowUpSchedule? schedule;
  final PatientConfirmation confirmation;
  final InterventionReference? intervention;
  final PlanCaptureAssociation? baseline, followUp;
  SchedulingDecision? get resolvedDecision {
    for (final decision in decisions) {
      if (decision.recordId == resolvedDecisionId) return decision;
    }
    return null;
  }

  bool get active =>
      !lifecycle.inactive && lifecycle != ComparisonLifecycle.unknown;

  /// Conservative presentation gate, not a clinical/AI-processing permission.
  /// Patient confirmation alone is not a scheduling authority. A future wire
  /// adapter must verify the persisted decision and consent requirements.
  bool get confirmedSchedule =>
      active &&
      ![
        ComparisonLifecycle.notScheduled,
        ComparisonLifecycle.pendingConfirmation,
      ].contains(lifecycle) &&
      schedule?.instantUtc != null &&
      confirmation == PatientConfirmation.confirmed &&
      [
        SchedulingSource.doctorDirected,
        SchedulingSource.aiProposed,
      ].contains(resolvedDecision?.source);

  bool sameRevisionDefinition(ComparisonPlan other) =>
      id == other.id &&
      owner == other.owner &&
      revision == other.revision &&
      recordedAt == other.recordedAt &&
      lifecycle == other.lifecycle &&
      confirmation == other.confirmation &&
      resolvedDecisionId == other.resolvedDecisionId &&
      resolutionNote == other.resolutionNote &&
      schedule?.instantUtc == other.schedule?.instantUtc &&
      schedule?.serverDue == other.schedule?.serverDue &&
      schedule?.reportedTimezone == other.schedule?.reportedTimezone &&
      intervention?.kind == other.intervention?.kind &&
      intervention?.recordId == other.intervention?.recordId &&
      intervention?.relationshipRecordId ==
          other.intervention?.relationshipRecordId &&
      baseline?.captureId == other.baseline?.captureId &&
      baseline?.relationshipRecordId == other.baseline?.relationshipRecordId &&
      followUp?.captureId == other.followUp?.captureId &&
      followUp?.relationshipRecordId == other.followUp?.relationshipRecordId &&
      decisions.length == other.decisions.length &&
      List.generate(
        decisions.length,
        (i) =>
            decisions[i].recordId == other.decisions[i].recordId &&
            decisions[i].source == other.decisions[i].source &&
            decisions[i].recordedAt == other.decisions[i].recordedAt,
      ).every((same) => same);
}

class ComparisonAssessment {
  ComparisonAssessment({
    required this.id,
    required this.owner,
    required this.planId,
    required this.planRevision,
    required this.revision,
    required this.status,
    required this.source,
    this.sourceVersion,
    this.generatedAt,
    this.baselineCaptureId,
    this.followUpCaptureId,
    this.review = AssessmentReview.unknown,
    this.reviewRecordId,
    List<String> observations = const [],
    List<String> evidenceRecords = const [],
    List<String> limitations = const [],
    List<String> uncertainties = const [],
  }) : observations = List.unmodifiable(observations),
       evidenceRecords = List.unmodifiable(evidenceRecords),
       limitations = List.unmodifiable(limitations),
       uncertainties = List.unmodifiable(uncertainties) {
    for (final value in [id, owner, planId, ...this.evidenceRecords]) {
      comparisonId(value);
    }
    for (final value in [
      baselineCaptureId,
      followUpCaptureId,
      reviewRecordId,
    ]) {
      if (value != null) comparisonId(value);
    }
    if (generatedAt != null) comparisonUtc(generatedAt!);
    if (revision < 1 ||
        planRevision < 1 ||
        (status == AssessmentStatus.available && generatedAt == null) ||
        (review == AssessmentReview.recorded && reviewRecordId == null) ||
        (status != AssessmentStatus.available &&
            this.observations.isNotEmpty)) {
      throw const FormatException('Unsupported assessment evidence');
    }
  }
  final String id, owner, planId;
  final int planRevision, revision;
  final AssessmentStatus status;
  final AssessmentSource source;
  final String? sourceVersion,
      baselineCaptureId,
      followUpCaptureId,
      reviewRecordId;
  final DateTime? generatedAt;
  final AssessmentReview review;
  final List<String> observations, evidenceRecords, limitations, uncertainties;
}

class ComparisonSnapshot {
  ComparisonSnapshot({
    required this.plan,
    required this.observedAt,
    required this.freshness,
    this.assessment,
  }) {
    comparisonUtc(observedAt);
    final result = assessment;
    if (result == null) return;
    if (result.owner != plan.owner ||
        result.planId != plan.id ||
        result.planRevision != plan.revision ||
        result.baselineCaptureId != plan.baseline?.captureId ||
        result.followUpCaptureId != plan.followUp?.captureId ||
        (result.status == AssessmentStatus.available &&
            (plan.baseline == null || plan.followUp == null))) {
      throw const FormatException(
        'Assessment does not match current plan evidence',
      );
    }
  }
  final ComparisonPlan plan;
  final DateTime observedAt;
  final ComparisonFreshness freshness;
  final ComparisonAssessment? assessment;
}

/// A handoff context, NOT a saved association or permission to POST. A future
/// camera action must use a verified write adapter and authoritative readback.
class FollowUpCaptureContext {
  const FollowUpCaptureContext({
    required this.planId,
    required this.owner,
    required this.planRevision,
    required this.sessionGeneration,
  });
  final String planId, owner;
  final int planRevision, sessionGeneration;
}
