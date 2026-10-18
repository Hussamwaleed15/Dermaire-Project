import '../clinical/clinical_models.dart' show timestamp;
import 'contract.dart';

/// Only the two domains actually sharing backend ConfigurationAttempt. Clinical,
/// messaging, product, Agent and adherence receipts have different contracts.
class ConfigurationPending extends PendingIntent {
  ConfigurationPending({
    required this.domain,
    required this.operation,
    required this.owner,
    required this.generation,
    required super.path,
    required super.body,
    super.method,
    this.resource,
    this.expectedRevision,
    this.expectedRoutineRevision,
  }) : super(
         attemptPath: domain == 'routine'
             ? 'routine/configuration-attempts/$operation'
             : 'experiments/operation-attempts/$operation',
       );
  final String domain, operation, owner;
  final String? resource;
  final int generation;
  final int? expectedRevision, expectedRoutineRevision;
  String? lookupStatus, availability;
  String get lookupPath =>
      '$attemptPath/$key${resource == null ? '' : '?resource_id=${resourceId(resource)}'}';
  @override
  Map<String, Object> get recoveryScope => {
    ...super.recoveryScope,
    'resource_id': ?resource,
    'expected_revision': ?expectedRevision,
    'expected_routine_revision': ?expectedRoutineRevision,
  };
}

class ConfigurationReceipt {
  ConfigurationReceipt._(
    this.status,
    this.availability,
    this.resource,
    this.revision,
    this.original,
  );
  final String status, availability;
  final String? resource;
  final int? revision;
  final Map<String, dynamic>? original;
  factory ConfigurationReceipt.parse(Object? value, ConfigurationPending op) {
    if (value is! Map ||
        value['schema_version'] != 1 ||
        value['owner_id'] != op.owner ||
        value['actor_id'] != op.owner ||
        value['domain'] != op.domain ||
        value['operation'] != op.operation ||
        value['attempt_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(value['attempt_id'] as String) ||
        !['unknown', 'committed', 'expired'].contains(value['status'])) {
      throw const FormatException('Invalid configuration receipt scope');
    }
    final status = value['status'] as String;
    if (status == 'unknown') {
      if ([
            'resource_id',
            'resource_revision',
            'recorded_at',
            'expires_at',
            'result',
          ].any((k) => value[k] != null) ||
          ![null, 'unknown'].contains(value['result_availability'])) {
        throw const FormatException('Unknown is not committed');
      }
      return ConfigurationReceipt._('unknown', 'unknown', null, null, null);
    }
    final id = resourceId(value['resource_id']);
    final revision = value['resource_revision'],
        availability = value['result_availability'];
    final recorded = timestamp(value['recorded_at']),
        expires = timestamp(value['expires_at']);
    final expectedKind = op.operation == 'evaluate' ? 'evaluation' : op.domain;
    if (op.resource != null && id != op.resource ||
        revision is! int ||
        revision < 1 ||
        revision > 2147483647 ||
        op.expectedRevision != null &&
            (op.operation == 'stop'
                ? revision < op.expectedRevision!
                : revision <= op.expectedRevision!) ||
        value['result_kind'] != expectedKind ||
        !expires.isAfter(recorded) ||
        value['snapshot_basis'] != 'original_committed_not_current' ||
        (status == 'expired'
            ? availability != 'expired'
            : !['retained', 'erased'].contains(availability))) {
      throw const FormatException(
        'Inconsistent original configuration receipt',
      );
    }
    if (availability != 'retained') {
      if (value['result'] != null) {
        throw const FormatException('Unavailable original content');
      }
      return ConfigurationReceipt._(
        status,
        availability as String,
        id,
        revision,
        null,
      );
    }
    final result = value['result'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Missing original configuration');
    }
    // Each repository additionally validates its actual DTO and original identity.
    return ConfigurationReceipt._(status, 'retained', id, revision, result);
  }
}
