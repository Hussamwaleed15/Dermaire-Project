import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'observation_models.dart';

enum ObservationPhase {
  editing,
  review,
  submitting,
  confirmed,
  rejected,
  uncertain,
  ended,
}

enum ObservationHistoryPhase { empty, loading, ready, failed }

abstract interface class ObservationRepository {
  Future<ObservationRecord> save(ObservationDraft draft, int generation);
  Future<List<ObservationRecord>> history(int generation);
}

class RemoteObservationRepository implements ObservationRepository {
  RemoteObservationRepository(this.api);
  final ApiService api;
  @override
  Future<ObservationRecord> save(ObservationDraft draft, int generation) =>
      api.submitPatientObservation(draft: draft, generation: generation);
  @override
  Future<List<ObservationRecord>> history(int generation) =>
      api.getPatientObservations(generation: generation);
}

/// In-memory account state. No automatic POST retry or content/time matching
/// for an unknown write. ID-based GET reconciliation is the only confirmation.
class ObservationController extends ChangeNotifier {
  ObservationController(
    this.api, {
    ObservationRepository? repository,
    this.onConfirmed,
    this.onUncertain,
  }) : repository = repository ?? RemoteObservationRepository(api) {
    api.addListener(clear);
  }
  final ApiService api;
  final ObservationRepository repository;
  final void Function()? onConfirmed;
  final void Function()? onUncertain;
  ObservationDraft _draft = ObservationDraft();
  ObservationDraft? _submitted;
  ObservationRecord? _saved;
  List<ObservationRecord>? _history;
  String? _candidateId;
  int? _session;
  int _writeRevision = 0, _historyRevision = 0;
  bool _disposed = false;
  ObservationPhase phase = ObservationPhase.editing;
  ObservationHistoryPhase historyPhase = ObservationHistoryPhase.empty;
  String? message, historyError;
  bool historyStale = false, confirmedByHistory = false;
  bool get allowed => !_disposed && api.canReadPatientClinicalStatus;
  bool get current => allowed && api.isCurrentSession(_session ?? -1);
  ObservationDraft get draft => current ? _draft : ObservationDraft();
  ObservationRecord? get saved => current ? _saved : null;
  List<ObservationRecord>? get rows => current ? _history : null;
  void begin({required int generation}) {
    if (!allowed ||
        !api.isCurrentSession(generation) ||
        phase == ObservationPhase.submitting) {
      return;
    }
    if (_session != generation) {
      clear(notify: false);
      _session = generation;
    }
    if (phase == ObservationPhase.ended) phase = ObservationPhase.editing;
    // Reopening an uncertain/submitting flow never silently authorizes a retry.
  }

  void startNew({required int generation}) {
    if (!allowed ||
        !api.isCurrentSession(generation) ||
        phase == ObservationPhase.submitting) {
      return;
    }
    _session = generation;
    _writeRevision++;
    _draft = ObservationDraft();
    _submitted = null;
    _saved = null;
    _candidateId = null;
    phase = ObservationPhase.editing;
    message = null;
    confirmedByHistory = false;
    notifyListeners();
  }

  void edit(ObservationDraft value, {required int generation}) {
    if (!api.isCurrentSession(generation) ||
        !current ||
        ![
          ObservationPhase.editing,
          ObservationPhase.review,
          ObservationPhase.rejected,
        ].contains(phase)) {
      return;
    }
    _draft = value;
    phase = ObservationPhase.editing;
    message = null;
    notifyListeners();
  }

  bool review({required int generation}) {
    if (!api.isCurrentSession(generation) ||
        !current ||
        ![
          ObservationPhase.editing,
          ObservationPhase.rejected,
        ].contains(phase)) {
      return false;
    }
    message = _draft.validation;
    if (message != null) {
      notifyListeners();
      return false;
    }
    phase = ObservationPhase.review;
    notifyListeners();
    return true;
  }

  Future<bool> submit({required int generation}) async {
    if (!current ||
        !api.isCurrentSession(generation) ||
        phase != ObservationPhase.review ||
        _draft.validation != null) {
      return false;
    }
    final revision = ++_writeRevision;
    _submitted = _draft;
    phase = ObservationPhase.submitting;
    message = null;
    notifyListeners();
    try {
      final record = await repository.save(_submitted!, generation);
      if (!current ||
          revision != _writeRevision ||
          !api.isCurrentSession(generation)) {
        return false;
      }
      if (record.ownerId != api.observationOwner) {
        throw const ObservationWriteException(ObservationFailure.uncertain);
      }
      if (!record.matches(_submitted!)) {
        throw ObservationWriteException(
          ObservationFailure.uncertain,
          candidateId: record.id,
        );
      }
      _confirm(record);
      return true;
    } catch (failure) {
      if (!current ||
          revision != _writeRevision ||
          !api.isCurrentSession(generation)) {
        return false;
      }
      if (failure is ObservationWriteException &&
          failure.failure == ObservationFailure.rejected) {
        phase = ObservationPhase.rejected;
        message =
            'The server rejected this observation. It was not confirmed saved. Review your fields before another explicit submission.';
      } else {
        phase = ObservationPhase.uncertain;
        _candidateId = failure is ObservationWriteException
            ? failure.candidateId
            : null;
        message =
            'We could not confirm whether the server saved this attempt. Do not resend automatically; another submission may create a duplicate. Review saved history.';
      }
      notifyListeners();
      if (current && phase == ObservationPhase.uncertain) onUncertain?.call();
      return false;
    }
  }

  void _confirm(ObservationRecord record) {
    _saved = record;
    _candidateId = null;
    phase = ObservationPhase.confirmed;
    message = null;
    historyStale = _history != null;
    notifyListeners();
    if (current) onConfirmed?.call();
  }

  Future<bool> loadHistory({required int generation}) async {
    if (!allowed || !api.isCurrentSession(generation)) return false;
    if (_session != generation) {
      clear(notify: false);
      _session = generation;
    }
    final revision = ++_historyRevision;
    historyPhase = ObservationHistoryPhase.loading;
    historyStale = _history != null;
    historyError = null;
    notifyListeners();
    try {
      final records = await repository.history(generation);
      if (!current ||
          !api.isCurrentSession(generation) ||
          revision != _historyRevision) {
        return false;
      }
      if (records.any((r) => r.ownerId != api.observationOwner) ||
          records.map((r) => r.id).toSet().length != records.length) {
        throw const FormatException('Duplicate history identity');
      }
      _history = List.unmodifiable(records);
      historyPhase = ObservationHistoryPhase.ready;
      historyStale = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (!current ||
          !api.isCurrentSession(generation) ||
          revision != _historyRevision) {
        return false;
      }
      historyPhase = ObservationHistoryPhase.failed;
      historyStale = _history != null;
      historyError =
          'Skin history unavailable. Connect and refresh; previous records do not confirm the current history.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> reconcile({required int generation}) async {
    if (!current || phase != ObservationPhase.uncertain) return false;
    final revision = _writeRevision;
    if (!await loadHistory(generation: generation) ||
        !current ||
        revision != _writeRevision ||
        phase != ObservationPhase.uncertain) {
      return false;
    }
    if (_candidateId != null && _submitted != null) {
      final matches = _history!.where(
        (r) => r.id == _candidateId && r.matches(_submitted!),
      );
      if (matches.length == 1) {
        confirmedByHistory = true;
        _confirm(matches.single);
        return true;
      }
    }
    message =
        'History was refreshed, but it cannot prove the outcome of this attempt without an exact matching server record ID. No automatic resubmission is safe.';
    notifyListeners();
    return false;
  }

  void clear({bool notify = true}) {
    if (_disposed) return;
    _writeRevision++;
    _historyRevision++;
    _session = null;
    _draft = ObservationDraft();
    _submitted = null;
    _saved = null;
    _history = null;
    _candidateId = null;
    phase = ObservationPhase.ended;
    historyPhase = ObservationHistoryPhase.empty;
    message = null;
    historyError = null;
    historyStale = false;
    confirmedByHistory = false;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _writeRevision++;
    _historyRevision++;
    api.removeListener(clear);
    super.dispose();
  }
}
