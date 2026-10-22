# Changelog

## [0.1.1](https://github.com/transxactfj/transxact-flutter/compare/v0.1.0...v0.1.1) (2026-10-22)


### Bug Fixes

* require Flutter 3.32+ to match the Dart SDK constraint ([528c3e9](https://github.com/transxactfj/transxact-flutter/commit/528c3e98a7d10eee7776d3aeb61aff015d13822b))

## 0.1.0

* First release of `transxact_flutter`, the client-only Flutter SDK for Transxact hosted Checkout Sessions.
* `Transxact.pay` and `CheckoutButton` start a Checkout attempt through the Merchant backend and open the hosted URL in an in-app browser, with an Idempotency-Key per attempt, a double-tap guard and https-only `hostedUrl` validation.
* `CheckoutButton.onCreated` hands back the created session, so the app can check its result when the Customer returns.
* `Transxact.watchSession` confirms the Checkout Session status through the Merchant backend, polling while it is `pending`. Cancelling the subscription stops polling at once.
* `CheckoutReturnBuilder` runs `watchSession` for a return screen and gives its builder the current update and a `refresh` function.
* `createSessionUri` / `retrieveSessionUri` shorthands cover simple Merchant backends.
* Never takes an amount or a secret key.
