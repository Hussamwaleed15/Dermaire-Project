import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'account_profile.dart';

enum AccountPhase { empty, loading, ready, partial, unauthorized, unavailable }

enum ProfileSaveResult { saved, savedReadbackUnavailable, unconfirmed }

class AccountController extends ChangeNotifier {
  AccountController(this.api) {
    api.addListener(clear);
  }
  final ApiService api;
  AccountPhase phase = AccountPhase.empty;
  String? error;
  bool saving = false;
  AccountProfile? _value;
  int? _session;
  int _request = 0;
  bool _disposed = false;

  AccountProfile? get value =>
      !_disposed &&
          _session != null &&
          api.isCurrentSession(_session!) &&
          api.hasConfirmedSafetyAcceptance
      ? _value
      : null;
  bool get ready =>
      value != null &&
      (phase == AccountPhase.ready || phase == AccountPhase.partial);
  bool _current(int session, int request) =>
      !_disposed && api.isCurrentSession(session) && request == _request;
  void _ready(AccountProfile profile) {
    _value = profile;
    phase = profile.partial ? AccountPhase.partial : AccountPhase.ready;
  }

  Future<bool> hydrate({bool reuseConsent = true}) async {
    if (_disposed || saving) return false;
    final session = api.sessionGeneration;
    final request = ++_request;
    _session = session;
    _value = null;
    error = null;
    if (!api.isCurrentSession(session) || !api.hasConfirmedSafetyAcceptance) {
      phase = AccountPhase.unauthorized;
      notifyListeners();
      return false;
    }
    phase = AccountPhase.loading;
    notifyListeners();
    try {
      final profile = await api.readAccountProfile(reuseConsent: reuseConsent);
      if (!_current(session, request)) return false;
      _ready(profile);
      notifyListeners();
      return true;
    } catch (failure) {
      if (!_current(session, request)) return false;
      phase = failure is ProfileRequestException && failure.unauthorized
          ? AccountPhase.unauthorized
          : AccountPhase.unavailable;
      error = _message(failure);
      notifyListeners();
      return false;
    }
  }

  Future<ProfileSaveResult> save(Map<String, dynamic> fields) async {
    if (_disposed || saving || !ready) return ProfileSaveResult.unconfirmed;
    final session = api.sessionGeneration;
    final request = ++_request;
    saving = true;
    error = null;
    notifyListeners();
    var confirmedWrite = false;
    try {
      final profile = await api.updateAccountProfile(fields);
      if (!_current(session, request)) return ProfileSaveResult.unconfirmed;
      _ready(profile);
      confirmedWrite = true;
      // PATCH UserOut confirms the write; GET reconciles the latest projection.
      final latest = await api.readAccountProfile(reuseConsent: false);
      if (!_current(session, request)) return ProfileSaveResult.unconfirmed;
      _ready(latest);
      return ProfileSaveResult.saved;
    } catch (failure) {
      if (!_current(session, request)) return ProfileSaveResult.unconfirmed;
      error = confirmedWrite
          ? 'Profile saved; latest view unavailable. Retry refresh.'
          : 'Save was not confirmed. Your draft is still here. Please retry.';
      return confirmedWrite
          ? ProfileSaveResult.savedReadbackUnavailable
          : ProfileSaveResult.unconfirmed;
    } finally {
      if (_current(session, request)) {
        saving = false;
        notifyListeners();
      }
    }
  }

  String _message(Object failure) {
    if (failure is TimeoutException) {
      return 'Profile loading timed out. Please retry.';
    }
    if (failure is ProfileRequestException) return failure.message;
    return 'Could not load your account profile. Check your connection and retry.';
  }

  void clear() {
    if (_disposed) return;
    _request++;
    _session = null;
    _value = null;
    saving = false;
    error = null;
    phase = api.isAuthenticated
        ? AccountPhase.empty
        : AccountPhase.unauthorized;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _value = null;
    _session = null;
    _request++;
    api.removeListener(clear);
    super.dispose();
  }
}
