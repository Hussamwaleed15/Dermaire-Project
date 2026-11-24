import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'guided_capture_models.dart';
import 'capture_history_models.dart';

abstract interface class CaptureHistoryRepository {
  Future<List<GuidedCaptureRecord>> history(int generation);
  Future<GuidedCaptureRecord> record(String id, int generation);
  Future<CaptureMeasurement> measurement(String id, int generation);
}

class RemoteCaptureHistoryRepository implements CaptureHistoryRepository {
  @override
  Future<List<GuidedCaptureRecord>> history(int generation) =>
      ApiService.instance.readPrivateCaptureHistory(generation);
  @override
  Future<GuidedCaptureRecord> record(String id, int generation) =>
      ApiService.instance.readGuidedCapture(id: id, generation: generation);
  @override
  Future<CaptureMeasurement> measurement(String id, int generation) =>
      ApiService.instance.readCaptureMeasurement(
        id: id,
        generation: generation,
      );
}

// Route lifetime and session generation are both required; a disposed route or
// an old response cannot publish, even when tokens are reused by the next login.
class CaptureHistoryController extends ChangeNotifier {
  CaptureHistoryController(
    this.api, {
    CaptureHistoryRepository? repository,
    this.timeout = const Duration(seconds: 20),
  }) : repository = repository ?? RemoteCaptureHistoryRepository(),
       generation = api.sessionGeneration,
       owner = api.observationOwner {
    api.addListener(sessionChanged);
  }
  final ApiService api;
  final CaptureHistoryRepository repository;
  final Duration timeout;
  final int generation;
  final String? owner;
  bool disposed = false, loading = false, confirmed = false;
  int revision = 0;
  List<GuidedCaptureRecord> records = const [];
  String? error;
  bool get current =>
      !disposed &&
      api.isCurrentSession(generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == owner &&
      owner != null;
  void sessionChanged() {
    if (!current) {
      revision++;
      records = const [];
      error = null;
      loading = false;
      confirmed = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!current) return;
    final request = ++revision;
    records = const [];
    confirmed = false;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final rows = await repository.history(generation).timeout(timeout);
      if (!current || request != revision) return;
      if (rows.length > 100 ||
          rows.any((r) => r.owner != owner) ||
          rows.map((r) => r.id).toSet().length != rows.length) {
        throw const FormatException('Unverified history');
      }
      final sorted = rows.toList()
        ..sort((a, b) {
          final time = b.receivedAt.compareTo(a.receivedAt);
          return time != 0 ? time : b.id.compareTo(a.id);
        });
      records = List.unmodifiable(sorted);
      confirmed = true;
    } catch (e) {
      if (!current || request != revision) return;
      error = e is TimeoutException
          ? 'History request timed out. Please retry.'
          : captureReadError(e);
    }
    if (current && request == revision) {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    revision++;
    records = const [];
    api.removeListener(sessionChanged);
    super.dispose();
  }
}

class CaptureDetailController extends ChangeNotifier {
  CaptureDetailController(
    this.api,
    this.id, {
    CaptureHistoryRepository? repository,
    this.timeout = const Duration(seconds: 20),
  }) : repository = repository ?? RemoteCaptureHistoryRepository(),
       generation = api.sessionGeneration,
       owner = api.observationOwner {
    api.addListener(sessionChanged);
  }
  final ApiService api;
  final String id;
  final CaptureHistoryRepository repository;
  final Duration timeout;
  final int generation;
  final String? owner;
  bool disposed = false, loading = false, reading = false;
  int revision = 0, measurementRevision = 0;
  GuidedCaptureRecord? record;
  CaptureMeasurement? measurement;
  String? error, measurementError;
  bool get current =>
      !disposed &&
      owner != null &&
      api.isCurrentSession(generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == owner;
  void sessionChanged() {
    if (!current) {
      revision++;
      measurementRevision++;
      record = null;
      measurement = null;
      error = null;
      measurementError = null;
      loading = false;
      reading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!current) return;
    final request = ++revision;
    measurementRevision++;
    loading = true;
    reading = false;
    record = null;
    measurement = null;
    error = null;
    measurementError = null;
    notifyListeners();
    try {
      final value = await repository.record(id, generation).timeout(timeout);
      if (!current || request != revision) return;
      if (value.id != id || value.owner != owner) {
        throw const FormatException('Unverified capture');
      }
      record = value;
    } catch (e) {
      if (!current || request != revision) return;
      error = e is TimeoutException
          ? 'Capture request timed out. Please retry.'
          : captureReadError(e);
    }
    if (!current || request != revision) return;
    loading = false;
    notifyListeners();
    if (record?.state == 'accepted') await readMeasurement();
  }

  Future<void> readMeasurement() async {
    final receipt = record;
    if (!current || receipt == null || receipt.state != 'accepted') return;
    final request = ++measurementRevision;
    reading = true;
    measurement = null;
    measurementError = null;
    notifyListeners();
    try {
      final value = await repository
          .measurement(id, generation)
          .timeout(timeout);
      if (!current ||
          request != measurementRevision ||
          !identical(record, receipt)) {
        return;
      }
      if (value.captureId != id ||
          value.qualityFingerprint != receipt.quality.requestFingerprint) {
        throw const FormatException('Unverified measurement');
      }
      measurement = value;
    } catch (e) {
      if (!current || request != measurementRevision) return;
      measurementError = measurementReadError(e);
    }
    if (current && request == measurementRevision) {
      reading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    disposed = true;
    revision++;
    measurementRevision++;
    record = null;
    measurement = null;
    api.removeListener(sessionChanged);
    super.dispose();
  }
}

// Read-only, bounded traversal of the receipt window. No image fetch, metric
// generation, automatic replay, or client-side comparison is performed here.
class MeasurementHistoryController extends CaptureHistoryController {
  MeasurementHistoryController(super.api, {super.repository, super.timeout});
  static const batchSize = 5;
  final Map<String, CaptureMeasurement> measurements = {};
  final Map<String, String> failures = {};
  int visibleCount = 0;
  bool reading = false;
  String? readingId;
  bool get hasMore => confirmed && visibleCount < records.length;
  List<GuidedCaptureRecord> get visibleRecords =>
      List.unmodifiable(records.take(visibleCount));

  void clearMeasurements() {
    measurements.clear();
    failures.clear();
    visibleCount = 0;
    reading = false;
    readingId = null;
  }

  @override
  void sessionChanged() {
    if (!current) clearMeasurements();
    super.sessionChanged();
  }

  @override
  Future<void> refresh() async {
    clearMeasurements();
    final pending = super.refresh();
    final request = revision;
    await pending;
    if (current && request == revision && confirmed && !loading) {
      await loadMore();
    }
  }

  Future<void> loadMore() async {
    if (!current || loading || reading || !hasMore) return;
    final request = revision;
    final start = visibleCount;
    visibleCount = (visibleCount + batchSize).clamp(0, records.length);
    reading = true;
    notifyListeners();
    for (final record in records.sublist(start, visibleCount)) {
      if (!current || request != revision) return;
      await readOne(record, request);
    }
    finish(request);
  }

  Future<void> retry(String id) async {
    if (!current || loading || reading || !failures.containsKey(id)) return;
    final record = visibleRecords.where((row) => row.id == id).firstOrNull;
    if (record == null) return;
    final request = revision;
    reading = true;
    await readOne(record, request);
    finish(request);
  }

  Future<void> readOne(GuidedCaptureRecord record, int request) async {
    if (record.state != 'accepted') return;
    readingId = record.id;
    failures.remove(record.id);
    measurements.remove(record.id);
    notifyListeners();
    try {
      final value = await repository
          .measurement(record.id, generation)
          .timeout(timeout);
      if (!current || request != revision) return;
      if (value.captureId != record.id ||
          value.qualityFingerprint != record.quality.requestFingerprint) {
        throw const FormatException('Measurement identity mismatch');
      }
      measurements[record.id] = value;
    } catch (e) {
      if (!current || request != revision) return;
      failures[record.id] = measurementReadError(e);
    }
    if (current && request == revision) {
      readingId = null;
      notifyListeners();
    }
  }

  void finish(int request) {
    if (!current || request != revision) return;
    reading = false;
    readingId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    clearMeasurements();
    super.dispose();
  }
}
