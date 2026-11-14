import '../clinical/clinical_controller.dart';
import '../clinical/clinical_models.dart';
import '../observations/observation_controller.dart';
import 'home_response.dart';

enum HomeAction {
  safety,
  clinician,
  verifyGuidance,
  uncertainObservation,
  history,
  experiment,
  observe,
}

class HomeNextAction {
  const HomeNextAction(this.action, this.title, this.reason);
  final HomeAction action;
  final String title, reason;

  /// Presentation rules over server projections, never a medical assessment.
  static HomeNextAction select({
    required ClinicalController clinical,
    required ObservationController observations,
    required bool hasExperiment,
    HomeObservationStatus? observationStatus,
  }) {
    final s = clinical.safety;
    final r = clinical.review;
    final embedded = r.value?.safety;
    if (s.value?.level == SafetyLevel.urgent ||
        embedded?.level == SafetyLevel.urgent) {
      return const HomeNextAction(
        HomeAction.safety,
        'Review urgent safety guidance',
        'An urgent server warning is shown above. Previously retrieved warnings remain visible until refreshed.',
      );
    }
    if (r.value?.hasUrgentGuidance == true) {
      return HomeNextAction(
        HomeAction.clinician,
        'Review urgent clinician guidance',
        r.stale
            ? 'Previously retrieved urgent clinician guidance remains relevant to review. Refresh to verify current instructions; this view cannot clear it.'
            : 'Patient-visible clinician guidance requires urgent attention. Open the recorded instructions; no treatment is performed by this action.',
      );
    }
    if (!r.stale && r.value?.needsAttention == true) {
      return const HomeNextAction(
        HomeAction.clinician,
        'Open clinician guidance',
        'Your current patient-visible clinician status includes guidance or a review in progress. A pending review is not a completed clinician decision.',
      );
    }
    if ((!s.stale &&
            s.value?.supported == true &&
            s.value?.level == SafetyLevel.doctorReview) ||
        (!r.stale &&
            embedded?.supported == true &&
            embedded?.level == SafetyLevel.doctorReview)) {
      return const HomeNextAction(
        HomeAction.safety,
        'Review safety guidance',
        'The Safety Engine recommends clinician review. This is separate from a clinician decision.',
      );
    }
    if (observations.phase == ObservationPhase.uncertain) {
      return const HomeNextAction(
        HomeAction.uncertainObservation,
        'Review an unconfirmed observation',
        'A previous submission has an uncertain outcome. Open the existing flow to review history; do not resend automatically.',
      );
    }
    if (s.phase != ClinicalPhase.ready ||
        s.stale ||
        s.value?.supported != true ||
        r.phase != ClinicalPhase.ready ||
        r.stale ||
        r.value?.supported != true) {
      return const HomeNextAction(
        HomeAction.verifyGuidance,
        'Verify safety & clinician information',
        'Some guidance is unavailable, refreshing or unsupported. Missing information does not establish safety.',
      );
    }
    if (observationStatus?.completedToday == false) {
      return const HomeNextAction(
        HomeAction.observe,
        'Start an observation',
        'The current server view has no observation recorded today (UTC). You may record what you notice; this is optional, not a due schedule.',
      );
    }
    if (hasExperiment) {
      return const HomeNextAction(
        HomeAction.experiment,
        'Open your experiment',
        'Home reports an existing experiment. Its scheduled day is separate from reporting and results.',
      );
    }
    if (observationStatus?.completedToday == true) {
      return const HomeNextAction(
        HomeAction.history,
        'View saved observations',
        'The current server view confirms an observation today (UTC). Review its history; this is not proof of a measurement day or clinical improvement.',
      );
    }
    return const HomeNextAction(
      HomeAction.observe,
      'Start an observation',
      'Current observation completion is unavailable. You may record what you notice or open history. Missing status does not establish an incomplete day; no due schedule is inferred.',
    );
  }
}
