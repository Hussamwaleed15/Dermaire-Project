import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/request_failure.dart';
import '../clinical/clinical_models.dart' show text;
import 'doctor_controller.dart';
import 'doctor_models.dart';

/// One immutable doctor session + selected patient. Every open/refresh rechecks
/// the backend-authorized detail and never promotes a cached list to permission.
class DoctorConnectionController extends ChangeNotifier {
  DoctorConnectionController(this.parent, this.patientId) {
    selection = parent.selectPatient(patientId);
    parent.addListener(_parentChanged);
  }
  final DoctorWorkspaceController parent;
  final String patientId;
  late final int selection;
  Map<String, dynamic>? _record;
  DoctorGrant? _grant;
  bool loading = false, _disposed = false;
  String? error;
  int _revision = 0;
  Timer? _expiry;
  bool get current =>
      !_disposed &&
      parent.allows(patientId) &&
      parent.activePatient == patientId &&
      parent.selectionRevision == selection;
  bool get confirmed =>
      current &&
      _grant?.active(DateTime.now().toUtc()) == true &&
      _record != null &&
      !loading;
  Map<String, dynamic>? get record => confirmed ? _record : null;
  DoctorGrant? get grant => confirmed ? _grant : null;
  void _parentChanged() {
    if (!current) invalidate();
  }

  void invalidate() {
    if (_disposed) return;
    _revision++;
    _expiry?.cancel();
    _record = null;
    _grant = null;
    loading = false;
    error = 'Patient authorization changed. Return and refresh connections.';
    notifyListeners();
  }

  Future<bool> refresh() async {
    if (!current || loading || parent.saving) return false;
    final revision = ++_revision;
    loading = true;
    error = null;
    _record = null;
    _grant = null;
    notifyListeners();
    try {
      final data =
          await parent.api.doctorResource(
                'patients/${doctorId(patientId)}',
                parent.generation,
              )
              as Map<String, dynamic>;
      if (data['patient_id'] != patientId) {
        throw const FormatException('Wrong patient detail');
      }
      text(data['full_name']);
      final grant = DoctorGrant.fromApi(
        data['access'] as Map<String, dynamic>,
        patient: patientId,
        doctor: parent.session.userId,
      );
      if (!current || revision != _revision) return false;
      if (!grant.active(DateTime.now().toUtc())) {
        parent.forgetPatient(patientId);
        return false;
      }
      _grant = grant;
      _record = Map.unmodifiable(data);
      _expiry?.cancel();
      _expiry = Timer(
        grant.expiresAt.difference(DateTime.now().toUtc()),
        invalidate,
      );
    } catch (failure) {
      if (_disposed || revision != _revision) return false;
      _record = null;
      _grant = null;
      error = RequestFailure.from(failure).message;
      if (failure is RequestFailure &&
          [
            RequestFailureKind.denied,
            RequestFailureKind.rejected,
          ].contains(failure.kind)) {
        parent.forgetPatient(patientId);
      }
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        notifyListeners();
      }
    }
    return confirmed;
  }

  Future<bool> verifyForRead() async {
    if (!confirmed) return false;
    try {
      final data =
          await parent.api.doctorResource(
                'patients/${doctorId(patientId)}',
                parent.generation,
              )
              as Map<String, dynamic>;
      if (!confirmed) return false;
      final active = DoctorGrant.fromApi(
        data['access'] as Map<String, dynamic>,
        patient: patientId,
        doctor: parent.session.userId,
      );
      if (data['patient_id'] != patientId ||
          !active.active(DateTime.now().toUtc()) ||
          active.id != _grant?.id) {
        invalidate();
        return false;
      }
      return confirmed;
    } catch (_) {
      if (current) invalidate();
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _expiry?.cancel();
    parent.removeListener(_parentChanged);
    _record = null;
    _grant = null;
    super.dispose();
  }
}
