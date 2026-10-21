import 'dart:async';

import 'package:flutter/widgets.dart';

import 'checkout.dart';
import 'types.dart';

/// Builds the UI for one [CheckoutReturnUpdate]. Call [refresh] to start the
/// lookup again, e.g. after an error or a timeout.
typedef CheckoutReturnWidgetBuilder = Widget Function(
  BuildContext context,
  CheckoutReturnUpdate update,
  VoidCallback refresh,
);

/// Confirms what actually happened to a Checkout Session, for the screen the
/// Customer lands on when they come back.
///
/// Landing there proves nothing, so this always asks the Merchant backend
/// (through [Transxact.watchSession]), polling while the session is `pending`.
/// It starts when it appears and stops when it is removed.
class CheckoutReturnBuilder extends StatefulWidget {
  const CheckoutReturnBuilder({
    super.key,
    required this.transxact,
    required this.sessionId,
    required this.builder,
  });

  final Transxact transxact;
  final String sessionId;
  final CheckoutReturnWidgetBuilder builder;

  @override
  State<CheckoutReturnBuilder> createState() => _CheckoutReturnBuilderState();
}

class _CheckoutReturnBuilderState extends State<CheckoutReturnBuilder> {
  StreamSubscription<CheckoutReturnUpdate>? _subscription;
  CheckoutReturnUpdate _update = const CheckoutReturnUpdate(
    CheckoutReturnState.loading,
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CheckoutReturnBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId ||
        oldWidget.transxact != widget.transxact) {
      _refresh();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _start() {
    _subscription = widget.transxact
        .watchSession(widget.sessionId)
        .listen((update) => setState(() => _update = update));
  }

  void _refresh() {
    _subscription?.cancel();
    setState(
      () => _update = const CheckoutReturnUpdate(CheckoutReturnState.loading),
    );
    _start();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _update, _refresh);
}
