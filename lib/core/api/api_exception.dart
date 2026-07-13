class ApiException implements Exception {
  final String message;
  final Map<String, List<String>>? fieldErrors;

  /// The HTTP status code that produced this error, or `null` when it never
  /// reached the server (no connection, DNS failure, timeout, dropped
  /// socket). Callers use this to tell "the server rejected you" (e.g. 401)
  /// apart from "you're offline", which should be handled very differently.
  final int? statusCode;

  ApiException(this.message, {this.fieldErrors, this.statusCode});

  @override
  String toString() => message;
}
