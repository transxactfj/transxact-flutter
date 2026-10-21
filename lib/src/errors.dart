enum TransxactErrorCode { configMissing, httpError, invalidResponse }

class TransxactException implements Exception {
  TransxactException(
    this.code,
    this.message, {
    this.status,
    this.body,
    this.cause,
  });
  final TransxactErrorCode code;
  final String message;
  final int? status;
  final Object? body;
  final Object? cause;
  @override
  String toString() => 'TransxactException(${code.name}): $message';
}
