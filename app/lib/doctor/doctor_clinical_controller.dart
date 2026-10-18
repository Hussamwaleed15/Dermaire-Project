import 'package:flutter/foundation.dart';
import '../services/request_failure.dart';
import '../routine/routine_controller.dart' show RoutineController;
import 'doctor_connection.dart';
import 'doctor_evidence_models.dart';
import 'doctor_models.dart';

/// A selected-patient editor/read model. Immutable writes are never replayed.
class DoctorClinicalController extends ChangeNotifier {
  DoctorClinicalController(this.connection) {
    connection.addListener(_accessChanged);
  }
  final DoctorConnectionController connection;
  final List<DoctorNote> _notes = [];
  DoctorReviewRead? _review;
  bool loading = false, saving = false, _disposed = false;
  String? error, outcome;
  int _revision = 0;
  bool get current => !_disposed && connection.confirmed;
  bool get confirmed => current && _review != null && !loading && error == null;
  List<DoctorNote> get notes => confirmed ? List.unmodifiable(_notes) : [];
  DoctorReviewRead? get review => confirmed ? _review : null;
  String key(String kind) => '${connection.patientId}:$kind';
  bool uncertain(String kind) =>
      connection.parent.api.uncertainDoctorWrites.contains(key(kind));
  void _accessChanged() {
    if (!current) clear();
  }

  void clear() {
    if (_disposed) return;
    _revision++;
    _notes.clear();
    _review = null;
    loading = saving = false;
    error = outcome = null;
    notifyListeners();
  }

  Future<DoctorReviewRead> _readReview() async => DoctorReviewRead.fromApi(
    await connection.parent.api.doctorResource(
          'patients/${connection.patientId}/reviews',
          connection.parent.generation,
        )
        as Map<String, dynamic>,
    connection.patientId,
  );
  Future<List<DoctorNote>> _readNotes() async {
    final result =
        (await connection.parent.api.doctorResource(
                  'patients/${connection.patientId}/notes',
                  connection.parent.generation,
                )
                as List)
            .map(
              (v) => DoctorNote.fromApi(
                v as Map<String, dynamic>,
                connection.patientId,
              ),
            )
            .toList();
    if (result.map((n) => n.id).toSet().length != result.length) {
      throw const FormatException('Duplicate note');
    }
    return result;
  }

  static bool sameDecision(Map<String, dynamic> a, Map<String, dynamic> b) =>
      RoutineController.sameWire(
        {
          for (final k in [
            'id',
            'sequence',
            'patient_id',
            'doctor_id',
            'access_id',
            'state',
            'recommendation',
            'rationale',
            'patient_visible',
            'created_at',
            'provenance',
            'safety_at_review',
          ])
            k: a[k],
        },
        {
          for (final k in [
            'id',
            'sequence',
            'patient_id',
            'doctor_id',
            'access_id',
            'state',
            'recommendation',
            'rationale',
            'patient_visible',
            'created_at',
            'provenance',
            'safety_at_review',
          ])
            k: b[k],
        },
      );
  void _reconcile(List<DoctorNote> notes, DoctorReviewRead review) {
    final api = connection.parent.api;
    for (final kind in ['notes', 'reviews']) {
      final receipt = api.pendingDoctorReceipts[key(kind)];
      if (receipt == null ||
          receipt['doctor_id'] != connection.parent.session.userId ||
          receipt['patient_id'] != connection.patientId) {
        continue;
      }
      final found = kind == 'notes'
          ? notes.any(
              (n) =>
                  n.id == receipt['id'] &&
                  RoutineController.sameWire(n.wire, receipt),
            )
          : review.history.any(
              (r) => r.id == receipt['id'] && sameDecision(r.wire, receipt),
            );
      if (found) {
        api.pendingDoctorReceipts.remove(key(kind));
        api.uncertainDoctorWrites.remove(key(kind));
        api.integrationIntents.remove(
          'legacy:doctor:patients/${connection.patientId}/$kind',
        );
      }
    }
  }

  Future<bool> refresh() async {
    if (!current || loading || saving) return false;
    final revision = ++_revision;
    loading = true;
    error = outcome = null;
    _notes.clear();
    _review = null;
    notifyListeners();
    try {
      if (!await connection.verifyForRead()) return false;
      final notes = await _readNotes();
      if (!current || revision != _revision) return false;
      final review = await _readReview();
      if (!current || revision != _revision) return false;
      _notes.addAll(notes);
      _review = review;
      _reconcile(notes, review);
    } catch (failure) {
      if (!current || revision != _revision) return false;
      error = RequestFailure.from(failure).message;
      if (failure is RequestFailure &&
          [
            RequestFailureKind.denied,
            RequestFailureKind.rejected,
          ].contains(failure.kind)) {
        connection.invalidate();
      }
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
    return confirmed;
  }

  String? validateNote(
    String content,
    String priority,
    String? followUp,
    String? category,
  ) {
    if (content.trim().length < 10 || content.trim().length > 1500) {
      return 'Use 10–1500 characters of clinical context.';
    }
    if (!['routine', 'review', 'urgent'].contains(priority)) {
      return 'Choose a supported priority.';
    }
    if (followUp != null && followUp.trim().length > 100) {
      return 'Follow-up guidance is limited to 100 characters.';
    }
    if (category != null &&
        (category.trim().isEmpty || category.trim().length > 50)) {
      return 'Category must have 1–50 characters.';
    }
    return null;
  }

  String? validateReview(
    String state,
    String? recommendation,
    String? rationale,
  ) {
    if (![
      'pending',
      'in_review',
      'reviewed',
      'follow_up_needed',
    ].contains(state)) {
      return 'Choose a supported review state.';
    }
    if (recommendation != null &&
        ![
          'track',
          'low_risk_self_care',
          'doctor_review',
          'urgent',
        ].contains(recommendation)) {
      return 'Choose a supported recommendation.';
    }
    if ((recommendation != null && rationale == null) ||
        (rationale != null &&
            (rationale.trim().length < 10 || rationale.trim().length > 1500))) {
      return 'A recommendation needs 10–1500 characters of rationale.';
    }
    return null;
  }

  Future<bool> addNote({
    required String content,
    String priority = 'routine',
    bool visible = false,
    String? followUp,
    String? category,
  }) async {
    if (validateNote(content, priority, followUp, category) != null) {
      return false;
    }
    final payload = <String, dynamic>{
      'content': content.trim(),
      'priority': priority,
      'patient_visible': visible,
      'follow_up': followUp?.trim(),
      'category': category?.trim(),
    };
    return _write('notes', payload, null);
  }

  Future<bool> recordReview({
    required String state,
    required int expectedSequence,
    String? recommendation,
    String? rationale,
    bool visible = false,
  }) async {
    if (validateReview(state, recommendation, rationale) != null ||
        expectedSequence < 0) {
      return false;
    }
    return _write('reviews', {
      'state': state,
      'recommendation': recommendation,
      'rationale': rationale?.trim(),
      'patient_visible': visible,
      'expected_sequence': expectedSequence,
    }, expectedSequence);
  }

  Future<bool> _write(
    String kind,
    Map<String, dynamic> payload,
    int? expectedSequence,
  ) async {
    final api = connection.parent.api,
        generation = connection.parent.generation,
        operation = key(kind);
    if (!confirmed ||
        saving ||
        uncertain(kind) ||
        api.inFlightDoctorWrites.isNotEmpty ||
        connection.parent.saving) {
      return false;
    }
    final revision = _revision, grantId = connection.grant!.id;
    bool active() => current && revision == _revision;
    api.inFlightDoctorWrites.add(operation);
    saving = true;
    error = outcome = null;
    notifyListeners();
    bool sent = false, acknowledged = false;
    try {
      if (!await connection.verifyForRead() || !active()) return false;
      if (kind == 'reviews') {
        final latest = await _readReview();
        if (!active()) return false;
        if (latest.sequence != expectedSequence) {
          _review = null;
          _notes.clear();
          error =
              'Review changed elsewhere. Refresh and reconsider the current record before submitting.';
          return false;
        }
      }
      if (!active() || connection.grant?.id != grantId) return false;
      sent = true;
      final raw =
          await api.doctorResource(
                'patients/${connection.patientId}/$kind',
                generation,
                method: 'POST',
                payload: payload,
                identityScope: {
                  'access_id': grantId,
                  'patient_id': connection.patientId,
                  'doctor_id': connection.parent.session.userId,
                },
              )
              as Map<String, dynamic>;
      acknowledged = true;
      if (kind == 'notes') {
        final receipt = DoctorNote.fromApi(raw, connection.patientId);
        if (receipt.doctor != connection.parent.session.userId ||
            payload.entries.any((e) => raw[e.key] != e.value)) {
          throw const FormatException('Unverified note receipt');
        }
      } else {
        final receipt = DoctorDecision.fromApi(raw, connection.patientId);
        if (receipt.doctor != connection.parent.session.userId ||
            receipt.accessId != grantId ||
            receipt.sequence != expectedSequence! + 1 ||
            payload.entries
                .where((e) => e.key != 'expected_sequence')
                .any((e) => raw[e.key] != e.value)) {
          throw const FormatException('Unverified review receipt');
        }
      }
      if (!api.isCurrentSession(generation)) return false;
      api.pendingDoctorReceipts[operation] = Map.unmodifiable(raw);
      // A receipt is retained only for GET reconciliation, never a second POST.
      if (!active()) {
        api.uncertainDoctorWrites.add(operation);
        return false;
      }
      final notes = await _readNotes();
      if (!active()) {
        if (api.isCurrentSession(generation)) {
          api.uncertainDoctorWrites.add(operation);
        }
        return false;
      }
      final read = await _readReview();
      final match = kind == 'notes'
          ? notes.any(
              (n) =>
                  n.id == raw['id'] && RoutineController.sameWire(n.wire, raw),
            )
          : read.history.any(
              (r) => r.id == raw['id'] && sameDecision(r.wire, raw),
            );
      if (!match) throw const FormatException('Unverified readback');
      if (!active()) {
        if (api.isCurrentSession(generation)) {
          api.uncertainDoctorWrites.add(operation);
        }
        return false;
      }
      _notes
        ..clear()
        ..addAll(notes);
      _review = read;
      _reconcile(notes, read);
      outcome = kind == 'reviews' && read.sequence > raw['sequence']
          ? 'Review recorded and confirmed in history; a newer review is current.'
          : 'Clinical record confirmed by server readback.';
      return true;
    } catch (failure) {
      if (!api.isCurrentSession(generation)) return false;
      final rejected =
          !acknowledged &&
          failure is RequestFailure &&
          [
            RequestFailureKind.denied,
            RequestFailureKind.rejected,
          ].contains(failure.kind);
      if (sent && !rejected) api.uncertainDoctorWrites.add(operation);
      if (!active()) return false;
      _notes.clear();
      _review = null;
      error = rejected
          ? 'The change was rejected or the review changed. Refresh before reconsidering it.'
          : sent
          ? 'Outcome is unconfirmed. Refresh records; do not resend this change.'
          : 'Patient access could not be verified. Return and refresh access.';
      if (failure is RequestFailure &&
          failure.kind == RequestFailureKind.denied) {
        connection.invalidate();
      }
      return false;
    } finally {
      if (api.isCurrentSession(generation)) {
        api.inFlightDoctorWrites.remove(operation);
      }
      if (!_disposed && revision == _revision) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    connection.removeListener(_accessChanged);
    _notes.clear();
    _review = null;
    super.dispose();
  }
}
