import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import 'agent_domain.dart';

enum AgentReadState {
  idle,
  loading,
  unavailable,
  empty,
  ready,
  stale,
  failed,
  ended,
}

class AgentController extends ChangeNotifier {
  AgentController(
    this.api, {
    required this.proposalId,
    AgentRepository? repository,
    this.timeout = const Duration(seconds: 20),
  }) : repository = repository ?? const UnsupportedAgentRepository(),
       context = AgentReadContext(
         api.observationOwner ?? '',
         api.sessionGeneration,
       ) {
    api.addListener(sessionChanged);
  }
  final ApiService api;
  final String proposalId;
  final AgentRepository repository;
  final AgentReadContext context;
  final Duration timeout;
  bool _disposed = false;
  int _revision = 0, _seenRevision = 0;
  AgentProposal? _proposal, _seenDefinition;
  AgentReadState state = AgentReadState.idle;
  bool locallyReviewed = false;
  Set<AgentContextScope> _localScopes = {};
  Set<AgentContextScope> get locallySelectedScopes =>
      Set.unmodifiable(_localScopes);
  bool get current =>
      !_disposed &&
      context.owner.isNotEmpty &&
      api.isCurrentSession(context.generation) &&
      api.canReadPatientClinicalStatus &&
      api.observationOwner == context.owner;
  AgentProposal? get proposal =>
      current && state == AgentReadState.ready ? _proposal : null;
  // Domain receipts/local review never enable a missing capability or substitute
  // for actual server permission. No execution adapter is connected in F4.
  bool get canExecute => false;
  bool get durableMemoryAvailable => false;
  bool get canTransmitExpandedContext => false;
  void selectLocally(Set<AgentContextScope> scopes) {
    if (current) {
      _localScopes = Set.from(scopes);
      notifyListeners();
    }
  }

  void reviewLocally() {
    if (current && proposal != null) {
      locallyReviewed = true;
      notifyListeners();
    }
  }

  Future<void> execute() async => throw const AgentUnsupported();
  Future<void> cancel() async => throw const AgentUnsupported();
  void sessionChanged() {
    if (!current) {
      _revision++;
      _proposal = null;
      _localScopes = {};
      _seenRevision = 0;
      _seenDefinition = null;
      locallyReviewed = false;
      state = AgentReadState.ended;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (!current) return;
    final request = ++_revision;
    _proposal = null;
    locallyReviewed = false;
    _localScopes = {};
    state = AgentReadState.loading;
    notifyListeners();
    try {
      final value = await repository
          .readProposal(proposalId, context)
          .timeout(timeout);
      if (!current || request != _revision) return;
      if (value == null) {
        state = AgentReadState.empty;
      } else {
        if (value.id != proposalId ||
            value.owner != context.owner ||
            value.revision < _seenRevision ||
            value.revision == _seenRevision &&
                _seenDefinition != null &&
                !value.sameRevisionContent(_seenDefinition!)) {
          throw const FormatException('Unverified proposal owner/revision');
        }
        _seenRevision = value.revision;
        _seenDefinition = value;
        if (!value.fresh ||
            value.status == AgentActionState.superseded ||
            value.status == AgentActionState.cancelled) {
          state = AgentReadState.stale;
        } else {
          _proposal = value;
          state = AgentReadState.ready;
        }
      }
    } on AgentUnsupported {
      if (!current || request != _revision) return;
      state = AgentReadState.unavailable;
    } catch (_) {
      if (!current || request != _revision) return;
      state = AgentReadState.failed;
    }
    if (current && request == _revision) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _seenDefinition = null;
    _proposal = null;
    _localScopes = {};
    api.removeListener(sessionChanged);
    super.dispose();
  }
}
