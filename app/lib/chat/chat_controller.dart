import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../clinical/clinical_models.dart';
import '../assistance/assistance_models.dart';

class PatientChatReply {
  PatientChatReply.fromApi(Map<String, dynamic> data, {required String owner})
    : textReply = text(data['reply']),
      kind = text(data['kind']),
      escalated = flag(data['escalation_triggered']),
      compatibilitySource = text(data['azure_model_used']),
      assistance = AssistanceResponse.fromApi(
        object(object(data['safety_details'])['contextual_assistance']),
        owner: owner,
      ) {
    final snapshot = SafetyAssessment.fromApi(
      object(object(data['safety_details'])['authoritative_safety']),
    );
    if (!['education', 'uncertainty', 'escalation'].contains(kind) ||
        textReply != assistance.message ||
        escalated != (kind == 'escalation') ||
        snapshot.rawStatus != assistance.safety.rawStatus ||
        snapshot.guidance != assistance.safety.guidance ||
        snapshot.evaluatedAt != assistance.safety.evaluatedAt) {
      throw const FormatException('Unverified chat envelope');
    }
  }
  final String textReply, kind, compatibilitySource;
  final bool escalated;
  final AssistanceResponse assistance;
}

abstract interface class PatientChatRepository {
  Future<PatientChatReply> send(String message, int generation) async {
    final api = ApiService.instance,
        owner = ApiService.instance.observationOwner;
    final data = await api.patientInformationalPost(
      'chat',
      message,
      generation,
    );
    if (!api.isCurrentSession(generation) ||
        owner == null ||
        api.observationOwner != owner) {
      throw ApiException('Session changed. Reopen chat.');
    }
    return PatientChatReply.fromApi(data, owner: owner);
  }
}

class RemotePatientChatRepository implements PatientChatRepository {
  @override
  Future<PatientChatReply> send(String message, int generation) async =>
      PatientChatReply.fromApi(
        await ApiService.instance.patientInformationalPost(
          'chat',
          message,
          generation,
        ),
        owner: ApiService.instance.observationOwner!,
      );
}

class PatientChatTurn {
  PatientChatTurn(this.question, this.submittedAt);
  final String question;
  final DateTime submittedAt;
  PatientChatReply? response;
  DateTime? receivedAt;
  String? error;
  int attempts = 0;
}

class PatientChatController extends ChangeNotifier {
  PatientChatController(
    this.api, {
    PatientChatRepository? repository,
    this.timeout = const Duration(seconds: 60),
  }) : repository = repository ?? RemotePatientChatRepository(),
       generation = api.sessionGeneration,
       owner = api.observationOwner {
    api.addListener(sessionChanged);
  }
  final ApiService api;
  final PatientChatRepository repository;
  final int generation;
  final String? owner;
  final Duration timeout;
  final List<PatientChatTurn> _turns = [];
  bool _disposed = false, busy = false;
  int _revision = 0;
  String? validation;
  bool get current =>
      !_disposed &&
      owner != null &&
      api.isCurrentSession(generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == owner;
  List<PatientChatTurn> get turns =>
      current ? List.unmodifiable(_turns) : const [];
  void sessionChanged() {
    if (!current) {
      _revision++;
      _turns.clear();
      busy = false;
      validation = null;
      notifyListeners();
    }
  }

  void clear() {
    if (!current) return;
    _revision++;
    _turns.clear();
    busy = false;
    validation = null;
    notifyListeners();
  }

  Future<void> send(String input) async {
    if (!current || busy) return;
    final value = input.trim();
    if (value.isEmpty || value.runes.length > 1000) {
      validation = 'Enter a message of 1–1000 characters.';
      notifyListeners();
      return;
    }
    if (_turns.length >= 20) {
      validation =
          'This temporary view holds 20 questions. Clear this device view to start again.';
      notifyListeners();
      return;
    }
    final turn = PatientChatTurn(value, DateTime.now().toUtc());
    _turns.add(turn);
    await _request(turn);
  }

  Future<void> retry(PatientChatTurn turn) async {
    if (current &&
        !busy &&
        _turns.contains(turn) &&
        turn.error != null &&
        turn.attempts == 1) {
      await _request(turn);
    }
  }

  Future<void> _request(PatientChatTurn turn) async {
    final revision = ++_revision;
    turn.attempts++;
    turn.error = null;
    validation = null;
    busy = true;
    notifyListeners();
    try {
      final response = await repository
          .send(turn.question, generation)
          .timeout(timeout);
      if (!current || revision != _revision) return;
      if (response.assistance.owner != owner) {
        throw const FormatException('Wrong response owner');
      }
      turn.response = response;
      turn.receivedAt = DateTime.now().toUtc();
    } catch (e) {
      if (!current || revision != _revision) return;
      turn.error = e is TimeoutException
          ? 'Response timed out; no assistant reply was received.'
          : e is FormatException || e is TypeError
          ? 'Unsupported server response; no assistant reply is shown.'
          : 'The server assistant is unavailable. Your current skin context and safety status could not be checked.';
    }
    if (current && revision == _revision) {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _turns.clear();
    api.removeListener(sessionChanged);
    super.dispose();
  }
}
