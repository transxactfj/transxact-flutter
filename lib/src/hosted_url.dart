import 'errors.dart';

Uri validateHostedUrl(Object? value) {
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
      'hostedUrl is not a valid URL: $value',
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
      'hostedUrl must be an https URL: $value',
    );
  }
  return uri;
}
