import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

enum ConsentPhase {
  checking,
  required,
  accepting,
  confirmed,
  unavailable,
  ended,
}

/// A receipt is only current within the session that requested it.
class SafetyConsentController extends ChangeNotifier {
  SafetyConsentController(this.api) : generation = api.sessionGeneration {
    api.addListener(_sessionChanged);
  }

  final ApiService api;
  final int generation;
  ConsentPhase phase = ConsentPhase.checking;
  String? error;
  bool _disposed = false;
  bool _busy = false;
  bool _reconcileWrite = false;

  bool get current => !_disposed && api.isCurrentSession(generation);
  bool get confirmed =>
      current &&
      phase == ConsentPhase.confirmed &&
      api.hasConfirmedSafetyAcceptance;

  void _sessionChanged() {
    if (_disposed || api.isCurrentSession(generation)) return;
    phase = ConsentPhase.ended;
    error = 'Your session changed or expired. Please sign in again.';
    notifyListeners();
  }

  Future<void> refresh() async {
    if (_busy || !current) {
      _sessionChanged();
      return;
    }
    _busy = true;
    phase = ConsentPhase.checking;
    error = null;
    notifyListeners();
    try {
      final accepted = await api.readSafetyAcceptance();
      if (!current) return;
      phase = accepted ? ConsentPhase.confirmed : ConsentPhase.required;
    } catch (failure) {
      if (!current) return;
      phase = ConsentPhase.unavailable;
      error = _message(failure);
    } finally {
      _busy = false;
      if (current) notifyListeners();
    }
  }

  Future<void> accept() async {
    if (_busy || !current) {
      _sessionChanged();
      return;
    }
    _busy = true;
    phase = ConsentPhase.accepting;
    error = null;
    notifyListeners();
    try {
      // An earlier timeout or failed readback may hide a successful write.
      // Reconcile before repeating that write; false still needs explicit POST.
      if (_reconcileWrite && await api.readSafetyAcceptance()) {
        if (current) phase = ConsentPhase.confirmed;
        return;
      }
      if (!current) return;
      _reconcileWrite = true;
      await api.acceptSafetyTerms();
      if (!current) return;
      final accepted = await api.readSafetyAcceptance();
      if (!current) return;
      phase = accepted ? ConsentPhase.confirmed : ConsentPhase.required;
      if (!accepted) {
        error = 'The server has not confirmed your acceptance. Please retry.';
      }
    } catch (failure) {
      if (!current) return;
      phase = ConsentPhase.required;
      error = _message(failure);
    } finally {
      _busy = false;
      if (current) notifyListeners();
    }
  }

  String _message(Object failure) {
    if (failure is TimeoutException) {
      return 'Safety acceptance could not be confirmed in time. Please retry.';
    }
    if (failure is ApiException) return failure.message;
    return 'Could not confirm safety acceptance. Check your connection and retry.';
  }

  @override
  void dispose() {
    _disposed = true;
    api.removeListener(_sessionChanged);
    super.dispose();
  }
}
