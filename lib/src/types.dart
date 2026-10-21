enum CheckoutSessionStatus { pending, succeeded, failed, cancelled }

class CreatedCheckoutSession {
  const CreatedCheckoutSession({required this.hostedUrl, this.id});
  final String hostedUrl;
  final String? id;
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
typedef CreateSession = Future<Map<String, dynamic>> Function(
  String idempotencyKey,
);

//Your functuon that asks the Merchant backend for a session status.
typedef RetrieveSession = Future<Map<String, dynamic>> Function(
  String sessionId,
);

class PollingOptions {
  const PollingOptions({
    this.interval = const Duration(milliseconds: 1500),
    this.maxInterval = const Duration(seconds: 8),
    this.timeout = const Duration(seconds: 60),
  });
  final Duration interval, maxInterval, timeout;
}

/// What Transxact.watchSession is doing. The payment itself is `session.status`.
enum CheckoutReturnState { loading, polling, settled, timedOut, error }

class CheckoutReturnUpdate {
  const CheckoutReturnUpdate(this.state, {this.session, this.error});
  final CheckoutReturnState state;
  final CheckoutSession? session;
  final Object? error;
}
