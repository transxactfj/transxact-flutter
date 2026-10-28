import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transxact_flutter/src/hosted_url.dart';
import 'package:transxact_flutter/src/idempotency_key.dart';
import 'package:transxact_flutter/src/version.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

const _fast = PollingOptions(
  interval: Duration(milliseconds: 1),
  maxInterval: Duration(milliseconds: 4),
  timeout: Duration(seconds: 2),
  jitter: 0,
);

final _create = Uri.parse('https://shop.example/api/checkout');
final _retrieve = Uri.parse('https://shop.example/api/session');
const _session = {'id': 'cs_1', 'status': 'succeeded'};

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Transxact _creating(
  MockClientHandler handler, {
  UrlOpener? openUrl,
  List<String>? hosts,
  Duration timeout = const Duration(seconds: 2),
}) => Transxact(
  createSessionUri: _create,
  requestTimeout: timeout,
  retryBaseDelay: const Duration(milliseconds: 1),
  allowedHostedUrlHosts: hosts,
  client: MockClient(handler),
  openUrl: openUrl ?? (_) async => true,
  polling: _fast,
);

Future<void> expectCode(Future<Object?> call, TransxactErrorCode code) async {
  await expectLater(
    call,
    throwsA(isA<TransxactException>().having((e) => e.code, 'code', code)),
  );
}

void main() {
  group('validateHostedUrl', () {
    for (final bad in [
      'https://pay.transxact.io@evil.example/x',
      'https://user:pw@pay.transxact.io/x',
      'file:///etc/passwd',
      'ftp://pay.transxact.io/x',
      'http://pay.transxact.io/x',
      'http://localhost.evil.example/x',
      'javascript:alert(1)',
      '',
    ]) {
      test('rejects "$bad"', () {
        expect(
          () => validateHostedUrl(bad),
          throwsA(isA<TransxactException>()),
        );
      });
    }

    for (final good in [
      'https://pay.transxact.io/c/cs_1',
      'HTTPS://PAY.TRANSXACT.IO/c/cs_1',
      'http://localhost:3000/c',
      'http://[::1]:3000/c',
      'http://10.0.2.2:3000/c',
      'http://shop.localhost/c',
    ]) {
      test(
        'accepts "$good"',
        () => expect(validateHostedUrl(good), isA<Uri>()),
      );
    }

    test('allowlist is exact', () {
      expect(
        validateHostedUrl(
          'https://pay.transxact.io/c',
          allowedHosts: ['PAY.transxact.io'],
        ).host,
        'pay.transxact.io',
      );
      for (final other in [
        'https://evil.example/c',
        'https://pay.transxact.io.evil.example/c',
        'https://sub.pay.transxact.io/c',
      ]) {
        expect(
          () => validateHostedUrl(other, allowedHosts: ['pay.transxact.io']),
          throwsA(isA<TransxactException>()),
        );
      }
    });

    test('the error does not echo the URL', () {
      try {
        validateHostedUrl('http://evil.example/c?token=secret');
        fail('should throw');
      } on TransxactException catch (e) {
        expect(e.message, isNot(contains('secret')));
        expect(e.message, isNot(contains('evil.example')));
      }
    });
  });

  group('pay', () {
    test('rejects a host outside allowedHostedUrlHosts without opening', () {
      var opened = false;
      final transxact = _creating(
        (_) async => _json({'hostedUrl': 'https://evil.example/c'}),
        hosts: ['pay.transxact.io'],
        openUrl: (_) async => opened = true,
      );
      return expectCode(
        transxact.pay(),
        TransxactErrorCode.invalidResponse,
      ).then((_) => expect(opened, isFalse));
    });

    test('openUrl returning false is launchFailed', () {
      final transxact = _creating(
        (_) async => _json({'hostedUrl': 'https://pay.transxact.io/c'}),
        openUrl: (_) async => false,
      );
      return expectCode(transxact.pay(), TransxactErrorCode.launchFailed);
    });

    test('reports the idempotency key and accepts a caller one', () async {
      late String sent;
      final transxact = _creating((request) async {
        sent = request.headers['Idempotency-Key']!;
        return _json({'hostedUrl': 'https://pay.transxact.io/c', 'id': 'cs_1'});
      });
      final created = await transxact.pay(idempotencyKey: 'order-7');
      expect(sent, 'order-7');
      expect(created?.idempotencyKey, 'order-7');
    });

    test('sends the SDK version', () async {
      late http.Request seen;
      final transxact = _creating((request) async {
        seen = request;
        return _json({'hostedUrl': 'https://pay.transxact.io/c'});
      });
      await transxact.pay();
      expect(seen.headers['X-Transxact-SDK'], 'transxact_flutter/$sdkVersion');
    });

    test('a network failure is network, with the cause', () async {
      final transxact = _creating(
        (_) async => throw const SocketException('x'),
      );
      await expectLater(
        transxact.pay(),
        throwsA(
          isA<TransxactException>()
              .having((e) => e.code, 'code', TransxactErrorCode.network)
              .having((e) => e.cause, 'cause', isNotNull),
        ),
      );
    });

    test('a request that never answers is timeout', () {
      final never = Completer<http.Response>();
      final transxact = _creating(
        (_) => never.future,
        timeout: const Duration(milliseconds: 20),
      );
      return expectCode(transxact.pay(), TransxactErrorCode.timeout);
    });

    test('a callback that never answers is timeout', () {
      final transxact = Transxact(
        createSession: (_) => Completer<Map<String, dynamic>>().future,
        requestTimeout: const Duration(milliseconds: 20),
      );
      return expectCode(transxact.pay(), TransxactErrorCode.timeout);
    });

    test('retries a 503 with the same key, then succeeds', () async {
      final keys = <String>[];
      final transxact = _creating((request) async {
        keys.add(request.headers['Idempotency-Key']!);
        return keys.length < 3
            ? _json({
                'error': {'code': 'x'},
              }, 503)
            : _json({'hostedUrl': 'https://pay.transxact.io/c'});
      });
      await transxact.pay();
      expect(keys, hasLength(3));
      expect(keys.toSet(), hasLength(1));
    });

    test('gives up after maxRetries', () async {
      var calls = 0;
      final transxact = _creating((_) async {
        calls++;
        return _json({}, 503);
      });
      await expectCode(transxact.pay(), TransxactErrorCode.httpError);
      expect(calls, 3); // first try + 2 retries
    });

    test('a 409 is not retried and carries the api code', () async {
      var calls = 0;
      final transxact = _creating((_) async {
        calls++;
        return http.Response(
          jsonEncode({
            'error': {'code': 'idempotency_key_reused', 'message': 'm'},
          }),
          409,
          headers: {'x-request-id': 'req_1'},
        );
      });
      await expectLater(
        transxact.pay(),
        throwsA(
          isA<TransxactException>()
              .having((e) => e.apiCode, 'apiCode', 'idempotency_key_reused')
              .having((e) => e.requestId, 'requestId', 'req_1')
              .having((e) => e.status, 'status', 409),
        ),
      );
      expect(calls, 1);
    });

    test('errors name the path only', () async {
      final transxact = Transxact(
        createSessionUri: Uri.parse(
          'https://user:pw@shop.example/api/checkout?token=secret',
        ),
        maxRetries: 0,
        client: MockClient((_) async => _json({}, 500)),
      );
      try {
        await transxact.pay();
        fail('should throw');
      } on TransxactException catch (e) {
        expect(e.message, contains('/api/checkout'));
        expect(e.message, isNot(contains('secret')));
        expect(e.message, isNot(contains('shop.example')));
        expect(e.message, isNot(contains('pw')));
      }
    });

    test('non-JSON and non-object 200s are invalidResponse', () async {
      for (final body in ['<html>', '[1]', '"x"']) {
        final transxact = _creating((_) async => http.Response(body, 200));
        await expectCode(transxact.pay(), TransxactErrorCode.invalidResponse);
      }
    });

    test(
      'refuses an amount, currency, quote or price in the payload',
      () async {
        var calls = 0;
        final transxact = _creating((_) async {
          calls++;
          return _json({'hostedUrl': 'https://pay.transxact.io/c'});
        });
        for (final payload in [
          {'amount': 100},
          {'Amount_Cents': 100},
          {
            'cart': [
              {'price': 1},
            ],
          },
          {'currency': 'FJD'},
          {'quote': {}},
        ]) {
          await expectCode(
            transxact.pay(payload: payload),
            TransxactErrorCode.invalidRequest,
          );
        }
        expect(calls, 0);
        await transxact.pay(payload: {'orderId': 'o_1', 'priceId': 'p'});
      },
    );

    test('refuses a secret key anywhere it could leak', () {
      expect(
        () => Transxact(headers: {'Authorization': 'Bearer sk_live_abc'}),
        throwsA(isA<TransxactException>()),
      );
      expect(
        () => Transxact(
          retrieveSessionUri: Uri.parse('https://x.example/?k=sk_test_a'),
        ),
        throwsA(isA<TransxactException>()),
      );
      final transxact = _creating((_) async => _json({}));
      return expectCode(
        transxact.pay(payload: {'note': 'sk_test_abc'}),
        TransxactErrorCode.invalidRequest,
      );
    });
  });

  group('fetchSession / watchSession', () {
    test('rejects a malformed session id before calling the backend', () async {
      var calls = 0;
      final transxact = Transxact(
        retrieveSessionUri: _retrieve,
        client: MockClient((_) async {
          calls++;
          return _json(_session);
        }),
      );
      for (final id in ['', 'cs 1', 'cs_1&x=y', '../a']) {
        await expectCode(
          transxact.fetchSession(id),
          TransxactErrorCode.invalidRequest,
        );
      }
      expect(calls, 0);
    });

    test('a different session id in the answer is invalidResponse', () {
      final transxact = Transxact(
        retrieveSession: (_) async => {'id': 'cs_other', 'status': 'succeeded'},
      );
      return expectCode(
        transxact.fetchSession('cs_1'),
        TransxactErrorCode.invalidResponse,
      );
    });

    test('retries a transient failure and still settles', () async {
      var calls = 0;
      final transxact = Transxact(
        polling: _fast,
        retrieveSessionUri: _retrieve,
        client: MockClient((_) async {
          calls++;
          if (calls == 1) throw const SocketException('offline');
          if (calls == 2) return _json({}, 503);
          return _json(_session);
        }),
      );
      final updates = await transxact.watchSession('cs_1').toList();
      expect(updates.last.state, CheckoutReturnState.settled);
      expect(calls, 3);
    });

    test('gives up after polling.retries failures in a row', () async {
      var calls = 0;
      final transxact = Transxact(
        polling: const PollingOptions(
          interval: Duration(milliseconds: 1),
          maxInterval: Duration(milliseconds: 2),
          timeout: Duration(seconds: 2),
          retries: 2,
          jitter: 0,
        ),
        retrieveSessionUri: _retrieve,
        client: MockClient((_) async {
          calls++;
          return _json({}, 502);
        }),
      );
      final updates = await transxact.watchSession('cs_1').toList();
      expect(updates.last.state, CheckoutReturnState.error);
      expect(calls, 3);
    });

    test('does not retry a 404', () async {
      var calls = 0;
      final transxact = Transxact(
        polling: _fast,
        retrieveSessionUri: _retrieve,
        client: MockClient((_) async {
          calls++;
          return _json({
            'error': {'code': 'not_found'},
          }, 404);
        }),
      );
      final updates = await transxact.watchSession('cs_1').toList();
      expect(updates.last.state, CheckoutReturnState.error);
      expect((updates.last.error as TransxactException).apiCode, 'not_found');
      expect(calls, 1);
    });

    test('honours Retry-After on a 429', () async {
      var calls = 0;
      final stamps = <DateTime>[];
      final transxact = Transxact(
        polling: _fast,
        retrieveSessionUri: _retrieve,
        client: MockClient((_) async {
          calls++;
          stamps.add(DateTime.now());
          return calls == 1
              ? http.Response('{}', 429, headers: {'retry-after': '1'})
              : _json(_session);
        }),
      );
      await transxact.watchSession('cs_1').toList();
      expect(
        stamps[1].difference(stamps[0]),
        greaterThanOrEqualTo(const Duration(milliseconds: 900)),
      );
    });

    test('cancelling stops polling for good', () async {
      var calls = 0;
      final transxact = Transxact(
        polling: const PollingOptions(
          interval: Duration(milliseconds: 5),
          maxInterval: Duration(milliseconds: 5),
          timeout: Duration(seconds: 5),
        ),
        retrieveSession: (_) async {
          calls++;
          return {'id': 'cs_1', 'status': 'pending'};
        },
      );
      final sub = transxact.watchSession('cs_1').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await sub.cancel();
      final seen = calls;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(calls, seen);
    });
  });

  group('misc', () {
    test('close releases an owned client without error', () {
      Transxact(retrieveSessionUri: _retrieve).close();
    });

    test('invalid options are rejected', () {
      expect(
        () => Transxact(requestTimeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => Transxact(polling: const PollingOptions(interval: Duration.zero)),
        throwsArgumentError,
      );
      expect(
        () => Transxact(
          polling: const PollingOptions(
            interval: Duration(seconds: 5),
            maxInterval: Duration(seconds: 1),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('onLog gets path and status only', () async {
      final lines = <String>[];
      final transxact = Transxact(
        retrieveSessionUri: Uri.parse('https://shop.example/api/session?k=v'),
        headers: {'Authorization': 'Bearer t'},
        onLog: lines.add,
        client: MockClient((_) async => _json(_session)),
      );
      await transxact.fetchSession('cs_1');
      expect(lines, ['GET /api/session -> 200']);
    });

    test('newIdempotencyKey is a v4 UUID and unique', () {
      final keys = {for (var i = 0; i < 200; i++) newIdempotencyKey()};
      expect(keys, hasLength(200));
      for (final key in keys) {
        expect(
          key,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      }
    });

    test('sessionIdFromReturnUri reads a well-formed id only', () {
      expect(
        sessionIdFromReturnUri(
          Uri.parse('https://shop.example/r?session_id=cs_ab12'),
        ),
        'cs_ab12',
      );
      expect(
        sessionIdFromReturnUri(Uri.parse('https://shop.example/r')),
        isNull,
      );
      expect(
        sessionIdFromReturnUri(
          Uri.parse('https://shop.example/r?session_id=a%20b'),
        ),
        isNull,
      );
    });

    test('sdkVersion matches pubspec.yaml', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(sdkVersion, version);
    });
  });
}
