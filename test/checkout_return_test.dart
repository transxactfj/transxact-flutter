import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

const _fast = PollingOptions(
  interval: Duration(milliseconds: 1),
  maxInterval: Duration(milliseconds: 4),
  timeout: Duration(milliseconds: 50),
);

Transxact _withStatuses(List<String> statuses) {
  var i = 0;
  return Transxact(
    polling: _fast,
    retrieveSession: (id) async {
      final status = statuses[i < statuses.length ? i : statuses.length - 1];
      i++;
      return {'id': id, 'status': status};
    },
  );
}

void main() {
  test('polls until the session settles', () async {
    final updates = await _withStatuses([
      'pending',
      'pending',
      'succeeded',
    ]).watchSession('cs_1').toList();

    expect(updates.map((u) => u.state), [
      CheckoutReturnState.loading,
      CheckoutReturnState.polling,
      CheckoutReturnState.polling,
      CheckoutReturnState.settled,
    ]);
    expect(updates.last.session?.status, CheckoutSessionStatus.succeeded);
  });

  test('failed is a settled payment, not an error state', () async {
    final updates = await _withStatuses([
      'failed',
    ]).watchSession('cs_1').toList();
    expect(updates.last.state, CheckoutReturnState.settled);
    expect(updates.last.session?.status, CheckoutSessionStatus.failed);
  });

  test('times out while still pending', () async {
    final updates = await _withStatuses([
      'pending',
    ]).watchSession('cs_1').toList();
    expect(updates.last.state, CheckoutReturnState.timedOut);
    expect(updates.last.session?.status, CheckoutSessionStatus.pending);
  });

  test('a lookup failure is an error state', () async {
    final transxact = Transxact(
      polling: _fast,
      retrieveSession: (_) async => throw StateError('offline'),
    );
    final updates = await transxact.watchSession('cs_1').toList();
    expect(updates.last.state, CheckoutReturnState.error);
    expect(updates.last.error, isA<StateError>());
  });

  test('an unknown status is invalidResponse', () async {
    final updates = await _withStatuses([
      'weird',
    ]).watchSession('cs_1').toList();
    expect(updates.last.state, CheckoutReturnState.error);
    expect(updates.last.error, isA<TransxactException>());
  });

  test('retrieveSessionUri appends session_id and sends headers', () async {
    late http.Request seen;
    final transxact = Transxact(
      retrieveSessionUri: Uri.parse('https://shop.example/api/checkout?x=1'),
      headers: {'Authorization': 'Bearer app-token'},
      client: MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode({'status': 'succeeded'}), 200);
      }),
    );
    final session = await transxact.fetchSession('cs_9');
    expect(seen.url.queryParameters, {'x': '1', 'session_id': 'cs_9'});
    expect(seen.headers['Authorization'], 'Bearer app-token');
    expect(session.id, 'cs_9');
    expect(session.status, CheckoutSessionStatus.succeeded);
  });
}
