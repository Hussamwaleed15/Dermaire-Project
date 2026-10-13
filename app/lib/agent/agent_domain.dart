/// Proposed future domain concepts ONLY, not current JSON fields or endpoints.
/// Existing contextual assistance/stateless chat remain separate real contracts.
library;

enum AgentConsentState {
  unknown,
  userRequested,
  locallySelected,
  awaitingServer,
  serverConfirmed,
  revoked,
}

enum AgentAuthority {
  aiSuggestion,
  patientConfirmation,
  clinicianDecision,
  safetyEngine,
  serverAuthorization,
  unknown,
}

enum AgentActionKind {
  recordObservation,
  recordAdherence,
  reviewEvidence,
  medicalTreatmentChange,
  changeDoctorDecision,
  scheduling,
  unknown,
}

enum AgentActionState {
  proposed,
  awaitingConfirmation,
  pending,
  succeeded,
  failed,
  rejected,
  cancelled,
  superseded,
  uncertain,
  unknown,
}

enum AgentContextScope {
  profile,
  observations,
  imageReferences,
  routine,
  experiments,
  personalSkinModel,
}

class AgentConsent {
  AgentConsent({
    required this.state,
    required this.purpose,
    required Set<AgentContextScope> scopes,
    this.receiptId,
  }) : scopes = Set.unmodifiable(scopes) {
    if (purpose.trim().isEmpty ||
        state == AgentConsentState.serverConfirmed &&
            (receiptId == null || receiptId!.isEmpty)) {
      throw const FormatException('Missing authoritative consent receipt');
    }
  }
  final AgentConsentState state;
  final String purpose;
  final Set<AgentContextScope> scopes;
  final String? receiptId;
}

class AgentProposal {
  AgentProposal({
    required this.id,
    required this.owner,
    required this.revision,
    required this.kind,
    required this.authority,
    required this.status,
    required this.fresh,
    required Map<String, String> parameters,
    required this.consent,
    this.requiresConfirmation = true,
    this.conversationId,
    this.provider,
    this.modelVersion,
    this.resultRecordId,
    this.completedAt,
    List<String> evidenceIds = const [],
    this.resolutionRecordId,
  }) : parameters = Map.unmodifiable(parameters),
       evidenceIds = List.unmodifiable(evidenceIds) {
    if (id.isEmpty ||
        owner.isEmpty ||
        revision < 1 ||
        parameters.length > 20 ||
        parameters.entries.any((e) => e.key.isEmpty || e.value.length > 2000) ||
        completedAt != null && !completedAt!.isUtc ||
        status == AgentActionState.succeeded &&
            (resultRecordId == null || completedAt == null)) {
      throw const FormatException('Unverified future action result');
    }
  }
  final String id, owner;
  final int revision;
  final AgentActionKind kind;
  final AgentAuthority authority;
  final AgentActionState status;
  final bool fresh, requiresConfirmation;
  final Map<String, String> parameters;
  final List<String> evidenceIds;
  final AgentConsent consent;
  final String? conversationId,
      provider,
      modelVersion,
      resultRecordId,
      resolutionRecordId;
  final DateTime? completedAt;
  bool sameRevisionContent(AgentProposal other) =>
      id == other.id &&
      owner == other.owner &&
      revision == other.revision &&
      kind == other.kind &&
      authority == other.authority &&
      status == other.status &&
      requiresConfirmation == other.requiresConfirmation &&
      parameters.length == other.parameters.length &&
      parameters.entries.every((e) => other.parameters[e.key] == e.value) &&
      consent.state == other.consent.state &&
      consent.purpose == other.consent.purpose &&
      consent.receiptId == other.consent.receiptId &&
      consent.scopes.length == other.consent.scopes.length &&
      consent.scopes.every(other.consent.scopes.contains) &&
      conversationId == other.conversationId &&
      provider == other.provider &&
      modelVersion == other.modelVersion &&
      resultRecordId == other.resultRecordId &&
      completedAt == other.completedAt &&
      resolutionRecordId == other.resolutionRecordId &&
      evidenceIds.length == other.evidenceIds.length &&
      List.generate(
        evidenceIds.length,
        (i) => evidenceIds[i] == other.evidenceIds[i],
      ).every((same) => same);

  bool get forbiddenMedicalAction => [
    AgentActionKind.medicalTreatmentChange,
    AgentActionKind.changeDoctorDecision,
    AgentActionKind.scheduling,
    AgentActionKind.unknown,
  ].contains(kind);
}

class AgentReadContext {
  const AgentReadContext(this.owner, this.generation);
  final String owner;
  final int generation;
}

class AgentUnsupported implements Exception {
  const AgentUnsupported();
}

abstract interface class AgentRepository {
  Future<AgentProposal?> readProposal(String id, AgentReadContext context);
  Future<void> execute(AgentProposal proposal, AgentReadContext context);
  Future<void> cancel(AgentProposal proposal, AgentReadContext context);
}

class UnsupportedAgentRepository implements AgentRepository {
  const UnsupportedAgentRepository();
  @override
  Future<AgentProposal?> readProposal(
    String id,
    AgentReadContext context,
  ) async => throw const AgentUnsupported();
  @override
  Future<void> execute(
    AgentProposal proposal,
    AgentReadContext context,
  ) async => throw const AgentUnsupported();
  @override
  Future<void> cancel(AgentProposal proposal, AgentReadContext context) async =>
      throw const AgentUnsupported();
}
