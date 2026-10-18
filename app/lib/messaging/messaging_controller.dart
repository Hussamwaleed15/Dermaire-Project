import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../integration/private_view.dart';
import 'messaging_models.dart';

class ThreadsController extends PrivateController {
  ThreadsController({this.patient});
  final String? patient;
  final _threads = <CareThread>[];
  final _grants = <Map<String, dynamic>>[];
  String? next;
  List<CareThread> get threads => current ? List.unmodifiable(_threads) : [];
  List<Map<String, dynamic>> get grants =>
      current ? List.unmodifiable(_grants) : [];
  @override
  void wipe() {
    _threads.clear();
    _grants.clear();
    next = null;
  }

  @override
  Future<void> refresh() async => load();
  Future<void> load({bool more = false}) async {
    if (!current || busy || more && next == null) return;
    final after = more ? next : null, ticket = begin();
    if (!more) wipe();
    try {
      final data = object(
        (await api.integrationResource(
          'messaging/threads',
          generation,
          query: {'limit': '50', 'after': ?after},
        )).data,
      );
      final rows = (data['items'] as List)
          .map((v) => CareThread.fromApi(object(v), owner, role))
          .toList();
      final cursor = data['next_after'] == null
          ? null
          : resourceId(data['next_after']);
      if (cursor == after && cursor != null) {
        throw const FormatException('Repeated cursor');
      }
      if (!valid(ticket)) return;
      final ids = _threads.map((t) => t.id).toSet();
      if (rows.any((t) => !ids.add(t.id))) {
        throw const FormatException('Duplicate conversation');
      }
      _threads.addAll(
        rows.where((t) => patient == null || t.patient == patient),
      );
      next = cursor;
      if (role == 'patient' && !more) {
        final list =
            (await api.integrationResource('doctor/access', generation)).data
                as List;
        if (!valid(ticket)) return;
        for (final row in list) {
          final g = object(row);
          if (g['patient_id'] != owner || g['granted_by'] != owner) {
            throw const FormatException('Foreign grant');
          }
          if (g['status'] == 'active' &&
              DateTime.parse(
                g['expires_at'] as String,
              ).isAfter(DateTime.now().toUtc()) &&
              g['doctor_id'] is String &&
              (g['scopes'] as List?)?.contains('VIEW') == true) {
            _grants.add(Map.unmodifiable(g));
          }
        }
      }
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<CareThread?> enroll(String grant) async {
    if (!current ||
        busy ||
        role != 'patient' ||
        !_grants.any((g) => g['id'] == grant)) {
      return null;
    }
    final ticket = begin();
    try {
      final row = CareThread.fromApi(
        object(
          (await api.integrationResource(
            'messaging/threads',
            generation,
            method: 'POST',
            body: {'access_id': resourceId(grant), 'messaging_consent': true},
          )).data,
        ),
        owner,
        role,
      );
      if (!valid(ticket) || row.grant != grant) return null;
      return row;
    } catch (failure) {
      if (valid(ticket)) {
        error =
            'Enrollment is unconfirmed. Refresh conversations before repeating consent. ${integrationError(failure)}';
      }
      return null;
    } finally {
      finish(ticket);
    }
  }
}

class ConversationController extends PrivateController {
  ConversationController(this.thread);
  final CareThread thread;
  @override
  bool get current =>
      super.current &&
      (role == 'patient' ? thread.patient == owner : thread.doctor == owner);
  final _messages = <CareMessage>[];
  int high = 0, patientRead = 0, doctorRead = 0;
  bool complete = false;
  String? outcome;
  String get intentId => 'message:${thread.id}';
  PendingIntent? get pending =>
      authenticatedCurrent ? api.integrationIntents[intentId] : null;
  List<CareMessage> get messages => current ? List.unmodifiable(_messages) : [];
  bool get hasEarlier =>
      current &&
      _messages.isNotEmpty &&
      _messages.first.sequence > 1 &&
      _messages.length < 500;
  @override
  void wipe() {
    _messages.clear();
    high = patientRead = doctorRead = 0;
    complete = false;
    outcome = null;
  }

  Future<MessagePage> page(int after, {int? asOf}) async => MessagePage.fromApi(
    object(
      (await api.integrationResource(
        'messaging/threads/${thread.id}/messages',
        generation,
        query: {
          'after': '$after',
          'limit': '50',
          if (asOf != null) 'as_of': '$asOf',
        },
      )).data,
    ),
    thread,
    after,
    asOf,
  );
  Future<MessagePage> latest() async {
    final first = await page(0);
    if (!current) return first;
    return first.high <= 50 ? first : page(first.high - 50, asOf: first.high);
  }

  void apply(MessagePage value) {
    _messages
      ..clear()
      ..addAll(value.messages);
    high = value.high;
    patientRead = value.patientRead;
    doctorRead = value.doctorRead;
    complete = true;
  }

  @override
  Future<void> refresh() async {
    if (!current || busy) return;
    final ticket = begin();
    wipe();
    try {
      final value = await latest();
      if (valid(ticket)) apply(value);
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<void> earlier() async {
    if (!hasEarlier || busy) return;
    final ticket = begin();
    final after = (_messages.first.sequence - 51).clamp(0, high);
    try {
      final value = await page(after, asOf: high);
      if (!valid(ticket)) return;
      final sequence = {for (final m in _messages) m.sequence: m};
      for (final m in value.messages) {
        if (sequence[m.sequence] != null && sequence[m.sequence]!.id != m.id) {
          throw const FormatException('History changed');
        }
        sequence[m.sequence] = m;
      }
      _messages
        ..clear()
        ..addAll(
          sequence.values.toList()
            ..sort((a, b) => a.sequence.compareTo(b.sequence)),
        );
      patientRead = value.patientRead;
      doctorRead = value.doctorRead;
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> send(String body) async {
    if (!current ||
        busy ||
        !complete ||
        body.trim().isEmpty ||
        body.trim().length > 4000 ||
        pending != null) {
      return false;
    }
    final intent = PendingIntent(
      path: 'messaging/threads/${thread.id}/messages',
      attemptPath: 'messaging/threads/${thread.id}/attempts',
      body: {'body': body.trim()},
      identityScope: {
        'access_id': thread.grant,
        'patient_id': thread.patient,
        'doctor_id': thread.doctor,
      },
    );
    api.integrationIntents[intentId] = intent;
    return deliver(intent);
  }

  Future<bool> reconcile({bool retryOriginal = false}) async {
    final intent = pending;
    if (intent == null || !current || busy) return false;
    final ticket = begin();
    try {
      final data = object(
        (await api.integrationResource(
          '${intent.attemptPath}/${intent.key}',
          generation,
        )).data,
      );
      if (!valid(ticket)) return false;
      if (data['status'] == 'committed') {
        if (data['attempt_id'] != object(data['result'])['id']) {
          throw const FormatException('Unverified attempt identity');
        }
        return await confirm(object(data['result']), intent, ticket);
      }
      if (!['unknown', 'expired'].contains(data['status'])) {
        throw const FormatException('Unverified attempt');
      }
      error = data['status'] == 'expired'
          ? 'The send receipt expired. Review conversation history; do not send a replacement automatically.'
          : 'The send is still unknown. You may explicitly retry the original body and key.';
      if (data['status'] == 'unknown' && retryOriginal) {
        busy = false;
        return deliver(intent);
      }
      return false;
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  Future<bool> deliver(PendingIntent intent) async {
    if (!current || busy) return false;
    final ticket = begin();
    bool sent = false, acknowledged = false;
    final wasUncertain = intent.uncertain;
    try {
      await page(0);
      if (!valid(ticket)) return false;
      sent = true;
      intent.uncertain = true;
      final result = await api.integrationResource(
        intent.path,
        generation,
        method: 'POST',
        body: intent.body,
        key: intent.key,
      );
      acknowledged = true;
      if (!valid(ticket)) return false;
      final receipt = object(result.data);
      if (result.headers['operation-attempt-id'] != receipt['id']) {
        throw const FormatException('Missing send receipt');
      }
      return await confirm(receipt, intent, ticket);
    } catch (failure) {
      if (!authenticatedCurrent) return false;
      if (sent &&
          !wasUncertain &&
          !acknowledged &&
          failure is IntegrationFailure &&
          [403, 404, 422].contains(failure.status)) {
        api.integrationIntents.remove(intentId);
      }
      if (valid(ticket)) {
        wipe();
        error = sent
            ? 'Send outcome is not confirmed. Resolve the original send before composing another. ${integrationError(failure)}'
            : integrationError(failure);
      }
      return false;
    } finally {
      finish(ticket);
    }
  }

  Future<bool> confirm(
    Map<String, dynamic> data,
    PendingIntent intent,
    int ticket,
  ) async {
    final receipt = CareMessage.fromApi(data, thread);
    if (receipt.actor != owner || receipt.body != intent.body['body']) {
      throw const FormatException('Unverified send receipt');
    }
    final currentPage = await latest();
    if (!valid(ticket)) return false;
    if (currentPage.high < receipt.sequence) {
      throw const FormatException('Send not in current history');
    }
    apply(currentPage);
    api.integrationIntents.remove(intentId);
    outcome =
        'Message saved on the server · sequence ${receipt.sequence}. Delivery is not confirmed.';
    return true;
  }

  Future<void> markRead() async {
    if (!current || busy || _messages.isEmpty) return;
    final through = _messages.last.sequence, ticket = begin();
    try {
      final row = CareThread.fromApi(
        object(
          (await api.integrationResource(
            'messaging/threads/${thread.id}/read',
            generation,
            method: 'PUT',
            body: {'through_sequence': through},
          )).data,
        ),
        owner,
        role,
      );
      if (!valid(ticket) || row.id != thread.id || row.grant != thread.grant) {
        throw const FormatException('Unverified read acknowledgment');
      }
      patientRead = row.patientRead;
      doctorRead = row.doctorRead;
    } catch (failure) {
      if (valid(ticket)) {
        wipe();
        error = integrationError(failure);
      }
    } finally {
      finish(ticket);
    }
  }

  Future<bool> withdraw() async {
    if (!authenticatedCurrent ||
        busy ||
        role != 'patient' ||
        thread.patient != owner) {
      return false;
    }
    final ticket = begin();
    try {
      final data = object(
        (await api.integrationResource(
          'messaging/threads/${thread.id}/consent',
          generation,
          method: 'DELETE',
          withdrawal: true,
        )).data,
      );
      if (!authenticatedCurrent ||
          ticket != revision ||
          data['id'] != thread.id ||
          data['status'] != 'closed') {
        return false;
      }
      api.integrationIntents.remove(intentId);
      wipe();
      error = 'Messaging consent withdrawn. This conversation is closed.';
      return true;
    } catch (failure) {
      if (valid(ticket)) error = integrationError(failure);
      return false;
    } finally {
      finish(ticket);
    }
  }
}
