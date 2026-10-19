import '../clinical/clinical_models.dart' show object, timestamp;
import '../doctor/access_invitation.dart' show ScopedGrant;
import '../doctor/doctor_models.dart';
import '../integration/contract.dart';
import '../integration/operation_identity.dart';
import '../services/api_service.dart';
import 'operation_journal.dart';

/// Patient consent GrantAttempt and doctor claim ClinicalAttempt are distinct
/// envelopes. Bearer invitation contents never leave this reader or enter storage.
class GrantReceiptReader implements JournalReceiptReader {
  GrantReceiptReader(this.api, this.generation);
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

  String contract(OperationIdentity i) {
    if (i.role == 'patient') {
      if (i.path == 'doctor/generate-qr' &&
          i.receiptPath == 'doctor/consent-attempts/issue') {
        return 'issue';
      }
      if (RegExp(r'^doctor/access/[A-Za-z0-9_-]+$').hasMatch(i.path) &&
          i.receiptPath == 'doctor/consent-attempts/revoke') {
        return 'revoke';
      }
      if (i.path == 'doctor/revoke/${i.owner}' &&
          i.receiptPath == 'doctor/consent-attempts/revoke_all') {
        return 'revoke_all';
      }
    }
    if (i.role == 'doctor' &&
        i.path == 'doctor/claim' &&
        i.scope['patient_id'] != null &&
        i.receiptPath ==
            'doctor/patients/${i.scope['patient_id']}/attempts/claim') {
      return 'claim';
    }
    throw const FormatException('Unsupported consent receipt identity');
  }

  Future<List<DoctorGrant>> grants(OperationIdentity i) async {
    final raw = (await api.integrationResource(
      'doctor/access',
      generation,
    )).data;
    guard(i);
    if (raw is! List) throw const FormatException('Invalid current grant list');
    final rows = raw
        .map((v) => DoctorGrant.fromApi(object(v), patient: i.owner))
        .toList();
    if (rows.map((v) => v.id).toSet().length != rows.length) {
      throw const FormatException('Duplicate grant identity');
    }
    return rows;
  }

  Future<void> verifyClaim(OperationIdentity i, String access) async {
    final patient = i.scope['patient_id'] as String;
    final raw = object(
      (await api.integrationResource(
        'doctor/patients/$patient',
        generation,
      )).data,
    );
    guard(i);
    if (raw['patient_id'] != patient) {
      throw const FormatException('Wrong claimed patient');
    }
    final current = ScopedGrant(
      object(raw['access']),
      patient: patient,
      doctor: i.owner,
    );
    if (current.grant.id != access ||
        !current.grant.active(DateTime.now().toUtc())) {
      throw RecoveryPermissionLost();
    }
  }

  Never failure(IntegrationFailure e) {
    if ([403, 404, 409, 410].contains(e.status)) throw RecoveryPermissionLost();
    throw e;
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    final operation = contract(i);
    try {
      final raw = object(
        (await api.integrationResource(
          '${i.receiptPath}/${i.key}',
          generation,
        )).data,
      );
      guard(i);
      resourceId(raw['attempt_id']);
      final status = raw['status'];
      if (raw['schema_version'] != 1 ||
          !['committed', 'unknown', 'expired'].contains(status)) {
        throw const FormatException('Invalid consent attempt');
      }
      if (status == 'unknown') {
        if (raw['result'] != null || raw['retry_safe'] != false) {
          throw const FormatException('Unknown consent is not rejection');
        }
        return const ReceiptEvidence(ReceiptOutcome.unknown);
      }
      if (raw['actor_id'] != i.owner ||
          raw['operation'] != operation ||
          raw['snapshot_basis'] != 'original_committed_not_current') {
        throw const FormatException('Wrong original consent actor');
      }
      final access = resourceId(raw['access_id']);
      if (operation == 'claim') {
        if (raw['patient_id'] != i.scope['patient_id'] ||
            raw['resource_id'] != access) {
          throw const FormatException('Wrong original claim');
        }
        final recorded = timestamp(raw['recorded_at']),
            expires = timestamp(raw['expires_at']);
        if (!expires.isAfter(recorded) ||
            expires.difference(recorded) > const Duration(days: 30)) {
          throw const FormatException('Invalid claim retention');
        }
        if (status == 'expired') {
          if (raw['result'] != null) {
            throw const FormatException('Expired claim content');
          }
          return ReceiptEvidence(ReceiptOutcome.expired, resource: access);
        }
        final result = raw['result'];
        if (result == null) {
          return ReceiptEvidence(ReceiptOutcome.committed, resource: access);
        }
        final resultMap = object(result);
        final grant = ScopedGrant(
          object(resultMap['access']),
          patient: i.scope['patient_id'] as String,
          doctor: i.owner,
        );
        if (resultMap['success'] != true ||
            grant.grant.id != access ||
            i.scope['access_id'] != null && i.scope['access_id'] != access) {
          throw const FormatException('Wrong claim result');
        }
        await verifyClaim(i, access);
        return ReceiptEvidence(ReceiptOutcome.committed, resource: access);
      }
      if (raw['owner_id'] != i.owner ||
          operation == 'revoke' && access != i.path.split('/').last ||
          operation == 'revoke_all' && access != i.owner) {
        throw const FormatException('Wrong original patient consent');
      }
      final availability = raw['result_availability'];
      if (status == 'expired') {
        if (availability != 'expired' || raw['result'] != null) {
          throw const FormatException('Expired consent content');
        }
        return ReceiptEvidence(ReceiptOutcome.expired, resource: access);
      }
      if (!['retained', 'unavailable'].contains(availability)) {
        throw const FormatException('Invalid consent availability');
      }
      if (availability == 'unavailable') {
        if (raw['result'] != null) {
          throw const FormatException('Unavailable invitation content');
        }
        return ReceiptEvidence(ReceiptOutcome.committed, resource: access);
      }
      final result = object(raw['result']);
      if (operation == 'revoke_all') {
        if (result['success'] != true) {
          throw const FormatException('Unconfirmed bulk withdrawal');
        }
      } else if (operation == 'revoke') {
        final grant = DoctorGrant.fromApi(result, patient: i.owner);
        if (grant.id != access || !grant.confirmedRevoked) {
          throw const FormatException('Unconfirmed selected withdrawal');
        }
      } else {
        final grant = ScopedGrant(object(result['access']), patient: i.owner);
        if (grant.grant.id != access ||
            grant.grant.status != 'pending' ||
            grant.effective.isNotEmpty) {
          throw const FormatException('Wrong original invitation scope');
        }
        if (i.scope['doctor_id'] != null &&
            grant.grant.doctorIdValue != i.scope['doctor_id']) {
          throw const FormatException('Wrong intended clinician');
        }
        // access_token/qr_payload are deliberately neither returned nor retained.
      }
      return ReceiptEvidence(ReceiptOutcome.committed, resource: access);
    } on IntegrationFailure catch (e) {
      failure(e);
    }
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    guard(i);
    final operation = contract(i);
    if (r.outcome != ReceiptOutcome.committed || r.resource == null) {
      return false;
    }
    try {
      if (operation == 'claim') {
        await verifyClaim(i, r.resource!);
        return true;
      }
      final rows = await grants(i);
      if (operation == 'issue') {
        return false; // Never restore or advertise old bearer validity.
      }
      if (operation == 'revoke_all') {
        return rows.every((v) => !['active', 'pending'].contains(v.status));
      }
      return rows.any((v) => v.id == r.resource && v.confirmedRevoked);
    } on IntegrationFailure catch (e) {
      failure(e);
    }
  }
}
