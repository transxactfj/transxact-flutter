import 'package:flutter/material.dart';
import 'package:transxact_flutter/transxact_flutter.dart';

/// Set with `--dart-define=BACKEND_URL=http://10.0.2.2:8787/api/checkout` to use a real Merchant backend
/// (see backend/server.mjs). Without it the app uses an in-memory fake, so it runs with no setup.
const backendUrl = String.fromEnvironment('BACKEND_URL');

Transxact buildTransxact() {
  if (backendUrl.isNotEmpty) {
    return Transxact(
      createSessionUri: Uri.parse(backendUrl),
      retrieveSessionUri: Uri.parse(backendUrl),
    );
  }
  // Fake Merchant backend: the session stays pending for two lookups, then succeeds.
  var lookups = 0;
  return Transxact(
    polling: const PollingOptions(interval: Duration(seconds: 1)),
    createSession: (idempotencyKey) async {
      lookups = 0;
      return {'id': 'cs_demo', 'hostedUrl': 'https://transxact.io'};
    },
    retrieveSession: (sessionId) async {
      lookups++;
      return {'id': sessionId, 'status': lookups > 2 ? 'succeeded' : 'pending'};
    },
  );
}

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transxact example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
      ),
      home: const CartScreen(),
    );
  }
}

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> with WidgetsBindingObserver {
  final transxact = buildTransxact();
  String? pendingSessionId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Closing the in-app browser by hand sends no callback, so check again when the app comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && pendingSessionId != null) {
      _showResult(pendingSessionId!);
    }
  }

  void _showResult(String sessionId) {
    setState(() => pendingSessionId = null);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ReturnScreen(transxact: transxact, sessionId: sessionId),
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transxact example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Order #1001', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 4),
            Text(
              backendUrl.isEmpty
                  ? 'Using the in-app fake backend.'
                  : 'Using $backendUrl',
            ),
            const Spacer(),
            CheckoutButton(
              transxact: transxact,
              // Say WHAT is bought. The amount is decided by the Merchant backend, never by the app.
              payload: const {'orderId': 'order_1001'},
              // Keep the session id to check the result when the Customer comes back.
              onCreated: (created) =>
                  setState(() => pendingSessionId = created.id),
              onError: (error) => _toast('$error'),
              child: const Text('Pay with M-PAiSA or MyCash'),
            ),
            if (pendingSessionId != null) ...[
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => _showResult(pendingSessionId!),
                child: const Text('I have paid — check my payment'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The return screen. Landing here proves nothing; the Merchant backend is always asked.
class ReturnScreen extends StatelessWidget {
  const ReturnScreen({
    super.key,
    required this.transxact,
    required this.sessionId,
  });

  final Transxact transxact;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your payment')),
      body: Center(
        child: CheckoutReturnBuilder(
          transxact: transxact,
          sessionId: sessionId,
          builder: (context, update, refresh) {
            switch (update.state) {
              case CheckoutReturnState.error:
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Couldn't check your payment."),
                    TextButton(
                      onPressed: refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                );
              case CheckoutReturnState.timedOut:
                return const Text(
                  "Still confirming your payment. We'll email you when it's done.",
                );
              case CheckoutReturnState.settled:
                return Text(switch (update.session!.status) {
                  CheckoutSessionStatus.succeeded => 'Paid — thank you!',
                  CheckoutSessionStatus.failed =>
                    "The payment didn't go through.",
                  _ => 'The payment was cancelled.',
                });
              case CheckoutReturnState.loading:
              case CheckoutReturnState.polling:
                return const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Confirming your payment…'),
                  ],
                );
            }
          },
        ),
      ),
    );
  }
}
