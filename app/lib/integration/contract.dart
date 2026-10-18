import 'dart:convert';
import 'dart:math';
import '../services/api_exception.dart';

String resourceId(Object? value) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw const FormatException('Invalid resource identity');
  }
  return value;
}

String operationKey() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

class IntegrationFailure extends ApiException {
  IntegrationFailure(this.status)
    : super(switch (status) {
        401 => 'Your session ended. Sign in again.',
        403 =>
          'Access or consent is no longer available. Refresh current permissions.',
        404 => 'This private resource is unavailable.',
        409 || 412 || 428 =>
          'The record or operation changed. Reconcile and refresh before continuing.',
        410 => 'This operation or resource has expired. Check current history.',
        422 => 'The server could not accept these fields. Review your input.',
        _ =>
          'The request could not be confirmed. Check current state before retrying.',
      });
  final int status;
}

class IntegrationResponse {
  const IntegrationResponse(this.data, this.headers, this.status);
  final Object? data;
  final Map<String, String> headers;
  final int status;
}

class PendingIntent {
  PendingIntent({
    required this.path,
    required this.attemptPath,
    required Map<String, dynamic> body,
    this.method = 'POST',
    Map<String, Object> identityScope = const {},
  }) : _scope = Map.unmodifiable(identityScope),
       _body = jsonEncode(body),
       key = operationKey();
  final String path, attemptPath, key, method;
  final String _body;
  final Map<String, Object> _scope;
  Map<String, dynamic> get body =>
      Map.unmodifiable(jsonDecode(_body) as Map<String, dynamic>);

  /// Only identifiers/revisions may cross an authorization-loss boundary.
  Map<String, Object> get recoveryScope => {
    ..._scope,
    for (final e in body.entries)
      if ([
            'access_id',
            'patient_id',
            'doctor_id',
            'job_id',
            'expected_revision',
          ].contains(e.key) &&
          e.value != null)
        e.key: e.value as Object,
  };
  bool uncertain = false;
}

class QuarantinedOperationFailure extends IntegrationFailure {
  QuarantinedOperationFailure() : super(409);
  @override
  String get message =>
      'An original operation remains unresolved after session expiry. No replacement request was sent. Review its original receipt; this device has no durable recovery yet.';
}
