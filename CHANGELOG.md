## 0.1.0

* First release of `transxact_flutter`, the client-only Flutter SDK for Transxact hosted Checkout Sessions.
* `Transxact.pay` and `CheckoutButton` start a Checkout attempt through the Merchant backend and open the hosted URL in an in-app browser, with an Idempotency-Key per attempt, a double-tap guard and https-only `hostedUrl` validation.
* `Transxact.watchSession` confirms the Checkout Session status through the Merchant backend, polling while it is `pending`.
* `createSessionUri` / `retrieveSessionUri` shorthands cover simple Merchant backends.
* Never takes an amount or a secret key.
