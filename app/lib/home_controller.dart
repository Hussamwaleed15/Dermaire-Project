import 'dart:convert';
import 'home/home_response.dart';
import 'package:flutter/foundation.dart';
import 'services/api_service.dart';

abstract class HomeRepository {
  Future<Map<String, dynamic>> read();
}

class RemoteHomeRepository implements HomeRepository {
  @override
  Future<Map<String, dynamic>> read() => ApiService.instance.getHome();
}

class HomeController extends ChangeNotifier {
  HomeController(this.repository);
  final HomeRepository repository;
  Map<String, dynamic>? _snapshot;
  int _generation = 0;
  bool loading = false;
  bool _disposed = false;
  int? _session;
  DateTime? retrievedAt;
  bool stale = false;
  void markStale() {
    if (_disposed) return;
    _generation++;
    loading = false;
    stale = _snapshot != null;
    notifyListeners();
  }

  String? error;
  String get today => DateTime.now().toUtc().toIso8601String().split('T').first;
  bool get available =>
      !_disposed &&
      _session == ApiService.instance.sessionGeneration &&
      !stale &&
      !loading &&
      error == null &&
      _snapshot?['date'] == today;
  Map<String, dynamic>? get current => available
      ? jsonDecode(jsonEncode(_snapshot)) as Map<String, dynamic>
      : null;

  void validate(Map<String, dynamic> value) =>
      validateHomeResponse(value, today);

  Future<bool> refresh() async {
    if (_disposed) return false;
    final generation = ++_generation;
    final session = ApiService.instance.sessionGeneration;
    _session = session;
    bool valid() =>
        !_disposed &&
        generation == _generation &&
        session == ApiService.instance.sessionGeneration;
    loading = true;
    stale = _snapshot != null;
    error = null;
    notifyListeners();
    try {
      final value = await repository.read().timeout(
        const Duration(seconds: 15),
      );
      if (!valid()) return false;
      validate(value);
      _snapshot = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
      retrievedAt = DateTime.now().toUtc();
      stale = false;
      loading = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (!valid()) return false;
      loading = false;
      error = 'Home unavailable. Connect and refresh to confirm current data.';
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _generation++;
    _snapshot = null;
    _session = null;
    retrievedAt = null;
    stale = false;
    loading = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
