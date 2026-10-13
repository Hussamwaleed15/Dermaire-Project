class ApiException implements Exception {
  ApiException(this.message, [this.details]);
  final String message;
  final Map<String, dynamic>? details;

  @override
  String toString() => message;
}
