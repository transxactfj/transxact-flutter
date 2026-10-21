import 'package:flutter/material.dart';

import 'checkout.dart';
import 'checkout_return_builder.dart';
import 'types.dart';

/// A pay button. While the Checkout Session is being created it is disabled
/// and shows a spinner.
class CheckoutButton extends StatefulWidget {
  const CheckoutButton({
    super.key,
    required this.transxact,
    required this.child,
    this.payload,
    this.onCreated,
    this.onError,
  });

  final Transxact transxact;
  final Widget child;

  /// Identifies what is being bought; the Merchant backend decides the amount.
  final Object? payload;

  /// Called once the Checkout Session exists and its hosted page has been
  /// opened. Keep the session id to check the result when the Customer
  /// returns (see [CheckoutReturnBuilder]).
  final void Function(CreatedCheckoutSession created)? onCreated;
  final void Function(Object error)? onError;

  @override
  State<CheckoutButton> createState() => _CheckoutButtonState();
}

class _CheckoutButtonState extends State<CheckoutButton> {
  bool _busy = false;

  Future<void> _tap() async {
    setState(() => _busy = true);
    try {
      final created = await widget.transxact.pay(payload: widget.payload);
      if (created != null) widget.onCreated?.call(created);
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
