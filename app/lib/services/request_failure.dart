import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_exception.dart';

enum RequestFailureKind {
  connection,
  timeout,
  session,
  denied,
  rateLimited,
  server,
  rejected,
  invalid,
  unknown,
}

/// Describes the failed request, not a device-wide connectivity diagnosis.
/// No server body, URL, token or exception text is exposed to the patient.
class RequestFailure extends ApiException {
  RequestFailure._(this.kind, String message) : super(message);
  final RequestFailureKind kind;

  factory RequestFailure.http(int status) => switch (status) {
    401 => RequestFailure.session(),
    403 => RequestFailure._(
      RequestFailureKind.denied,
      'Access was denied. Check your account before retrying.',
    ),
    429 => RequestFailure._(
      RequestFailureKind.rateLimited,
      'Too many requests. Wait before trying again.',
    ),
    >= 500 => RequestFailure._(
      RequestFailureKind.server,
      'The service is temporarily unavailable. Try again later.',
    ),
    _ => RequestFailure._(
      RequestFailureKind.rejected,
      'The request could not be confirmed. Refresh before making changes.',
    ),
  };

  factory RequestFailure.session() => RequestFailure._(
    RequestFailureKind.session,
    'Your session ended. Sign in and confirm safety acceptance again.',
  );

  factory RequestFailure.from(Object error) {
    if (error is RequestFailure) return error;
    if (error is TimeoutException) {
      return RequestFailure._(
        RequestFailureKind.timeout,
        'The request timed out. Refresh to confirm the latest information.',
      );
    }
    if (error is SocketException || error is http.ClientException) {
      return RequestFailure._(
        RequestFailureKind.connection,
        'The service could not be reached. Check your connection and retry.',
      );
    }
    if (error is FormatException || error is TypeError) {
      return RequestFailure._(
        RequestFailureKind.invalid,
        'The server response could not be verified. Refresh before making changes.',
      );
    }
    return RequestFailure._(
      RequestFailureKind.unknown,
      'Current information is unavailable. Check your connection and refresh.',
    );
  }
}
