import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

const _fast = PollingOptions(
  interval: Duration(milliseconds: 10),
  maxInterval: Duration(milliseconds: 20),
  timeout: Duration(seconds: 5),
);

Widget _app(Transxact transxact, {String sessionId = 'cs_1'}) {
  return MaterialApp(
    home: CheckoutReturnBuilder(
      transxact: transxact,
      sessionId: sessionId,
      builder: (context, update, refresh) {
        switch (update.state) {
          case CheckoutReturnState.settled:
            return Text('settled:${update.session!.status.name}');
          case CheckoutReturnState.error:
            return TextButton(onPressed: refresh, child: const Text('retry'));
          case CheckoutReturnState.timedOut:
            return const Text('timed out');
          case CheckoutReturnState.polling:
            return const Text('polling');
          case CheckoutReturnState.loading:
            return const Text('loading');
        }
      },
    ),
  );
}

Future<void> _pumpFor(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  testWidgets('starts as loading, then shows the settled payment', (
    tester,
  ) async {
    final transxact = Transxact(
      polling: _fast,
      retrieveSession: (id) async => {'id': id, 'status': 'succeeded'},
    );

    await tester.pumpWidget(_app(transxact));
    expect(find.text('loading'), findsOneWidget);

    await _pumpFor(tester, 3);
    expect(find.text('settled:succeeded'), findsOneWidget);
  });

  testWidgets('polls while pending, then settles', (tester) async {
    var lookups = 0;
    final transxact = Transxact(
      polling: _fast,
      retrieveSession: (id) async {
        lookups++;
        return {'id': id, 'status': lookups < 3 ? 'pending' : 'failed'};
      },
    );

    await tester.pumpWidget(_app(transxact));
    await tester.pump();
    expect(find.text('polling'), findsOneWidget);

    await _pumpFor(tester, 10);
    expect(find.text('settled:failed'), findsOneWidget);
    expect(lookups, 3);
  });

  testWidgets('refresh restarts the lookup after an error', (tester) async {
    var lookups = 0;
    final transxact = Transxact(
      polling: _fast,
      retrieveSession: (id) async {
        lookups++;
        if (lookups == 1) throw StateError('offline');
        return {'id': id, 'status': 'succeeded'};
      },
    );

    await tester.pumpWidget(_app(transxact));
    await _pumpFor(tester, 3);
    expect(find.text('retry'), findsOneWidget);

    await tester.tap(find.text('retry'));
    await _pumpFor(tester, 3);
    expect(find.text('settled:succeeded'), findsOneWidget);
    expect(lookups, 2);
  });

  testWidgets('a new sessionId restarts the lookup', (tester) async {
    final asked = <String>[];
    final transxact = Transxact(
      polling: _fast,
      retrieveSession: (id) async {
        asked.add(id);
        return {'id': id, 'status': 'succeeded'};
      },
    );

    await tester.pumpWidget(_app(transxact, sessionId: 'cs_1'));
    await _pumpFor(tester, 3);
    await tester.pumpWidget(_app(transxact, sessionId: 'cs_2'));
    await _pumpFor(tester, 3);

    expect(asked, ['cs_1', 'cs_2']);
  });

  testWidgets('stops polling when removed', (tester) async {
    var lookups = 0;
    final transxact = Transxact(
      polling: _fast,
      retrieveSession: (id) async {
        lookups++;
        return {'id': id, 'status': 'pending'};
      },
    );

    await tester.pumpWidget(_app(transxact));
    await _pumpFor(tester, 2);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final seen = lookups;
    await _pumpFor(tester, 10);

    expect(lookups, seen);
  });
}
