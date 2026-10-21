import 'package:flutter_test/flutter_test.dart';
import 'package:transxact_flutter/src/hosted_url.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

void main() {
  test('accepts https', () {
    expect(
      validateHostedUrl('https://pay.transxact.io/cs_1').host,
      'pay.transxact.io',
    );
  });

  test('accepts http on loopback', () {
    expect(validateHostedUrl('http://localhost:3000/x').port, 3000);
  });

  for (final bad in [
    'javascript:alert(1)',
    'http://evil.example/x',
    'not a url',
    'https:///x',
  ]) {
    test('rejects $bad', () {
      expect(() => validateHostedUrl(bad), throwsA(isA<TransxactException>()));
    });
  }

  test('rejects non-strings', () {
    expect(() => validateHostedUrl(42), throwsA(isA<TransxactException>()));
    expect(() => validateHostedUrl(null), throwsA(isA<TransxactException>()));
  });
}
