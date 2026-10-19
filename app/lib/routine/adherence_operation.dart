import '../clinical/clinical_models.dart' show timestamp;
import '../integration/contract.dart';

class AdherencePending extends PendingIntent {
  AdherencePending({
    required this.owner,
    required this.generation,
    required super.body,
  }) : super(
         path: 'routine/adherence',
         attemptPath: 'routine/adherence/attempts',
       );
  final String owner;
  final int generation;
  String? lookupStatus;
}

/// Actual AdherenceAttemptLookup metadata. It is not ConfigurationAttempt:
/// its resource is the immutable report and its revision is the original config.
class AdherenceReceipt {
  AdherenceReceipt._(
    this.status,
    this.resource,
    this.configurationRevision,
    this.original,
  );
  final String status;
  final String? resource;
  final int? configurationRevision;
  final Map<String, dynamic>? original;
  factory AdherenceReceipt.parse(Object? value, AdherencePending op) =>
      AdherenceReceipt.parseIdentity(value, owner: op.owner, body: op.body);

  /// Minimum identity reads need no restored patient note or invented payload.
  factory AdherenceReceipt.parseIdentity(
    Object? value, {
    required String owner,
    Map<String, dynamic>? body,
  }) {
    if (value is! Map ||
        value['schema_version'] != 1 ||
        value['operation'] != 'routine_adherence' ||
        value['owner_id'] != owner ||
        value['actor_id'] != owner ||
        value['attempt_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(value['attempt_id'] as String) ||
        !['unknown', 'committed', 'expired'].contains(value['status'])) {
      throw const FormatException('Invalid adherence attempt scope');
    }
    final status = value['status'] as String;
    if (status == 'unknown') {
      if ([
        'resource_id',
        'configuration_revision',
        'committed_at',
        'expires_at',
        'result',
      ].any((k) => value[k] != null)) {
        throw const FormatException('Unknown is not a recorded report');
      }
      return AdherenceReceipt._(status, null, null, null);
    }
    final resource = resourceId(value['resource_id']),
        revision = value['configuration_revision'];
    final committed = timestamp(value['committed_at']),
        expires = timestamp(value['expires_at']);
    if (resource != value['attempt_id'] ||
        revision is! int ||
        revision < 1 ||
        !expires.isAfter(committed)) {
      throw const FormatException('Invalid adherence receipt identity');
    }
    if (status == 'expired') {
      if (value['result'] != null) {
        throw const FormatException('Expired result unavailable');
      }
      return AdherenceReceipt._(status, resource, revision, null);
    }
    final result = value['result'];
    if (result is! Map<String, dynamic> ||
        result['id'] != resource ||
        result['day_basis'] != 'UTC' ||
        timestamp(result['created_at'], naiveUtc: true) != committed ||
        result['configuration_snapshot'] is! Map ||
        result['configuration_snapshot']['revision'] != revision ||
        body != null &&
            [
              'routine_entry_id',
              'date',
              'slot',
              'status',
              'note',
            ].any((k) => result[k] != body[k])) {
      throw const FormatException('Wrong original adherence report');
    }
    final nested = result['receipt'];
    if (nested is! Map ||
        [
          'schema_version',
          'operation',
          'attempt_id',
          'owner_id',
          'actor_id',
          'resource_id',
          'configuration_revision',
          'status',
        ].any((k) => nested[k] != value[k]) ||
        timestamp(nested['committed_at']) != committed ||
        timestamp(nested['expires_at']) != expires) {
      throw const FormatException('Contradictory adherence receipt');
    }
    return AdherenceReceipt._(status, resource, revision, result);
  }
}
