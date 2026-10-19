import '../clinical/clinical_models.dart' show object;
import '../integration/contract.dart';
import '../integration/operation_identity.dart';
import '../messaging/messaging_models.dart';
import '../services/api_service.dart';
import 'operation_journal.dart';

/// A participant-authored message is immutable. Original thread authorization
/// and separate messaging consent are re-read, never reconstructed from a body.
class MessageReceiptReader implements JournalReceiptReader {
  MessageReceiptReader(this.api, this.generation);
  final ApiService api;
  final int generation;
  void guard(OperationIdentity i) {
    if (!api.isCurrentSession(generation) ||
        api.authenticatedOwner != i.owner ||
        api.authenticatedRole != i.role ||
        !(api.canReadPatientClinicalStatus || api.canReadDoctorWorkspace)) {
      throw RecoverySessionLost();
    }
  }

  String contract(OperationIdentity i) {
    final match = RegExp(
      r'^messaging/threads/([A-Za-z0-9_-]+)/messages$',
    ).firstMatch(i.path);
    if (match == null ||
        i.receiptPath != 'messaging/threads/${match[1]}/attempts' ||
        i.scope['access_id'] == null ||
        i.scope['patient_id'] == null ||
        i.scope['doctor_id'] == null ||
        (i.role == 'patient' ? i.scope['patient_id'] : i.scope['doctor_id']) !=
            i.owner) {
      throw const FormatException('Unsupported original message identity');
    }
    return match[1]!;
  }

  Future<CareThread> authorize(OperationIdentity i) async {
    guard(i);
    final id = contract(i), seen = <String>{};
    String? after;
    for (int page = 0; page < 100; page++) {
      final raw = object(
        (await api.integrationResource(
          'messaging/threads',
          generation,
          query: {'limit': '100', 'after': ?after},
        )).data,
      );
      guard(i);
      final rows = raw['items'];
      if (rows is! List || rows.length > 100) {
        throw const FormatException('Invalid authorized thread page');
      }
      for (final value in rows) {
        final thread = CareThread.fromApi(object(value), i.owner, i.role);
        if (!seen.add(thread.id)) {
          throw const FormatException('Repeated thread page');
        }
        if (thread.id == id) {
          if (thread.grant != i.scope['access_id'] ||
              thread.patient != i.scope['patient_id'] ||
              thread.doctor != i.scope['doctor_id']) {
            throw RecoveryPermissionLost();
          }
          return thread;
        }
      }
      final next = raw['next_after'];
      if (next == null) throw RecoveryPermissionLost();
      resourceId(next);
      if (rows.isEmpty || next == after || (rows.last as Map)['id'] != next) {
        throw const FormatException('Invalid authorized thread cursor');
      }
      after = next as String;
    }
    throw const FormatException(
      'Original thread could not be verified within bounded pages',
    );
  }

  Never failure(IntegrationFailure e) {
    if ([403, 404, 409, 410].contains(e.status)) throw RecoveryPermissionLost();
    throw e;
  }

  @override
  Future<ReceiptEvidence> lookup(OperationIdentity i) async {
    guard(i);
    contract(i);
    try {
      final thread = await authorize(i);
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
        throw const FormatException('Invalid message attempt');
      }
      await authorize(i);
      if (status != 'committed') {
        if (raw['result'] != null) {
          throw const FormatException(
            'Unavailable message receipt contains content',
          );
        }
        return ReceiptEvidence(
          status == 'unknown' ? ReceiptOutcome.unknown : ReceiptOutcome.expired,
        );
      }
      final message = CareMessage.fromApi(object(raw['result']), thread);
      if (message.id != raw['attempt_id'] ||
          message.actor != i.owner ||
          i.scope['resource_id'] != null &&
              i.scope['resource_id'] != message.id) {
        throw const FormatException('Wrong original message result');
      }
      return ReceiptEvidence(
        ReceiptOutcome.committed,
        resource: message.id,
        revision: message.sequence,
      );
    } on IntegrationFailure catch (e) {
      failure(e);
    }
  }

  @override
  Future<bool> verifyCurrent(OperationIdentity i, ReceiptEvidence r) async {
    guard(i);
    contract(i);
    if (r.outcome != ReceiptOutcome.committed ||
        r.resource == null ||
        r.revision == null) {
      return false;
    }
    try {
      final thread = await authorize(i);
      if (thread.latest < r.revision!) return false;
      final raw = object(
        (await api.integrationResource(
          'messaging/threads/${thread.id}/messages',
          generation,
          query: {
            'after': '${r.revision! - 1}',
            'as_of': '${r.revision}',
            'limit': '1',
          },
        )).data,
      );
      guard(i);
      final page = MessagePage.fromApi(
        raw,
        thread,
        r.revision! - 1,
        r.revision,
      );
      await authorize(i);
      return page.messages.length == 1 &&
          page.messages.single.id == r.resource &&
          page.messages.single.sequence == r.revision &&
          page.messages.single.actor == i.owner;
    } on IntegrationFailure catch (e) {
      failure(e);
    }
  }
}
