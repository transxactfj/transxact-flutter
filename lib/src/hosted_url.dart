import 'errors.dart';

/// Checks a `hostedUrl` before it is opened: https, or http on loopback, with
/// no credentials in it. [allowedHosts], when given, is an exact-hostname
/// allowlist.
Uri validateHostedUrl(Object? value, {Iterable<String>? allowedHosts}) {
  if (value is! String) {
    throw TransxactException(
      TransxactErrorCode.invalidResponse,
      'Response has no hostedUrl string.',
    );
  }
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) {
    throw TransxactException(
      TransxactErrorCode.invalidResponse,
      'hostedUrl is not a valid URL.',
    );
  }
  if (uri.userInfo.isNotEmpty) {
    throw TransxactException(
      TransxactErrorCode.invalidResponse,
      'hostedUrl must not carry credentials.',
    );
  }
  final loopback =
      {
        'localhost',
        '127.0.0.1',
        '[::1]',
        '::1',
        '10.0.2.2',
      }.contains(uri.host) ||
      uri.host.endsWith('.localhost');
  if (uri.scheme != 'https' && !(uri.scheme == 'http' && loopback)) {
    throw TransxactException(
      TransxactErrorCode.invalidResponse,
      'hostedUrl must be an https URL.',
    );
  }
  if (allowedHosts != null &&
      !allowedHosts.map((h) => h.toLowerCase()).contains(uri.host)) {
    throw TransxactException(
      TransxactErrorCode.invalidResponse,
      'hostedUrl host "${uri.host}" is not in allowedHostedUrlHosts.',
    );
  }
  return uri;
}
