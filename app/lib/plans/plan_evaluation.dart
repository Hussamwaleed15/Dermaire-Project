import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import 'plan_models.dart';

/// A queue/status envelope is neither completed inference nor clinical clearance.
class PlanEvaluation {
  PlanEvaluation(Map<String, dynamic> v, ClinicalPlan plan)
    : state = text(v['state']),
      effective = v['effective_state'] as String?,
      wire = Map.unmodifiable(v) {
    if (state == 'not_requested') {
      if (v['inference'] != null || v.containsKey('id')) {
        throw const FormatException('Unexpected evaluation');
      }
      return;
    }
    resourceId(v['id']);
    final input = object(v['input']);
    if (v['schema_version'] != 'comparison-job-1' ||
        ![
          'queued',
          'running',
          'unavailable',
          'pending_human_review',
          'cancelled',
          'reviewed',
          'rejected',
        ].contains(state) ||
        (effective != null && effective != 'cancelled') ||
        input['schema_version'] != 'comparison-input-1' ||
        input['plan_id'] != plan.id ||
        input['baseline_capture_id'] != plan.baseline ||
        input['followup_capture_id'] != plan.followup ||
        count(v['plan_revision']) < 1 ||
        count(input['plan_revision']) < 1 ||
        count(input['consent_revision']) < 1 ||
        v['medical_resources_modified'] != false ||
        v['clinical_clearance'] != false) {
      throw const FormatException('Unverified evaluation');
    }
    count(v['attempts']);
    timestamp(v['updated_at']);
    if (v['inference'] != null) {
      final inference = object(v['inference']);
      if (inference['schema_version'] != 'comparison-model-boundary-1' ||
          inference['clinical_clearance'] != false ||
          ![
            'unavailable',
            'pending_human_review',
          ].contains(inference['status'])) {
        throw const FormatException('Invalid inference envelope');
      }
      if (inference['status'] == 'unavailable' && inference['result'] != null) {
        throw const FormatException('Unavailable evaluation has a result');
      }
      if (inference['status'] == 'pending_human_review' &&
          inference['result'] is! Map) {
        throw const FormatException('Missing inference evidence');
      }
      if (inference['result'] != null) {
        final result = object(inference['result']);
        if (result['schema_version'] != 'comparison-evidence-1' ||
            result['quality_flags'] is! List ||
            (result['quality_flags'] as List).any(
              (flag) => ![
                'lighting_mismatch',
                'pose_mismatch',
                'blur',
                'occlusion',
                'insufficient_evidence',
              ].contains(flag),
            )) {
          throw const FormatException('Invalid image-quality evidence');
        }
        if (result['baseline_capture_id'] != plan.baseline ||
            result['followup_capture_id'] != plan.followup ||
            result['provenance'] != 'nonclinical_image_quality_only' ||
            inference['status'] != 'pending_human_review') {
          throw const FormatException('Unverified inference provenance');
        }
        if (inference['model_version'] is! String ||
            !RegExp(
              r'^[a-fA-F0-9]{64}$',
            ).hasMatch(inference['artifact_sha256'] as String? ?? '')) {
          throw const FormatException('Unverified model artifact');
        }
      }
    }
    if (v['human_review'] != null) {
      final review = object(v['human_review']);
      if (review['provenance'] != 'clinician_authored' ||
          review['clinical_clearance'] != false ||
          review['clinical_accuracy_validated'] != false ||
          review['actor_id'] != plan.doctor ||
          review['job_id'] != v['id']) {
        throw const FormatException('Unverified inference review');
      }
      text(review['assessment']);
      timestamp(review['reviewed_at']);
    }
  }
  final String state;
  final String? effective;
  final Map<String, dynamic> wire;
  String get currentState => effective ?? state;
}
