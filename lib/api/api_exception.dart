class ApiException implements Exception {
  final String message;
  final Map<String, List<String>>? fieldErrors;

  ApiException(this.message, {this.fieldErrors});

  @override
  String toString() => message;
}
