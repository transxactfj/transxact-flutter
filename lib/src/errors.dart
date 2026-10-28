/// Why the SDK gave up. Branch on this (and [TransxactException.apiCode]),
/// never on the message.
enum TransxactErrorCode {
  /// No way to reach the Merchant backend was configured.
  configMissing,

  /// The Merchant backend answered with a non-2xx status.
  httpError,

  /// The Merchant backend's answer was not what the SDK expects.
  invalidResponse,

  /// The Merchant backend did not answer within `requestTimeout`.
  timeout,

  /// The request never got an answer (offline, DNS, TLS, reset).
  network,

  /// The request was cancelled by the caller.
  cancelled,

  /// The Customer's checkout page could not be opened.
  launchFailed,

  /// The SDK refused to send something that breaks its rules: a secret key,
  /// an amount, or a malformed session id.
  invalidRequest,
}

class TransxactException implements Exception {
  TransxactException(
    this.code,
    this.message, {
    this.status,
    this.body,
    this.cause,
    this.apiCode,
    this.requestId,
    this.retryAfter,
  });

  final TransxactErrorCode code;

  /// For developers and logs. Never contains the host, query string or
  /// credentials of the request. Do not show it to the Customer.
  final String message;

  /// The HTTP status, for [TransxactErrorCode.httpError].
  final int? status;

  /// The Merchant backend's response body. It may be sensitive: do not show it
  /// to the Customer.
  final Object? body;
  final Object? cause;

  /// The Merchant backend's own `{ "error": { "code" } }` string, if it sent
  /// one.
  final String? apiCode;

  /// The `x-request-id` response header, if the backend sent one.
  final String? requestId;

  /// The `Retry-After` response header, in seconds, if the backend sent one.
  final Duration? retryAfter;

  @override
  String toString() =>
      'TransxactException(${code.name}${status == null ? '' : ' $status'}'
      '${apiCode == null ? '' : ' $apiCode'}): $message';
}
