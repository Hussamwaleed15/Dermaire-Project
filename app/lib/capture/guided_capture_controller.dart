import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'photo_preparation.dart';
import 'guided_capture_models.dart';

enum GuidedCapturePhase {
  ready,
  review,
  uploading,
  confirmed,
  rejected,
  uncertain,
  ended,
}

abstract interface class GuidedCaptureRepository {
  Future<GuidedCaptureRecord> upload(
    PreparedPhoto photo,
    String source,
    String key,
    int generation,
  );
  Future<GuidedCaptureRecord> read(String id, int generation);
  Future<CaptureMeasurement> measurement(String id, int generation);
}

class RemoteGuidedCaptureRepository implements GuidedCaptureRepository {
  RemoteGuidedCaptureRepository(this.api);
  final ApiService api;
  @override
  Future<GuidedCaptureRecord> upload(
    PreparedPhoto p,
    String source,
    String key,
    int g,
  ) => api.submitGuidedCapture(
    photo: p,
    source: source,
    attemptKey: key,
    generation: g,
  );
  @override
  Future<GuidedCaptureRecord> read(String id, int g) =>
      api.readGuidedCapture(id: id, generation: g);
  @override
  Future<CaptureMeasurement> measurement(String id, int g) =>
      api.readCaptureMeasurement(id: id, generation: g);
}

/// One account-owned attempt; route departure never cancels a dispatched POST.
class GuidedCaptureController extends ChangeNotifier {
  GuidedCaptureController(this.api, {GuidedCaptureRepository? repository})
    : repository = repository ?? RemoteGuidedCaptureRepository(api) {
    api.addListener(clear);
  }
  final ApiService api;
  final GuidedCaptureRepository repository;
  int? _session;
  int _revision = 0, _readRevision = 0;
  bool _disposed = false;
  PreparedPhoto? _photo;
  GuidedCaptureRecord? _record;
  CaptureMeasurement? _readMeasurement;
  String? _source, _key, _fingerprint, _candidate;
  GuidedCapturePhase phase = GuidedCapturePhase.ready;
  String? error, measurementError;
  bool reading = false;
  bool get allowed => !_disposed && api.canReadPatientClinicalStatus;
  bool get current => allowed && api.isCurrentSession(_session ?? -1);
  PreparedPhoto? get photo => current ? _photo : null;
  GuidedCaptureRecord? get record => current ? _record : null;
  CaptureMeasurement? get measurement =>
      record?.measurement ?? (current ? _readMeasurement : null);
  bool get canChoose =>
      current &&
      ![
        GuidedCapturePhase.uploading,
        GuidedCapturePhase.uncertain,
      ].contains(phase);
  bool _valid(int g, int revision) =>
      current && api.isCurrentSession(g) && revision == _revision;
  void begin(int generation) {
    if (!allowed || !api.isCurrentSession(generation)) return;
    if (_session != generation) {
      clear(notify: false);
      _session = generation;
      phase = GuidedCapturePhase.ready;
    }
  }

  void select(PreparedPhoto photo, String source, {required int generation}) {
    if (!canChoose ||
        !api.isCurrentSession(generation) ||
        !['camera', 'upload'].contains(source)) {
      return;
    }
    _revision++;
    _readRevision++;
    _photo = photo;
    _source = source;
    _record = null;
    _readMeasurement = null;
    _candidate = null;
    _key = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _fingerprint = photo.requestFingerprint(source);
    reading = false;
    phase = GuidedCapturePhase.review;
    error = null;
    measurementError = null;
    notifyListeners();
  }

  void reset({required int generation, bool acknowledgeUncertain = false}) {
    if (!current ||
        !api.isCurrentSession(generation) ||
        phase == GuidedCapturePhase.uploading ||
        (phase == GuidedCapturePhase.uncertain && !acknowledgeUncertain)) {
      return;
    }
    _revision++;
    _readRevision++;
    _photo = null;
    _record = null;
    _readMeasurement = null;
    _source = null;
    _key = null;
    _fingerprint = null;
    _candidate = null;
    reading = false;
    phase = GuidedCapturePhase.ready;
    error = null;
    measurementError = null;
    notifyListeners();
  }

  void releasePreview({required int generation}) {
    if (!current || !api.isCurrentSession(generation)) return;
    _photo = null;
    if (phase == GuidedCapturePhase.review ||
        phase == GuidedCapturePhase.rejected) {
      reset(generation: generation);
    } else {
      notifyListeners();
    }
  }

  Future<bool> upload({required int generation}) async {
    if (!current ||
        !api.isCurrentSession(generation) ||
        phase != GuidedCapturePhase.review ||
        _photo == null) {
      return false;
    }
    final revision = ++_revision;
    final payload = _photo!;
    phase = GuidedCapturePhase.uploading;
    error = null;
    notifyListeners();
    try {
      final receipt = await repository
          .upload(payload, _source!, _key!, generation)
          .timeout(const Duration(seconds: 60));
      if (!_valid(generation, revision)) return false;
      if (receipt.owner != api.observationOwner ||
          receipt.source != _source ||
          receipt.quality.requestFingerprint != _fingerprint) {
        throw GuidedCaptureWriteException(
          CaptureWriteFailure.uncertain,
          candidateId: receipt.owner == api.observationOwner
              ? receipt.id
              : null,
        );
      }
      _record = receipt;
      _photo = null;
      phase = GuidedCapturePhase.confirmed;
      notifyListeners();
      return true;
    } catch (failure) {
      if (!_valid(generation, revision)) return false;
      if (failure is GuidedCaptureWriteException &&
          failure.failure == CaptureWriteFailure.rejected) {
        phase = GuidedCapturePhase.rejected;
        error =
            'The server rejected this upload request. No capture result was confirmed. Review or choose another photo.';
      } else {
        _photo = null;
        phase = GuidedCapturePhase.uncertain;
        _candidate = failure is GuidedCaptureWriteException
            ? failure.candidateId
            : null;
        error =
            'The upload outcome is unknown. The server may have stored the photo. Do not resend automatically.';
      }
      notifyListeners();
      return false;
    }
  }

  bool get canReconcile =>
      current && phase == GuidedCapturePhase.uncertain && _candidate != null;
  Future<bool> reconcile({required int generation}) async {
    if (!canReconcile || reading || !api.isCurrentSession(generation)) {
      return false;
    }
    final revision = _revision, read = ++_readRevision;
    final id = _candidate!;
    reading = true;
    notifyListeners();
    try {
      final receipt = await repository
          .read(id, generation)
          .timeout(const Duration(seconds: 20));
      if (!_valid(generation, revision) || read != _readRevision) return false;
      if (receipt.id != id ||
          receipt.owner != api.observationOwner ||
          receipt.source != _source ||
          receipt.quality.requestFingerprint != _fingerprint) {
        throw const FormatException('Unverified attempt readback');
      }
      _record = receipt;
      _photo = null;
      phase = GuidedCapturePhase.confirmed;
      error = null;
      return true;
    } catch (_) {
      if (!_valid(generation, revision) || read != _readRevision) return false;
      error =
          'This read could not confirm the original upload. Its outcome remains unknown; no photo was resubmitted.';
      return false;
    } finally {
      if (_valid(generation, revision) && read == _readRevision) {
        reading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshMeasurement({required int generation}) async {
    if (!current ||
        !api.isCurrentSession(generation) ||
        record?.state != 'accepted' ||
        reading) {
      return;
    }
    final revision = _revision, read = ++_readRevision, id = record!.id;
    reading = true;
    measurementError = null;
    notifyListeners();
    try {
      final value = await repository
          .measurement(id, generation)
          .timeout(const Duration(seconds: 20));
      if (!_valid(generation, revision) ||
          read != _readRevision ||
          record?.id != id) {
        return;
      }
      if (value.captureId != id ||
          value.qualityFingerprint != record!.quality.requestFingerprint) {
        throw const FormatException('Foreign capture measurement');
      }
      _readMeasurement = value;
    } catch (_) {
      if (!_valid(generation, revision) || read != _readRevision) return;
      measurementError =
          'No verified image estimates could be read. Your capture receipt is unchanged.';
    } finally {
      if (_valid(generation, revision) && read == _readRevision) {
        reading = false;
        notifyListeners();
      }
    }
  }

  void clear({bool notify = true}) {
    if (_disposed) return;
    _revision++;
    _readRevision++;
    _session = null;
    _photo = null;
    _record = null;
    _readMeasurement = null;
    _source = null;
    _key = null;
    _fingerprint = null;
    _candidate = null;
    phase = GuidedCapturePhase.ended;
    reading = false;
    error = null;
    measurementError = null;
    if (notify) notifyListeners();
  }

  @override
  void dispose() {
    clear(notify: false);
    _disposed = true;
    api.removeListener(clear);
    super.dispose();
  }
}
