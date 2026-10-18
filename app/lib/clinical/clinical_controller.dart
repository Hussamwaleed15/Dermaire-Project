import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'clinical_models.dart';

enum ClinicalPhase { empty, loading, ready, failed }

@immutable
class ClinicalRead<T> {
  const ClinicalRead({
    this.phase = ClinicalPhase.empty,
    this.value,
    this.retrievedAt,
    this.error,
    this.stale = false,
  });
  final ClinicalPhase phase;
  final T? value;
  final DateTime? retrievedAt;
  final String? error;
  final bool stale;
  ClinicalRead<T> waiting() => ClinicalRead(
    phase: ClinicalPhase.loading,
    value: value,
    retrievedAt: retrievedAt,
    stale: value != null,
  );
  ClinicalRead<T> outdated() => ClinicalRead(
    phase: phase == ClinicalPhase.loading
        ? (value == null ? ClinicalPhase.empty : ClinicalPhase.ready)
        : phase,
    value: value,
    retrievedAt: retrievedAt,
    error: error,
    stale: value != null,
  );
}

abstract interface class ClinicalRepository {
  Future<SafetyAssessment> readSafety(int generation);
  Future<ClinicianReview> readReview(int generation);
}

class RemoteClinicalRepository implements ClinicalRepository {
  RemoteClinicalRepository(this.api);
  final ApiService api;
  @override
  Future<SafetyAssessment> readSafety(int generation) =>
      api.getPatientSafety(generation: generation);
  @override
  Future<ClinicianReview> readReview(int generation) =>
      api.getPatientClinicalReview(generation: generation);
}

/// In-memory only. Each independent resource exposes failures and stale reads.
/// Request revision plus authenticated session generation protect every result.
class ClinicalController extends ChangeNotifier {
  ClinicalController(this.api, {ClinicalRepository? repository})
    : repository = repository ?? RemoteClinicalRepository(api) {
    api.addListener(clear);
  }
  final ApiService api;
  final ClinicalRepository repository;
  ClinicalRead<SafetyAssessment> _safety = const ClinicalRead();
  ClinicalRead<ClinicianReview> _review = const ClinicalRead();
  int _revision = 0;
  int? _session;
  bool _disposed = false;
  bool get allowed => !_disposed && api.canReadPatientClinicalStatus;
  bool get _current => allowed && api.isCurrentSession(_session ?? -1);
  ClinicalRead<SafetyAssessment> get safety =>
      _current ? _safety : const ClinicalRead();
  ClinicalRead<ClinicianReview> get review =>
      _current ? _review : const ClinicalRead();
  bool get loading =>
      safety.phase == ClinicalPhase.loading ||
      review.phase == ClinicalPhase.loading;

  Future<bool> refresh({int? expectedGeneration}) async {
    if (!allowed ||
        (expectedGeneration != null &&
            expectedGeneration != api.sessionGeneration)) {
      return false;
    }
    final revision = ++_revision;
    final generation = api.sessionGeneration;
    _session = generation;
    _safety = _safety.waiting();
    _review = _review.waiting();
    notifyListeners();
    bool valid() =>
        !_disposed &&
        revision == _revision &&
        _current &&
        api.isCurrentSession(generation);
    Future<void> readSafety() async {
      try {
        final value = await repository.readSafety(generation);
        if (!valid()) return;
        _safety = ClinicalRead(
          phase: ClinicalPhase.ready,
          value: value,
          retrievedAt: DateTime.now().toUtc(),
        );
      } catch (failure) {
        if (!valid()) return;
        _safety = ClinicalRead(
          phase: ClinicalPhase.failed,
          value: denied(failure) ? null : _safety.value,
          retrievedAt: denied(failure) ? null : _safety.retrievedAt,
          stale: !denied(failure) && _safety.value != null,
          error: _message('Safety', failure),
        );
      }
      if (valid()) notifyListeners();
    }

    Future<void> readReview() async {
      try {
        final value = await repository.readReview(generation);
        if (!valid()) return;
        _review = ClinicalRead(
          phase: ClinicalPhase.ready,
          value: value,
          retrievedAt: DateTime.now().toUtc(),
        );
      } catch (failure) {
        if (!valid()) return;
        _review = ClinicalRead(
          phase: ClinicalPhase.failed,
          value: denied(failure) ? null : _review.value,
          retrievedAt: denied(failure) ? null : _review.retrievedAt,
          stale: !denied(failure) && _review.value != null,
          error: _message('Clinician review', failure),
        );
      }
      if (valid()) notifyListeners();
    }

    await Future.wait([readSafety(), readReview()]);
    return valid() &&
        _safety.phase == ClinicalPhase.ready &&
        _review.phase == ClinicalPhase.ready;
  }

  bool denied(Object failure) =>
      failure is ClinicalRequestException &&
      [401, 403].contains(failure.status);

  String _message(String source, Object failure) {
    if (failure is TimeoutException) {
      return '$source timed out. Refresh to confirm the latest information.';
    }
    if (failure is ClinicalRequestException) return failure.message;
    return '$source could not be loaded or verified. Check your connection and refresh.';
  }

  void markStale() {
    if (_disposed || !_current) return;
    _revision++;
    _safety = _safety.outdated();
    _review = _review.outdated();
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _revision++;
    _session = null;
    _safety = const ClinicalRead();
    _review = const ClinicalRead();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    api.removeListener(clear);
    super.dispose();
  }
}
