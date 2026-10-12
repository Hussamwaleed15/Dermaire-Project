import '../clinical/clinical_controller.dart';
import '../clinical/clinical_models.dart';
import '../observations/observation_controller.dart';

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
    if (!r.stale &&
        r.value?.supported == true &&
        (r.value?.state == ReviewState.followUp ||
            r.value?.decision?.level == SafetyLevel.urgent ||
            r.value?.decision?.level == SafetyLevel.doctorReview)) {
      return const HomeNextAction(
        HomeAction.clinician,
        'Open clinician guidance',
        'Your current patient-visible clinician status includes an action or follow-up.',
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
    if (observations.phase == ObservationPhase.uncertain) {
      return const HomeNextAction(
        HomeAction.uncertainObservation,
        'Review an unconfirmed observation',
        'A previous submission has an uncertain outcome. Open the existing flow to review history; do not resend automatically.',
      );
    }
    if (!observations.historyStale &&
        observations.historyPhase == ObservationHistoryPhase.ready &&
        observations.rows?.isNotEmpty == true) {
      return const HomeNextAction(
        HomeAction.history,
        'View saved observations',
        'Your server history contains saved records. They do not establish clinical improvement or today’s completion.',
      );
    }
    if (hasExperiment) {
      return const HomeNextAction(
        HomeAction.experiment,
        'Open your experiment',
        'Home reports an existing experiment. Its scheduled day is separate from reporting and results.',
      );
    }
    return const HomeNextAction(
      HomeAction.observe,
      'Start an observation',
      'Record what you notice. Optional questions can remain unanswered.',
    );
  }
}
