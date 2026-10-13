import 'package:flutter/foundation.dart';
import '../capture/capture_history_models.dart';
import '../services/api_service.dart';
import '../services/request_failure.dart';
import 'doctor_connection.dart';
import 'doctor_evidence_models.dart';

class DoctorRecordsController extends ChangeNotifier {
  DoctorRecordsController(this.connection) {
    connection.addListener(_connectionChanged);
  }
  final DoctorConnectionController connection;
  DoctorTimelinePage? page;
  List<DoctorTimelineItem> _items = [];
  bool loading = false, loadingMore = false, _disposed = false;
  String? error;
  int _revision = 0;
  bool get current => !_disposed && connection.confirmed;
  bool get confirmed => current && page != null && error == null && !loading;
  List<DoctorTimelineItem> get items =>
      confirmed ? List.unmodifiable(_items) : [];
  bool get hasMore =>
      confirmed && page?.nextOffset != null && _items.length < 500;
  bool canReadCapture(String id) =>
      confirmed && _items.any((v) => v.sourceId == id && v.storedCapture);
  void _connectionChanged() {
    if (!current) invalidate();
  }

  void invalidate() {
    if (_disposed) return;
    _revision++;
    page = null;
    _items = [];
    loading = loadingMore = false;
    error = null;
    notifyListeners();
  }

  Future<bool> refresh() async {
    if (_disposed || loading || loadingMore) return false;
    final revision = ++_revision;
    page = null;
    _items = [];
    loading = true;
    error = null;
    notifyListeners();
    try {
      if (!await connection.verifyForRead()) return false;
      final data =
          await connection.parent.api.doctorResource(
                'patients/${connection.patientId}/timeline?offset=0&limit=100',
                connection.parent.generation,
              )
              as Map<String, dynamic>;
      final value = DoctorTimelinePage.fromApi(data, connection.patientId, 0);
      if (!current || revision != _revision) return false;
      page = value;
      _items = value.items;
    } catch (failure) {
      if (_disposed || revision != _revision) return false;
      page = null;
      _items = [];
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

  Future<void> loadMore() async {
    if (!hasMore || loadingMore) return;
    final revision = _revision,
        offset = page!.nextOffset!,
        expectedTotal = page!.total;
    loadingMore = true;
    notifyListeners();
    try {
      if (!await connection.verifyForRead()) return;
      final data =
          await connection.parent.api.doctorResource(
                'patients/${connection.patientId}/timeline?offset=$offset&limit=100',
                connection.parent.generation,
              )
              as Map<String, dynamic>;
      final value = DoctorTimelinePage.fromApi(
        data,
        connection.patientId,
        offset,
      );
      if (!current || revision != _revision) return;
      final ids = _items.map((v) => v.id).toSet();
      if (value.total != expectedTotal ||
          value.items.any((v) => !ids.add(v.id))) {
        throw const FormatException('History changed while paging');
      }
      _items = [..._items, ...value.items];
      page = value;
    } catch (failure) {
      if (_disposed || revision != _revision) return;
      error =
          'History is partial or changed. Refresh before drawing conclusions.';
      page = null;
      _items = [];
    } finally {
      if (!_disposed && revision == _revision) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<PrivateImageBytes> readImage(String id, int generation) async {
    final revision = _revision;
    bool active() =>
        canReadCapture(id) &&
        revision == _revision &&
        connection.parent.generation == generation;
    if (!active() || !await connection.verifyForRead() || !active()) {
      throw ApiException('Selected capture access is unverified.');
    }
    return connection.parent.api.readDoctorCaptureImage(
      id,
      generation,
      scope: this,
      active: active,
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _revision++;
    page = null;
    _items = [];
    notifyListeners();
    connection.removeListener(_connectionChanged);
    super.dispose();
  }
}
