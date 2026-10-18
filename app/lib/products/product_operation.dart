import '../clinical/clinical_models.dart' show timestamp;
import '../integration/contract.dart';
import 'product.dart';

/// Exact original request kept only in this authenticated session. Disk recovery
/// must not persist this payload in plaintext.
class ProductPendingOperation extends PendingIntent {
  ProductPendingOperation({
    required this.kind,
    required this.owner,
    required this.generation,
    required Map<String, dynamic> payload,
    this.resource,
    this.expectedRevision,
  }) : super(
         path: resource == null
             ? 'products'
             : 'products/${resourceId(resource)}',
         attemptPath: kind == 'create'
             ? 'products/attempts'
             : 'products/${resourceId(resource)}/operation-attempts/$kind',
         method: kind == 'create'
             ? 'POST'
             : kind == 'patch'
             ? 'PATCH'
             : 'DELETE',
         body: payload,
       );
  final String kind, owner;
  final String? resource;
  final int generation;
  final int? expectedRevision;
  String? lookupStatus, availability;
  @override
  Map<String, Object> get recoveryScope => {
    ...super.recoveryScope,
    'resource_id': ?resource,
    'expected_revision': ?expectedRevision,
  };
}

class ProductOperationReceipt {
  ProductOperationReceipt._(
    this.status,
    this.availability,
    this.resource,
    this.revision,
    this.original,
  );
  final String status, availability;
  final String? resource;
  final int? revision;
  final Product? original;
  factory ProductOperationReceipt.parse(
    Object? value,
    ProductPendingOperation op,
  ) => ProductOperationReceipt.parseIdentity(
    value,
    owner: op.owner,
    kind: op.kind,
    resource: op.resource,
    expectedRevision: op.expectedRevision,
  );

  /// Read-only recovery does not reconstruct a payload or mint an operation key.
  factory ProductOperationReceipt.parseIdentity(
    Object? value, {
    required String owner,
    required String kind,
    String? resource,
    int? expectedRevision,
  }) {
    resourceId(owner);
    if (!['create', 'patch', 'delete'].contains(kind)) {
      throw const FormatException('Unsupported product receipt operation');
    }
    if (value is! Map ||
        value['schema_version'] != 1 ||
        value['owner_id'] != owner ||
        value['actor_id'] != owner ||
        value['operation'] != 'product_$kind' ||
        value['attempt_id'] is! String ||
        !RegExp(
          r'^[A-Za-z0-9_-]{1,128}$',
        ).hasMatch(value['attempt_id'] as String) ||
        !['unknown', 'committed', 'expired'].contains(value['status'])) {
      throw const FormatException('Invalid product operation receipt');
    }
    final status = value['status'] as String;
    final availability = value['result_availability'];
    if (status == 'unknown') {
      if (availability != 'unknown' ||
          [
            'resource_id',
            'resource_revision',
            'recorded_at',
            'expires_at',
            'result',
          ].any((k) => value[k] != null)) {
        throw const FormatException('Unknown cannot assert commitment');
      }
      return ProductOperationReceipt._(status, 'unknown', null, null, null);
    }
    final id = resourceId(value['resource_id']);
    final revision = value['resource_revision'];
    final recorded = timestamp(value['recorded_at']);
    final expires = timestamp(value['expires_at']);
    if (revision is! int ||
        revision < 1 ||
        revision > 2147483647 ||
        kind == 'create' && revision != 1 ||
        expectedRevision != null && revision <= expectedRevision ||
        resource != null && id != resource ||
        !expires.isAfter(recorded) ||
        (status == 'expired'
            ? availability != 'expired'
            : !['retained', 'erased'].contains(availability))) {
      throw const FormatException('Inconsistent product receipt scope');
    }
    if (availability != 'retained') {
      if (value['result'] != null) {
        throw const FormatException('Unavailable receipt content');
      }
      return ProductOperationReceipt._(
        status,
        availability as String,
        id,
        revision,
        null,
      );
    }
    final result = value['result'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Missing original product result');
    }
    if (kind == 'delete') {
      if (result['deleted'] != true ||
          result['id'] != id ||
          result['revision'] != revision) {
        throw const FormatException('Invalid deletion tombstone');
      }
      return ProductOperationReceipt._(status, 'retained', id, revision, null);
    }
    final original = Product.fromApi(result);
    if (original.id != id ||
        original.owner != owner ||
        original.serverRevision != revision) {
      throw const FormatException('Wrong original product result');
    }
    return ProductOperationReceipt._(
      status,
      'retained',
      id,
      revision,
      original,
    );
  }
}
