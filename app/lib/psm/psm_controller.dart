import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../clinical/clinical_models.dart';
import 'psm_models.dart';

class PsmReadException implements Exception {
  const PsmReadException(this.status);
  final int status;
}

abstract interface class PsmRepository {
  Future<PersonalSkinModel> read(int generation);
}

class RemotePsmRepository implements PsmRepository {
  @override
  Future<PersonalSkinModel> read(int generation) =>
      ApiService.instance.readPersonalSkinModel(generation);
}

enum PsmPhase { idle, loading, ready, failed, unsupported, ended }

class PsmController extends ChangeNotifier {
  PsmController(
    this.api, {
    PsmRepository? repository,
    this.timeout = const Duration(seconds: 20),
  }) : repository = repository ?? RemotePsmRepository(),
       generation = api.sessionGeneration,
       owner = api.observationOwner {
    api.addListener(sessionChanged);
  }
  final ApiService api;
  final PsmRepository repository;
  final int generation;
  final String? owner;
  final Duration timeout;
  bool _disposed = false;
  int _request = 0;
  PersonalSkinModel? _model;
  SafetyAssessment? _lastSafety;
  PsmPhase phase = PsmPhase.idle;
  String? error;
  bool get current =>
      !_disposed &&
      owner != null &&
      api.isCurrentSession(generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == owner;
  PersonalSkinModel? get model =>
      current && phase == PsmPhase.ready ? _model : null;
  SafetyAssessment? get safety => current ? _lastSafety : null;
  bool get safetyStale =>
      model?.safety == null || !identical(model?.safety, _lastSafety);
  void sessionChanged() {
    if (!current) {
      _request++;
      _model = null;
      _lastSafety = null;
      error = null;
      phase = PsmPhase.ended;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!current) return;
    final request = ++_request;
    _model = null;
    phase = PsmPhase.loading;
    error = null;
    notifyListeners();
    try {
      final value = await repository.read(generation).timeout(timeout);
      if (!current || request != _request) return;
      if (value.owner != owner) {
        throw const FormatException('Wrong model owner');
      }
      _model = value;
      if (value.safety != null) _lastSafety = value.safety;
      phase = PsmPhase.ready;
    } catch (e) {
      if (!current || request != _request) return;
      phase = e is FormatException || e is TypeError
          ? PsmPhase.unsupported
          : PsmPhase.failed;
      error = e is TimeoutException
          ? 'Model request timed out. Please retry.'
          : e is PsmReadException
          ? switch (e.status) {
              403 => 'Model access was denied. Check your account and retry.',
              404 => 'Personal Skin Model is unavailable from the server.',
              >= 500 => 'Model service temporarily unavailable. Please retry.',
              _ => 'The model could not be read. Please retry.',
            }
          : phase == PsmPhase.unsupported
          ? 'The server returned an unsupported model format. No model conclusion is shown.'
          : 'Could not read your skin evidence. Check your connection and retry.';
    }
    if (current && request == _request) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _model = null;
    _lastSafety = null;
    api.removeListener(sessionChanged);
    super.dispose();
  }
}
