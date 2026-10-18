import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'contract.dart';

/// Sensitive correlation metadata, never a payload, grant or replay authority.
/// This value is memory-only until a reviewed durable adapter is implemented.
class OperationIdentity {
  OperationIdentity({
    required this.owner,
    required this.role,
    required this.path,
    required this.receiptPath,
    required this.key,
    required this.fingerprint,
    Map<String, Object> scope = const {},
  }) : scope = Map.unmodifiable(scope) {
    resourceId(owner);
    if (!['patient', 'doctor'].contains(role) ||
        !RegExp(r'^[a-f0-9]{48}$').hasMatch(key) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(fingerprint) ||
        [path, receiptPath].any(
          (p) =>
              !RegExp(r'^[A-Za-z0-9_/-]{1,512}$').hasMatch(p) ||
              p.contains('//'),
        ) ||
        scope.keys.any((k) => !scopeFields.contains(k))) {
      throw const FormatException('Invalid operation metadata');
    }
    for (final e in scope.entries) {
      if (e.key.endsWith('revision')) {
        if (e.value is! int ||
            (e.value as int) < 0 ||
            (e.value as int) > 2147483647) {
          throw const FormatException('Invalid original revision');
        }
      } else {
        resourceId(e.value);
      }
    }
  }
  static const scopeFields = {
    'resource_id',
    'access_id',
    'patient_id',
    'doctor_id',
    'job_id',
    'expected_revision',
    'expected_routine_revision',
  };
  final String owner, role, path, receiptPath, key, fingerprint;
  final Map<String, Object> scope;
  static String digest(Map<String, dynamic> body) =>
      sha256.convert(utf8.encode(jsonEncode(body))).toString();
  Map<String, Object> toJson() => {
    'owner': owner,
    'role': role,
    'path': path,
    'receipt_path': receiptPath,
    'key': key,
    'fingerprint': fingerprint,
    'scope': scope,
  };
  factory OperationIdentity.fromJson(Map<String, dynamic> v) {
    if (v.length != 7 || v['scope'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid operation metadata fields');
    }
    return OperationIdentity(
      owner: v['owner'] as String,
      role: v['role'] as String,
      path: v['path'] as String,
      receiptPath: v['receipt_path'] as String,
      key: v['key'] as String,
      fingerprint: v['fingerprint'] as String,
      scope: (v['scope'] as Map<String, dynamic>).cast<String, Object>(),
    );
  }
}
