import 'dart:convert';
import '../clinical/clinical_models.dart';
import '../integration/contract.dart';
import '../assistance/assistance_models.dart';

const brokerKinds = [
  'request_checkin',
  'propose_followup',
  'propose_routine_adjustment',
  'mark_notification_read',
];
void unavailableModel(Object? v) {
  final model = object(v);
  if (model['schema_version'] != 'agent-model-boundary-1' ||
      model['status'] != 'unavailable' ||
      model['invoked'] != false ||
      model['response'] != null) {
    throw const FormatException('Unsupported Agent model authority');
  }
}

class BrokerCapabilities {
  BrokerCapabilities(Map<String, dynamic> v) {
    unavailableModel(v['model']);
    if (v['schema_version'] != 'agent-platform-1' ||
        v['medical_execution_enabled'] != false ||
        v['autonomous_agent'] != false ||
        v['max_tool_calls'] != 8 ||
        v['context_freshness_seconds'] != 300 ||
        v['action_effect'] !=
            'confirmed_requests_or_allowlisted_nonclinical_action' ||
        (v['actions'] as List)
            .toSet()
            .difference(brokerKinds.toSet())
            .isNotEmpty) {
      throw const FormatException('Unsupported Agent capabilities');
    }
  }
}

class BrokerSession {
  BrokerSession(Map<String, dynamic> v)
    : id = resourceId(v['id']),
      revision = count(v['revision']),
      expires = timestamp(v['expires_at']),
      contextAt = timestamp(v['context_at']),
      digest = text(v['context_digest']),
      scopes = List.unmodifiable((v['scopes'] as List).cast<String>()),
      context = Map.unmodifiable(object(v['context'])),
      toolCalls = count(v['tool_calls']) {
    unavailableModel(v['model']);
    if (revision < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
        !scopes.contains('longitudinal_read') ||
        scopes.any(
          (s) => !['longitudinal_read', 'proposal_actions'].contains(s),
        ) ||
        scopes.toSet().length != scopes.length ||
        toolCalls > 8 ||
        v['max_tool_calls'] != 8 ||
        v['medical_execution_enabled'] != false ||
        v['consistency'] != 'owner_locked_multiple_reads_not_atomic_snapshot' ||
        context['schema_version'] != 'context-1.0') {
      throw const FormatException('Unverified Agent session');
    }
    timestamp(context['built_at']);
    safety = SafetyAssessment.fromApi(object(context['safety']));
    facts = List.unmodifiable(
      assistanceList(
        context['facts'],
        240,
      ).map((f) => AssistanceFact.fromApi(object(f))),
    );
    if (facts.map((f) => f.id).toSet().length != facts.length ||
        jsonEncode(context).length > 48000) {
      throw const FormatException('Invalid context budget');
    }
    unknowns = assistanceTexts(context['unknowns'], 100);
  }
  final String id, digest;
  final int revision, toolCalls;
  final DateTime expires, contextAt;
  final List<String> scopes;
  final Map<String, dynamic> context;
  late final SafetyAssessment safety;
  late final List<AssistanceFact> facts;
  late final List<String> unknowns;
  bool get active => DateTime.now().toUtc().isBefore(expires);
  bool get fresh =>
      active &&
      DateTime.now().toUtc().isBefore(
        contextAt.add(const Duration(minutes: 5)),
      );
}

class BrokerTurn {
  BrokerTurn(Map<String, dynamic> v)
    : id = resourceId(v['id']),
      message = text(v['message']),
      created = timestamp(v['created_at']) {
    if (v['authority'] != 'untrusted_user_text' || message.length > 1000) {
      throw const FormatException('Unverified conversation turn');
    }
  }
  final String id, message;
  final DateTime created;
}

enum BrokerActionStage {
  preview,
  expiredPreview,
  confirmedRequest,
  pendingClinician,
  doctorDecision,
  executed,
  withdrawn,
}

class BrokerAction {
  BrokerAction(Map<String, dynamic> v, {String? doctor})
    : id = resourceId(v['id']),
      kind = text(v['kind']),
      state = text(v['state']),
      revision = count(v['revision']),
      payload = Map.unmodifiable(object(v['payload'])),
      previewed = timestamp(v['previewed_at']),
      validUntil = timestamp(v['preview_valid_until']),
      confirmed = v['confirmed_at'] == null
          ? null
          : timestamp(v['confirmed_at']),
      result = v['result'] == null
          ? null
          : Map.unmodifiable(object(v['result'])) {
    if (!brokerKinds.contains(kind) ||
        !['preview', 'confirmed', 'revoked'].contains(state) ||
        revision < 1 ||
        v['medical_change'] != false ||
        v['requires_explicit_confirmation'] != (state == 'preview') ||
        validUntil != previewed.add(const Duration(minutes: 5))) {
      throw const FormatException('Unverified Agent action');
    }
    if (state == 'revoked') {
      if (payload.isNotEmpty || result != null) {
        throw const FormatException('Revoked memory retained');
      }
      return;
    }
    if (payload['kind'] != kind || text(payload['rationale']).length > 500) {
      throw const FormatException('Unverified proposal');
    }
    if (kind == 'propose_routine_adjustment') {
      resourceId(payload['routine_id']);
      if (count(payload['routine_revision']) < 1) {
        throw const FormatException('Invalid routine revision');
      }
    }
    if (kind == 'mark_notification_read') {
      resourceId(payload['notification_id']);
    }
    if (state == 'preview' &&
        (result != null || confirmed != null || revision != 1)) {
      throw const FormatException('Preview is not executed');
    }
    if (state == 'confirmed') {
      final r = result;
      if (r == null ||
          confirmed == null ||
          revision < 2 ||
          r['request_id'] != id ||
          r['clinical_clearance'] != false ||
          r['medical_resources_modified'] != false ||
          r['clinician_notified'] != false ||
          r['notification_enqueued'] is! bool) {
        throw const FormatException('Unverified confirmed request');
      }
      if (kind == 'mark_notification_read') {
        if (r['status'] != 'executed' ||
            r['tool'] != kind ||
            r['provenance'] != 'user_confirmed_nonclinical_action' ||
            r['notification_id'] != payload['notification_id']) {
          throw const FormatException('Unverified nonclinical execution');
        }
        timestamp(r['read_at']);
      } else {
        if (r['provenance'] != 'user_confirmed_request' ||
            ![
              'self_tracking_request',
              'pending_clinician_review',
              'accepted',
              'rejected',
              'reviewed',
            ].contains(r['status'])) {
          throw const FormatException('Unverified request state');
        }
      }
      if (r['access_id'] != null) {
        resourceId(r['access_id']);
        resourceId(r['doctor_id']);
        timestamp(r['expires_at']);
        timestamp(r['submitted_at']);
        if (r['consent_version'] != 1) {
          throw const FormatException('Unverified routing consent');
        }
      }
      if (doctor != null &&
          (r['doctor_id'] != doctor || r['access_id'] == null)) {
        throw const FormatException('Another clinician request');
      }
    }
  }
  final String id, kind, state;
  final int revision;
  final DateTime previewed, validUntil;
  final DateTime? confirmed;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>? result;
  bool get fresh => DateTime.now().toUtc().isBefore(validUntil);
  BrokerActionStage get stage {
    if (state == 'revoked') return BrokerActionStage.withdrawn;
    if (state == 'preview') {
      return fresh
          ? BrokerActionStage.preview
          : BrokerActionStage.expiredPreview;
    }
    if (kind == 'mark_notification_read') return BrokerActionStage.executed;
    if (result?['doctor_id'] != null) {
      if (['accepted', 'rejected', 'reviewed'].contains(result?['status'])) {
        return BrokerActionStage.doctorDecision;
      }
      if (result?['status'] == 'pending_clinician_review') {
        return BrokerActionStage.pendingClinician;
      }
    }
    return BrokerActionStage.confirmedRequest;
  }

  String get stageLabel => stage.label;
  String get outcome => state == 'preview'
      ? 'Proposed action, awaiting confirmation'
      : state == 'revoked'
      ? 'Withdrawn; memory erased'
      : kind == 'mark_notification_read'
      ? 'Executed nonclinical action: app notification marked read'
      : 'Confirmed request · ${result?['status']}. No treatment, check-in or clinical plan was executed.';
}

extension BrokerActionStageLabel on BrokerActionStage {
  String get label => switch (this) {
    BrokerActionStage.preview => 'Needs your confirmation',
    BrokerActionStage.expiredPreview => 'Preview expired',
    BrokerActionStage.confirmedRequest => 'Confirmed request',
    BrokerActionStage.pendingClinician => 'Awaiting clinician review',
    BrokerActionStage.doctorDecision => 'Clinician decision recorded',
    BrokerActionStage.executed => 'App action executed',
    BrokerActionStage.withdrawn => 'Withdrawn and erased',
  };
}
