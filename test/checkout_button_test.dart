import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('calls onCreated with the session once the page is opened', (
    tester,
  ) async {
    final opened = <Uri>[];
    CreatedCheckoutSession? created;
    final transxact = Transxact(
      createSession: (_) async => {
        'id': 'cs_1',
        'hostedUrl': 'https://pay.transxact.io/cs_1',
      },
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
    );

    await tester.pumpWidget(
      _app(
        CheckoutButton(
          transxact: transxact,
          payload: const {'orderId': 'o_1'},
          onCreated: (c) => created = c,
          child: const Text('Pay'),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pump();

    expect(created?.id, 'cs_1');
    expect(opened.single.toString(), 'https://pay.transxact.io/cs_1');
  });

  testWidgets('calls onError and not onCreated when creation fails', (
    tester,
  ) async {
    Object? error;
    var created = false;
    final transxact = Transxact(
      createSession: (_) async => throw StateError('offline'),
      openUrl: (_) async => true,
    );

    await tester.pumpWidget(
      _app(
        CheckoutButton(
          transxact: transxact,
          onCreated: (_) => created = true,
          onError: (e) => error = e,
          child: const Text('Pay'),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pump();

    expect(error, isA<StateError>());
    expect(created, isFalse);
    // The button is usable again.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('is disabled and shows a spinner while creating', (tester) async {
    final gate = Completer<Map<String, dynamic>>();
    final transxact = Transxact(
      createSession: (_) => gate.future,
      openUrl: (_) async => true,
    );

    await tester.pumpWidget(
      _app(CheckoutButton(transxact: transxact, child: const Text('Pay'))),
    );
    await tester.tap(find.text('Pay'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    gate.complete({'hostedUrl': 'https://pay.transxact.io/cs_2'});
    await tester.pump();

    expect(find.text('Pay'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
