import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

abstract class BaselineRepository {
  Future<Map<String, dynamic>> read();
}

class RemoteBaselineRepository implements BaselineRepository {
  @override
  Future<Map<String, dynamic>> read() => ApiService.instance.getBaseline();
}

class BaselineController extends ChangeNotifier {
  BaselineController(this.repository);
  final BaselineRepository repository;
  Map<String, dynamic>? _snapshot;
  bool loading = false;
  String? error;
  int _generation = 0;

  // Stale responses may be retained in memory, but never presented as current.
  bool get hasProgress => (_snapshot?['completed_days'] as int? ?? 0) > 0;
  bool get available => _snapshot != null && error == null && !loading;
  int? get completedDays => available ? _snapshot!['completed_days'] as int : null;
  bool get ready => available && _snapshot!['status'] == 'ready';
  bool get todayCheckedIn => available && _snapshot!['today_checked_in'] == true;
  Map<String, dynamic> get metrics => available
      ? Map<String, dynamic>.from(_snapshot!['metrics'] as Map)
      : {};

  Future<bool> refresh() async {
    final generation = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final snapshot = await repository.read();
      if (generation != _generation) return false;
      final days = snapshot['completed_days'];
      if (days is! int || days < 0 || days > 5 ||
          snapshot['required_days'] != 5 ||
          snapshot['status'] != (days == 5 ? 'ready' : 'collecting') ||
          snapshot['today_checked_in'] is! bool || snapshot['metrics'] is! Map) {
        throw ApiException('Invalid baseline response');
      }
      if (days == 5) {
        for (final name in ['hydration', 'texture', 'redness']) {
          final metric = (snapshot['metrics'] as Map)[name];
          if (metric is! Map || metric['mean'] is! num ||
              !(metric['mean'] as num).isFinite ||
              (metric['mean'] as num) < 0 || (metric['mean'] as num) > 100 ||
              metric['standard_deviation'] is! num ||
              !(metric['standard_deviation'] as num).isFinite ||
              (metric['standard_deviation'] as num) < 0) {
            throw ApiException('Invalid baseline measurements');
          }
        }
      }
      _snapshot = Map.of(snapshot);
      loading = false;
      notifyListeners();
      return true;
    } catch (_) {
      if (generation != _generation) return false;
      loading = false;
      error = 'Baseline unavailable. Connect and retry to confirm your progress.';
      notifyListeners();
      return false;
    }
  }

  void clear() {
    _generation++;
    _snapshot = null;
    loading = false;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
