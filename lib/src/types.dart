enum CheckoutSessionStatus { pending, succeeded, failed, cancelled }

class CreatedCheckoutSession {
  const CreatedCheckoutSession({
    required this.hostedUrl,
    this.id,
    this.idempotencyKey,
  });
  final String hostedUrl;
  final String? id;

  /// The `Idempotency-Key` this attempt used. Keep it to retry the same
  /// attempt (`Transxact.pay(idempotencyKey:)`) and get the same session back.
  final String? idempotencyKey;
}

class CheckoutSession {
  const CheckoutSession({
    required this.id,
    required this.status,
    this.raw = const {},
  });
  final String id;
  final CheckoutSessionStatus status;
  final Map<String, dynamic> raw; // whatever else your backend returned
}

// Your function that asks the Merchant to create a session.
typedef CreateSession =
    Future<Map<String, dynamic>> Function(String idempotencyKey);

// Your function that asks the Merchant backend for a session status.
typedef RetrieveSession =
    Future<Map<String, dynamic>> Function(String sessionId);

/// Receives one redacted line per request to the Merchant backend: method,
/// path and outcome. Never headers, bodies or query strings.
typedef TransxactLogger = void Function(String message);

class PollingOptions {
  const PollingOptions({
    this.interval = const Duration(milliseconds: 1500),
    this.maxInterval = const Duration(seconds: 8),
    this.timeout = const Duration(seconds: 60),
    this.retries = 3,
    this.jitter = 0.2,
  });
  final Duration interval, maxInterval, timeout;

  /// How many times in a row a lookup may fail for a transient reason
  /// (timeout, network, HTTP 408/429/5xx) before polling gives up.
  final int retries;

  /// Retry waits vary by up to this fraction either way (0 turns it off).
  final double jitter;
}

/// What Transxact.watchSession is doing. The payment itself is `session.status`.
enum CheckoutReturnState { loading, polling, settled, timedOut, error }

class CheckoutReturnUpdate {
  const CheckoutReturnUpdate(this.state, {this.session, this.error});
  final CheckoutReturnState state;
  final CheckoutSession? session;
  final Object? error;
}
