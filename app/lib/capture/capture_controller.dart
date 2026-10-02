import 'package:flutter/foundation.dart';

enum CapturePhase { ready, checking, accepted, rejected, failure }

typedef CaptureSubmit =
    Future<Map<String, dynamic>> Function(Uint8List bytes, String filename);

class CaptureController extends ChangeNotifier {
  CaptureController(this.submit);
  final CaptureSubmit submit;
  CapturePhase phase = CapturePhase.ready;
  Map<String, dynamic>? record;
  String? error;
  int _generation = 0;
  bool _disposed = false;

  List<String> get reasons => (record?['quality']?['reasons'] as List? ?? [])
      .map((r) => r.toString())
      .toList();

  void retake() {
    _generation++;
    phase = CapturePhase.ready;
    record = null;
    error = null;
    notifyListeners();
  }

  void selectionFailed() {
    _generation++;
    record = null;
    phase = CapturePhase.failure;
    error = 'Could not open this photo. Choose a JPEG or PNG up to 8 MiB.';
    notifyListeners();
  }

  Future<void> check(Uint8List bytes, String filename) async {
    final generation = ++_generation;
    phase = CapturePhase.checking;
    record = null;
    error = null;
    notifyListeners();
    try {
      final result = await submit(bytes, filename);
      if (_disposed || generation != _generation) return;
      final quality = result['quality'];
      if (result['id'] is! String ||
          (result['id'] as String).isEmpty ||
          quality is! Map ||
          quality['version'] != 'capture-quality-1.0' ||
          quality['reasons'] is! List ||
          !(quality['reasons'] as List).every((value) => value is String) ||
          result['state'] != quality['decision'] ||
          !['accepted', 'rejected'].contains(result['state']) ||
          result['provenance']?['quality'] != 'server_computed' ||
          !['azure_blob', 'not_persisted'].contains(result['storage'])) {
        throw const FormatException('Unconfirmed capture response');
      }
      record = result;
      phase = result['state'] == 'accepted'
          ? CapturePhase.accepted
          : CapturePhase.rejected;
    } catch (_) {
      if (_disposed || generation != _generation) return;
      record = null;
      phase = CapturePhase.failure;
      error =
          'Quality could not be confirmed. Check your connection and capture history before retrying.';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
