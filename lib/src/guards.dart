import 'errors.dart';

final _secretKey = RegExp(r'sk_(live|test)_', caseSensitive: false);
final _sessionId = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

// Keys that would let the app say what something costs. Only the Merchant
// backend decides the price.
const _amountKeys = {'amount', 'amountcents', 'currency', 'quote', 'price'};

/// The path of [uri] alone: no host, credentials or query string, which can
/// carry a `session_id`.
String describeUrl(Uri uri) => uri.path.isEmpty ? '/' : uri.path;

/// Throws if [value] contains a Transxact secret key. They belong on the
/// Merchant backend, never in an app binary.
void assertNoSecretKey(String where, Object? value) {
  if (value != null && _secretKey.hasMatch(value.toString())) {
    throw TransxactException(
      TransxactErrorCode.invalidRequest,
      'Refusing to send a Transxact secret key ($where). Secret keys belong '
      'on the Merchant backend, never in the app.',
    );
  }
}

/// Throws if [payload] tries to set an amount, currency or quote.
void assertNoAmount(Object? payload) {
  if (payload is Map) {
    for (final entry in payload.entries) {
      final key = entry.key.toString().toLowerCase().replaceAll(
        RegExp('[^a-z]'),
        '',
      );
      if (_amountKeys.contains(key)) {
        throw TransxactException(
          TransxactErrorCode.invalidRequest,
          'Refusing to send "${entry.key}" from the app. Only the Merchant '
          'backend decides the price.',
        );
      }
      assertNoAmount(entry.value);
    }
  } else if (payload is Iterable) {
    for (final item in payload) {
      assertNoAmount(item);
    }
  }
}

/// Throws unless [sessionId] looks like a Checkout Session id.
void assertSessionId(String sessionId) {
  if (!_sessionId.hasMatch(sessionId)) {
    throw TransxactException(
      TransxactErrorCode.invalidRequest,
      'sessionId is empty or has characters a Checkout Session id never has.',
    );
  }
}

/// The `session_id` the Transxact checkout appended to a return link, or null
/// if there is none or it is malformed.
///
/// The return link is a hint only: confirm the outcome with
/// `Transxact.watchSession`.
String? sessionIdFromReturnUri(Uri uri) {
  final id = uri.queryParameters['session_id'];
  return id != null && _sessionId.hasMatch(id) ? id : null;
}
