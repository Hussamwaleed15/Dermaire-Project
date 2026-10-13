import 'dart:async';
import 'package:flutter/foundation.dart';
import '../access_control.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import '../routine/routine_controller.dart' show RoutineController;
import 'doctor_models.dart';

class DoctorWorkspaceController extends ChangeNotifier {
  DoctorWorkspaceController(
    this.session, {
    List<Map<String, dynamic>> patientData = const [],
  }) : generation = ApiService.instance.sessionGeneration {
    api.addListener(_sessionChanged);
    // Constructor data and local AccessSession IDs never establish authority.
  }
  final api = ApiService.instance;
  final AccessSession session;
  final int generation;
  bool _disposed = false;
  int _revision = 0;
  Timer? _grantTimer;
  bool loading = false, saving = false;
  String? error;
  String? errorPatient;
  String? activePatient;
  int selectionRevision = 0;
  int selectPatient(String id) {
    selectionRevision++;
    activePatient = allows(id) ? id : null;
    notifyListeners();
    return selectionRevision;
  }

  DateTime? retrievedAt;
  String query = '';
  PatientPriority? filter;
  final notes = <String, List<String>>{};
  final audit = <String, List<ClinicalAuditEvent>>{};
  final List<DoctorPatient> patients = [];
  bool get authenticatedCurrent =>
      !_disposed &&
      api.isCurrentSession(generation) &&
      api.authenticatedRole == 'doctor' &&
      api.authenticatedOwner == session.userId &&
      session.role == UserRole.doctor &&
      !session.isExpired;
  bool get current =>
      !_disposed &&
      api.isCurrentSession(generation) &&
      api.canReadDoctorWorkspace &&
      api.doctorOwner == session.userId &&
      session.role == UserRole.doctor &&
      !session.isExpired;
  bool allows(String id) =>
      current &&
      !loading &&
      patients.any((p) => p.id == id && p.available(DateTime.now().toUtc()));
  List<DoctorPatient> get visible => !current
      ? []
      : patients
            .where(
              (p) =>
                  p.available(DateTime.now().toUtc()) &&
                  (filter == null || p.priority == filter) &&
                  p.name.toLowerCase().contains(query.trim().toLowerCase()),
            )
            .toList();
  void _sessionChanged() {
    if (!current) clear();
  }

  void clear() {
    if (_disposed) return;
    _revision++;
    _grantTimer?.cancel();
    patients.clear();
    notes.clear();
    audit.clear();
    query = '';
    filter = null;
    retrievedAt = null;
    loading = saving = false;
    error = 'Doctor session or authorization ended. Sign in again.';
    notifyListeners();
  }

  void forgetPatient(String id) {
    if (_disposed) return;
    patients.removeWhere((p) => p.id == id);
    notes.remove(id);
    audit.remove(id);
    error =
        'Patient access could not be confirmed. Refresh current connections.';
    notifyListeners();
  }

  void search(String value) {
    if (!current) return;
    query = value;
    notifyListeners();
  }

  void setFilter(PatientPriority? value) {
    if (!current) return;
    filter = value;
    notifyListeners();
  }

  Future<bool> refresh() async {
    if (!authenticatedCurrent || loading || saving) return false;
    final revision = ++_revision;
    loading = true;
    error = null;
    patients.clear();
    notes.clear();
    retrievedAt = null;
    notifyListeners();
    try {
      await api.readSafetyAcceptance();
      if (!current || revision != _revision) {
        if (revision == _revision) {
          error =
              'Doctor role and safety acceptance could not be verified. Sign in again or retry.';
        }
        return false;
      }
      final data = (await api.doctorResource('patients', generation) as List)
          .cast<Map<String, dynamic>>();
      final rows = data
          .map((v) => DoctorPatient.fromApi(v, session.userId))
          .toList();
      if (rows.map((p) => p.id).toSet().length != rows.length) {
        throw const FormatException('Duplicate patient');
      }
      final parsed = <String, List<String>>{};
      for (final row in data) {
        final id = row['patient_id'] as String;
        parsed[id] = (row['notes'] as List)
            .map(
              (v) => DoctorNote.fromApi(v as Map<String, dynamic>, id).content,
            )
            .toList();
      }
      if (!current || revision != _revision) return false;
      patients.addAll(rows.where((p) => p.available(DateTime.now().toUtc())));
      for (final patient in patients) {
        notes[patient.id] = parsed[patient.id]!;
      }
      retrievedAt = DateTime.now().toUtc();
      _grantTimer?.cancel();
      final deadlines =
          patients
              .expand((p) => p.grants)
              .where((g) => g.active(DateTime.now().toUtc()))
              .map((g) => g.expiresAt)
              .toList()
            ..sort();
      if (deadlines.isNotEmpty) {
        _grantTimer = Timer(
          deadlines.first.difference(DateTime.now().toUtc()),
          () {
            if (!current) return;
            patients.clear();
            notes.clear();
            audit.clear();
            retrievedAt = null;
            error =
                'Access changed or expired. Refresh to verify current connections.';
            notifyListeners();
          },
        );
      }
    } catch (failure) {
      if (_disposed || revision != _revision) return false;
      patients.clear();
      notes.clear();
      audit.clear();
      error = RequestFailure.from(failure).message;
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
    return current && error == null;
  }

  String? validateNote(String value) {
    final cleaned = value.trim();
    if (cleaned.length < 10) {
      return 'Add at least 10 characters of clinical context';
    }
    if (cleaned.length > 1500) return 'Keep the note under 1500 characters';
    return null;
  }

  Future<bool> addNote(DoctorPatient patient, String value) async {
    final key = '${patient.id}:notes';
    if (!allows(patient.id) ||
        saving ||
        api.inFlightDoctorWrites.isNotEmpty ||
        (activePatient != null && activePatient != patient.id) ||
        patient.fileClosed ||
        validateNote(value) != null ||
        api.uncertainDoctorWrites.contains(key)) {
      return false;
    }
    final revision = _revision, selection = selectionRevision;
    api.inFlightDoctorWrites.add(key);
    saving = true;
    errorPatient = patient.id;
    error = null;
    notifyListeners();
    bool sent = false, acknowledged = false;
    try {
      final detail =
          await api.doctorResource(
                'patients/${doctorId(patient.id)}',
                generation,
              )
              as Map<String, dynamic>;
      final grant = DoctorGrant.fromApi(
        detail['access'] as Map<String, dynamic>,
        patient: patient.id,
        doctor: session.userId,
      );
      if (detail['patient_id'] != patient.id ||
          !grant.active(DateTime.now().toUtc()) ||
          !current ||
          revision != _revision ||
          selection != selectionRevision) {
        return false;
      }
      sent = true;
      final receipt = DoctorNote.fromApi(
        await api.doctorResource(
              'patients/${patient.id}/notes',
              generation,
              method: 'POST',
              payload: {
                'content': value.trim(),
                'priority': 'routine',
                'follow_up': null,
              },
            )
            as Map<String, dynamic>,
        patient.id,
      );
      acknowledged = true;
      if (receipt.doctor != session.userId ||
          receipt.content != value.trim() ||
          receipt.priority != 'routine' ||
          receipt.visible ||
          receipt.followUp != null) {
        throw const FormatException('Unconfirmed note');
      }
      if (selection != selectionRevision) {
        if (api.isCurrentSession(generation)) {
          api.uncertainDoctorWrites.add(key);
        }
        return false;
      }
      final rows =
          (await api.doctorResource('patients/${patient.id}/notes', generation)
                  as List)
              .map(
                (v) =>
                    DoctorNote.fromApi(v as Map<String, dynamic>, patient.id),
              )
              .toList();
      final match = rows.where((n) => n.id == receipt.id).firstOrNull;
      if (match == null ||
          !RoutineController.sameWire(match.wire, receipt.wire)) {
        throw const FormatException('Missing note readback');
      }
      if (!current ||
          revision != _revision ||
          selection != selectionRevision ||
          !allows(patient.id)) {
        if (api.isCurrentSession(generation)) {
          api.uncertainDoctorWrites.add(key);
        }
        return false;
      }
      notes[patient.id] = rows.map((n) => n.content).toList();
      audit
          .putIfAbsent(patient.id, () => [])
          .add(
            ClinicalAuditEvent(
              'Clinical note confirmed by server',
              receipt.createdAt,
            ),
          );
      return true;
    } catch (failure) {
      if (!current || revision != _revision) return false;
      final rejected =
          !acknowledged &&
          failure is RequestFailure &&
          [
            RequestFailureKind.denied,
            RequestFailureKind.rejected,
          ].contains(failure.kind);
      if (sent && !rejected) api.uncertainDoctorWrites.add(key);
      if (failure is RequestFailure &&
          failure.kind == RequestFailureKind.denied) {
        patients.clear();
        notes.clear();
        audit.clear();
      }
      error = rejected
          ? 'The clinical change was rejected. Refresh connections before continuing.'
          : sent
          ? 'Clinical change is not confirmed. Refresh records; do not resend an uncertain change.'
          : 'Patient access could not be verified. Refresh connections before writing.';
      return false;
    } finally {
      if (api.isCurrentSession(generation)) {
        api.inFlightDoctorWrites.remove(key);
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
    _grantTimer?.cancel();
    api.removeListener(_sessionChanged);
    patients.clear();
    notes.clear();
    audit.clear();
    super.dispose();
  }
}
