import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

void main() {
  final createUri = Uri.parse('https://shop.example/api/checkout');

  test('posts payload with an Idempotency-Key and opens hostedUrl', () async {
    late http.Request seen;
    final opened = <Uri>[];
    final transxact = Transxact(
      createSessionUri: createUri,
      headers: {'Authorization': 'Bearer app-token'},
      client: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'id': 'cs_1',
            'hostedUrl': 'https://pay.transxact.io/cs_1',
          }),
          200,
        );
      }),
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
    );

    final created = await transxact.pay(payload: {'orderId': 'o_1'});

    expect(created?.id, 'cs_1');
    expect(opened.single.toString(), 'https://pay.transxact.io/cs_1');
    expect(jsonDecode(seen.body), {'orderId': 'o_1'});
    expect(seen.headers['Idempotency-Key'], isNotEmpty);
    expect(seen.headers['Authorization'], 'Bearer app-token');
  });

  test('uses createSession over a URL and passes the key', () async {
    String? key;
    final transxact = Transxact(
      createSession: (idempotencyKey) async {
        key = idempotencyKey;
        return {'hostedUrl': 'https://pay.transxact.io/cs_2'};
      },
      openUrl: (_) async => true,
    );
    await transxact.pay();
    expect(key, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('ignores a second tap while one is in flight', () async {
    var calls = 0;
    final transxact = Transxact(
      createSession: (_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return {'hostedUrl': 'https://pay.transxact.io/cs_3'};
      },
      openUrl: (_) async => true,
    );
    final first = transxact.pay();
    final second = await transxact.pay();
    await first;
    expect(second, isNull);
    expect(calls, 1);
  });

  test('HTTP errors become httpError with status', () async {
    final transxact = Transxact(
      createSessionUri: createUri,
      client: MockClient((_) async => http.Response('{"error":"x"}', 500)),
      openUrl: (_) async => true,
    );
    await expectLater(
      transxact.pay(),
      throwsA(
        isA<TransxactException>()
            .having((e) => e.code, 'code', TransxactErrorCode.httpError)
            .having((e) => e.status, 'status', 500),
      ),
    );
  });

  test('missing hostedUrl is invalidResponse and does not open', () async {
    var opened = false;
    final transxact = Transxact(
      createSession: (_) async => {'id': 'cs_4'},
      openUrl: (_) async => opened = true,
    );
    await expectLater(
      transxact.pay(),
      throwsA(
        isA<TransxactException>().having(
          (e) => e.code,
          'code',
          TransxactErrorCode.invalidResponse,
        ),
      ),
    );
    expect(opened, isFalse);
  });

  test('no backend configured is configMissing', () async {
    await expectLater(
      Transxact().pay(),
      throwsA(
        isA<TransxactException>().having(
          (e) => e.code,
          'code',
          TransxactErrorCode.configMissing,
        ),
      ),
    );
  });

  test('can pay again after a failure', () async {
    var fail = true;
    final transxact = Transxact(
      createSession: (_) async {
        if (fail) throw StateError('boom');
        return {'hostedUrl': 'https://pay.transxact.io/cs_5'};
      },
      openUrl: (_) async => true,
    );
    await expectLater(transxact.pay(), throwsStateError);
    fail = false;
    expect(await transxact.pay(), isNotNull);
  });
}
