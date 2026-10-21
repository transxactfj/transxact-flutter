import 'package:flutter/material.dart';

import 'checkout.dart';

/// A pay button. While the Checkout Session is being created it is disabled
/// and shows a spinner.
class CheckoutButton extends StatefulWidget {
  const CheckoutButton({
    super.key,
    required this.transxact,
    required this.child,
    this.payload,
    this.onError,
  });

  final Transxact transxact;
  final Widget child;

  /// Identifies what is being bought; the Merchant backend decides the amount.
  final Object? payload;
  final void Function(Object error)? onError;

  @override
  State<CheckoutButton> createState() => _CheckoutButtonState();
}

class _CheckoutButtonState extends State<CheckoutButton> {
  bool _busy = false;

  Future<void> _tap() async {
    setState(() => _busy = true);
    try {
      await widget.transxact.pay(payload: widget.payload);
    } catch (error) {
      widget.onError?.call(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _busy ? null : _tap,
      child: _busy
          ? const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : widget.child,
    );
  }
}
