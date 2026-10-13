import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'assistance_models.dart';

class AssistanceReadException implements Exception {
  const AssistanceReadException(this.status);
  final int status;
}

abstract interface class AssistanceRepository {
  Future<AssistanceResponse> request(String message, int generation);
}

class RemoteAssistanceRepository implements AssistanceRepository {
  @override
  Future<AssistanceResponse> request(String message, int generation) =>
      ApiService.instance.requestPatientAssistance(message, generation);
}

class AssistanceController extends ChangeNotifier {
  AssistanceController(
    this.api, {
    AssistanceRepository? repository,
    this.timeout = const Duration(seconds: 60),
  }) : repository = repository ?? RemoteAssistanceRepository(),
       generation = api.sessionGeneration,
       owner = api.observationOwner {
    api.addListener(changedSession);
  }
  final ApiService api;
  final AssistanceRepository repository;
  final int generation;
  final String? owner;
  final Duration timeout;
  bool _disposed = false, busy = false;
  int _revision = 0, attempts = 0;
  String? question, error;
  AssistanceResponse? _response;
  bool get current =>
      !_disposed &&
      owner != null &&
      api.isCurrentSession(generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == owner;
  AssistanceResponse? get response => current ? _response : null;
  bool get canRetry => current && !busy && error != null && attempts == 1;
  void changedSession() {
    if (!current) {
      _revision++;
      busy = false;
      question = null;
      error = null;
      _response = null;
      attempts = 0;
      notifyListeners();
    }
  }

  Future<void> send(String input, {bool retry = false}) async {
    if (!current || busy) return;
    final value = input.trim();
    if (value.isEmpty || value.runes.length > 1000) {
      error = 'Enter a question of 1–1000 characters.';
      notifyListeners();
      return;
    }
    if (retry && !canRetry) return;
    if (retry && value != question) return;
    if (!retry) {
      question = value;
      attempts = 0;
    }
    attempts++;
    final request = ++_revision;
    busy = true;
    error = null;
    _response = null;
    notifyListeners();
    try {
      final result = await repository
          .request(value, generation)
          .timeout(timeout);
      if (!current || request != _revision) return;
      if (result.owner != owner) {
        throw const FormatException('Wrong response owner');
      }
      _response = result;
    } catch (e) {
      if (!current || request != _revision) return;
      error = e is TimeoutException
          ? 'Response timed out. No successful response was received.'
          : e is FormatException || e is TypeError
          ? 'Unsupported response. No assistant conclusion is shown.'
          : e is AssistanceReadException && e.status == 403
          ? 'Access denied. Check your account.'
          : 'The server assistant is unavailable. Your current skin context and safety status could not be checked.';
    }
    if (current && request == _revision) {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> retry() => send(question ?? '', retry: true);
  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _response = null;
    question = null;
    api.removeListener(changedSession);
    super.dispose();
  }
}
