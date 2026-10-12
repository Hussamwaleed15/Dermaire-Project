import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../capture/guided_capture_models.dart';
import 'comparison_domain.dart';
import 'comparison_repository.dart';

enum ComparisonPhase {
  idle,
  loading,
  unavailable,
  empty,
  ready,
  stale,
  failed,
  ended,
}

class ComparisonController extends ChangeNotifier {
  ComparisonController(
    this.api, {
    required this.planId,
    ComparisonRepository? repository,
    this.timeout = const Duration(seconds: 20),
  }) : repository = repository ?? const UnsupportedComparisonRepository(),
       context = ComparisonReadContext(
         api.observationOwner ?? '',
         api.sessionGeneration,
       ) {
    comparisonId(planId);
    api.addListener(sessionChanged);
  }
  final ApiService api;
  final String planId;
  final ComparisonRepository repository;
  final ComparisonReadContext context;
  final Duration timeout;
  bool _disposed = false;
  int _request = 0;
  ComparisonSnapshot? _snapshot;
  ComparisonPlan? _latestDefinition;
  String? _assessmentId;
  int _assessmentRevision = 0;
  ComparisonPhase phase = ComparisonPhase.idle;
  String? error;
  bool get current =>
      !_disposed &&
      context.owner.isNotEmpty &&
      api.isCurrentSession(context.generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == context.owner;
  ComparisonSnapshot? get snapshot =>
      current && phase == ComparisonPhase.ready ? _snapshot : null;
  // No local write, AI consent, association or scheduling permission is invented.
  bool get canAssociateCapture => false;
  bool get canRequestAssessment => false;
  FollowUpCaptureContext? get captureContext {
    final plan = snapshot?.plan;
    if (plan == null ||
        !plan.confirmedSchedule ||
        plan.schedule?.serverDue != true ||
        plan.schedule?.instantUtc == null ||
        plan.baseline == null ||
        plan.resolvedDecision == null ||
        plan.resolvedDecision?.source == SchedulingSource.unknown ||
        plan.confirmation != PatientConfirmation.confirmed ||
        ![
          ComparisonLifecycle.due,
          ComparisonLifecycle.awaitingCapture,
        ].contains(plan.lifecycle)) {
      return null;
    }
    return FollowUpCaptureContext(
      planId: plan.id,
      owner: context.owner,
      planRevision: plan.revision,
      sessionGeneration: context.generation,
    );
  }

  /// Validates a still-current camera handoff candidate. This does not save a
  /// link, request analysis or confer clinical/AI-processing authorization.
  bool recognizesUnassociatedCapture(
    FollowUpCaptureContext request,
    GuidedCaptureRecord record,
  ) {
    final expected = captureContext;
    return expected != null &&
        request.planId == expected.planId &&
        request.owner == expected.owner &&
        request.planRevision == expected.planRevision &&
        request.sessionGeneration == expected.sessionGeneration &&
        record.owner == expected.owner &&
        record.state == 'accepted' &&
        record.stored;
  }

  void sessionChanged() {
    if (!current) {
      _request++;
      _snapshot = null;
      _latestDefinition = null;
      _assessmentId = null;
      _assessmentRevision = 0;
      error = null;
      phase = ComparisonPhase.ended;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!current) return;
    final request = ++_request;
    _snapshot = null;
    error = null;
    phase = ComparisonPhase.loading;
    notifyListeners();
    try {
      final value = await repository.readPlan(planId, context).timeout(timeout);
      if (!current || request != _request) return;
      if (value == null) {
        phase = ComparisonPhase.empty;
      } else {
        final plan = value.plan, previous = _latestDefinition;
        if (plan.id != planId ||
            plan.owner != context.owner ||
            (previous != null &&
                (plan.revision < previous.revision ||
                    plan.revision == previous.revision &&
                        !plan.sameRevisionDefinition(previous)))) {
          throw const FormatException('Plan identity/revision is unverified');
        }
        final assessment = value.assessment;
        if (previous?.revision == plan.revision &&
            assessment?.id == _assessmentId &&
            assessment != null &&
            assessment.revision < _assessmentRevision) {
          throw const FormatException('Assessment revision regressed');
        }
        // Remember observed revision watermarks even when freshness prevents
        // presentation. A stale cancellation cannot be followed by an older
        // 'fresh' plan that resurrects the previous images.
        _latestDefinition = plan;
        if (previous?.revision != plan.revision) {
          _assessmentId = null;
          _assessmentRevision = 0;
        }
        if (assessment != null) {
          _assessmentId = assessment.id;
          _assessmentRevision = assessment.revision;
        }
        if (value.freshness != ComparisonFreshness.fresh) {
          phase = ComparisonPhase.stale;
        } else {
          _snapshot = value;
          phase = ComparisonPhase.ready;
        }
      }
    } on ComparisonUnsupported {
      if (!current || request != _request) return;
      phase = ComparisonPhase.unavailable;
    } catch (e) {
      if (!current || request != _request) return;
      phase = ComparisonPhase.failed;
      error = e is TimeoutException
          ? 'Comparison read timed out. Please retry.'
          : 'Comparison information could not be verified. Please retry.';
    }
    if (current && request == _request) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _snapshot = null;
    _latestDefinition = null;
    _assessmentId = null;
    api.removeListener(sessionChanged);
    super.dispose();
  }
}
