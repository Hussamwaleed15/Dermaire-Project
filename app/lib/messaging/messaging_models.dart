import '../clinical/clinical_models.dart';
import '../integration/contract.dart';

class CareThread {
  CareThread.fromApi(Map<String, dynamic> value, String owner, String role)
    : id = resourceId(value['id']),
      patient = resourceId(value['patient_id']),
      doctor = resourceId(value['doctor_id']),
      grant = resourceId(value['access_id']),
      createdAt = timestamp(value['created_at']),
      latest = count(value['latest_sequence']),
      patientRead = count(value['patient_read']),
      doctorRead = count(value['doctor_read']) {
    if ((role == 'patient' ? patient : doctor) != owner ||
        patient == doctor ||
        value['closed_at'] != null ||
        value['emergency_service'] != false ||
        patientRead > latest ||
        doctorRead > latest) {
      throw const FormatException('Unverified conversation');
    }
  }
  final String id, patient, doctor, grant;
  final DateTime createdAt;
  final int latest, patientRead, doctorRead;
}

class CareMessage {
  CareMessage.fromApi(Map<String, dynamic> value, CareThread thread)
    : id = resourceId(value['id']),
      actor = resourceId(value['actor_id']),
      sequence = count(value['sequence']),
      body = text(value['body']),
      createdAt = timestamp(value['created_at']) {
    if (value['thread_id'] != thread.id ||
        ![thread.patient, thread.doctor].contains(actor) ||
        sequence < 1 ||
        body.length > 4000 ||
        value['provenance'] != 'participant_authored' ||
        value['clinical_clearance'] != false) {
      throw const FormatException('Unverified message');
    }
  }
  final String id, actor, body;
  final int sequence;
  final DateTime createdAt;
}

class MessagePage {
  MessagePage.fromApi(
    Map<String, dynamic> value,
    CareThread thread,
    int after,
    int? expectedHigh,
  ) : high = count(value['as_of_sequence']),
      next = value['next_after'] as int?,
      patientRead = count(value['patient_read']),
      doctorRead = count(value['doctor_read']),
      messages = (value['items'] as List)
          .map((v) => CareMessage.fromApi(object(v), thread))
          .toList() {
    if ((expectedHigh != null && high != expectedHigh) ||
        messages.length > 50 ||
        messages.any((m) => m.sequence <= after || m.sequence > high) ||
        messages.map((m) => m.sequence).toSet().length != messages.length ||
        (next != null &&
            (messages.isEmpty ||
                next != messages.last.sequence ||
                next! >= high))) {
      throw const FormatException('Invalid message page');
    }
    for (int i = 1; i < messages.length; i++) {
      if (messages[i - 1].sequence >= messages[i].sequence) {
        throw const FormatException('Unordered messages');
      }
    }
  }
  final int high, patientRead, doctorRead;
  final int? next;
  final List<CareMessage> messages;
}
