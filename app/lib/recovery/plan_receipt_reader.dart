import '../clinical/clinical_models.dart' show object;
import '../integration/contract.dart';
import '../integration/operation_identity.dart';
import '../plans/plan_models.dart';
import '../plans/plan_evaluation.dart';
import '../services/api_service.dart';
import 'operation_journal.dart';

/// ClinicalPlanAttempt only. Plans, comparison jobs and their current projections
/// retain their different DTOs. No invitation, Agent or cancellation lookup inferred.
class PlanReceiptReader implements JournalReceiptReader {
  PlanReceiptReader(this.api, this.generation);
  final ApiService api;
  final int generation;
  void guard(OperationIdentity i) {
    if (!api.isCurrentSession(generation) ||
        i.owner != api.authenticatedOwner ||
        i.role != api.authenticatedRole ||
        !(api.canReadPatientClinicalStatus || api.canReadDoctorWorkspace)) {
      throw RecoverySessionLost();
    }
  }

  ({String? id, String patient, String operation}) contract(
    OperationIdentity i,
  ) {
    final create = RegExp(
      r'^clinical-plans/creation-attempts/([A-Za-z0-9_-]+)$',
    ).firstMatch(i.receiptPath);
    if (i.path == 'clinical-plans' &&
        create != null &&
        i.role == 'doctor' &&
        i.scope['access_id'] != null) {
      if (i.scope['doctor_id'] != null && i.scope['doctor_id'] != i.owner ||
          i.scope['patient_id'] != null && i.scope['patient_id'] != create[1]) {
        throw const FormatException('Wrong creation scope');
      }
      return (id: null, patient: create[1]!, operation: 'create');
    }
    final match = RegExp(
      r'^clinical-plans/([A-Za-z0-9_-]+)/(acknowledge|reschedule|cancel|review|capture|evaluation|evaluation/review)$',
    ).firstMatch(i.path);
    if (match == null ||
        i.scope['patient_id'] == null ||
        i.scope['doctor_id'] == null ||
        i.scope['access_id'] == null ||
        i.scope['expected_revision'] is! int ||
        (i.scope['expected_revision'] as int) < 1 ||
        (i.role == 'patient' ? i.scope['patient_id'] : i.scope['doctor_id']) !=
            i.owner) {
      throw const FormatException('Unsupported original plan identity');
    }
    final action = match[2]!,
        operation = action == 'evaluation'
            ? 'evaluate'
            : action == 'evaluation/review'
            ? 'evaluation_review'
            : action;
    if (i.receiptPath != 'clinical-plans/${match[1]}/attempts/$operation' ||
        ['reschedule', 'review', 'evaluation_review'].contains(operation) &&
            i.role != 'doctor' ||
        ['acknowledge', 'capture', 'evaluate'].contains(operation) &&
            i.role != 'patient' ||
        operation == 'evaluation_review' && i.scope['job_id'] == null) {
      throw const FormatException('Wrong original plan contract');
    }
    return (
      id: match[1]!,
      patient: i.scope['patient_id'] as String,
      operation: operation,
    );
  }

  ClinicalPlan parsePlan(Object? raw, OperationIdentity i) {
    final c = contract(i);
    final plan = ClinicalPlan.fromApi(object(raw), i.owner, i.role);
    if (plan.patient != c.patient ||
        plan.grant != i.scope['access_id'] ||
        c.id != null && plan.id != c.id ||
        i.scope['doctor_id'] != null && plan.doctor != i.scope['doctor_id']) {
      throw RecoveryPermissionLost();
    }
    return plan;
  }

  Future<ClinicalPlan> current(OperationIdentity i, String id) async {
    final raw = (await api.integrationResource(
      'clinical-plans/$id',
      generation,
    )).data;
    guard(i);
    final plan = parsePlan(raw, i);
    if (plan.id != id) throw const FormatException('Wrong current plan');
    return plan;
  }

  Never failure(IntegrationFailure e) {
    if ([403, 404, 409, 410].contains(e.status)) throw RecoveryPermissionLost();
    throw e;
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    final c = contract(i);
    try {
      // Non-create reads are bound to original current plan/grant before lookup.
      final plan = c.id == null ? null : await current(i, c.id!);
      final raw = object(
        (await api.integrationResource(
          '${i.receiptPath}/${i.key}',
          generation,
        )).data,
      );
      guard(i);
      resourceId(raw['attempt_id']);
      final status = raw['status'];
      if (!['committed', 'unknown', 'expired'].contains(status)) {
        throw const FormatException('Invalid plan attempt');
      }
      if (status != 'committed') {
        if (raw['result'] != null) {
          throw const FormatException(
            'Unavailable plan receipt contains content',
          );
        }
        return ReceiptEvidence(
          status == 'unknown' ? ReceiptOutcome.unknown : ReceiptOutcome.expired,
        );
      }
      if (['evaluate', 'evaluation_review'].contains(c.operation)) {
        final job = PlanEvaluation(object(raw['result']), plan!);
        if (c.operation == 'evaluate' && job.state != 'queued' ||
            c.operation == 'evaluation_review' &&
                (!['reviewed', 'rejected'].contains(job.state) ||
                    job.wire['human_review'] is! Map)) {
          throw const FormatException(
            'Wrong original evaluation operation result',
          );
        }
        if (job.state == 'not_requested' ||
            c.operation == 'evaluation_review' &&
                job.wire['id'] != i.scope['job_id'] ||
            job.wire['plan_revision'] !=
                (i.scope['expected_revision'] as int) + 1) {
          throw const FormatException('Wrong original evaluation revision');
        }
        await current(i, plan.id);
        return ReceiptEvidence(
          ReceiptOutcome.committed,
          resource: job.wire['id'] as String,
          revision: job.wire['plan_revision'] as int,
        );
      }
      final original = parsePlan(raw['result'], i);
      final expectedState = {
        'create': 'proposed',
        'acknowledge': 'scheduled',
        'reschedule': 'proposed',
        'cancel': 'cancelled',
        'review': 'reviewed',
        'capture': 'captured',
      }[c.operation];
      if (original.state != expectedState ||
          original.revision !=
              (c.operation == 'create'
                  ? 1
                  : (i.scope['expected_revision'] as int) + 1)) {
        throw const FormatException('Wrong original plan result');
      }
      await current(i, original.id);
      return ReceiptEvidence(
        ReceiptOutcome.committed,
        resource: original.id,
        revision: original.revision,
      );
    } on IntegrationFailure catch (e) {
      failure(e);
    }
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    guard(i);
    final c = contract(i);
    if (r.outcome != ReceiptOutcome.committed ||
        r.resource == null ||
        r.revision == null) {
      return false;
    }
    try {
      final evaluating = [
        'evaluate',
        'evaluation_review',
      ].contains(c.operation);
      final plan = await current(i, evaluating ? c.id! : r.resource!);
      if (!evaluating) return plan.revision == r.revision;
      final raw = (await api.integrationResource(
        'clinical-plans/${plan.id}/evaluation',
        generation,
      )).data;
      guard(i);
      final job = PlanEvaluation(object(raw), plan);
      await current(i, plan.id);
      return job.state != 'not_requested' &&
          job.currentState != 'cancelled' &&
          job.wire['id'] == r.resource &&
          job.wire['plan_revision'] == r.revision;
    } on IntegrationFailure catch (e) {
      failure(e);
    }
  }
}
