# Client-only, hand-written Flutter SDK over the hosted Checkout Session

The platform's ADR-0010 says "No native iOS/Android SDK", shipping a mobile guide instead, and ADR-0011 keeps `sk_` keys server-to-server with no CORS on `/v1` and no publishable key. This package (`transxact_flutter`) departs from ADR-0010 on purpose, the way `@transxact/react` does, but it does less than an SDK normally would. The app can never talk to Transxact directly, so the package only covers the two app legs of the hosted checkout (platform ADR-0003):

1. Asking the Merchant backend to create a Checkout Session, then opening its `hostedUrl` in an in-app browser.
2. After the Customer returns, asking the Merchant backend what the Checkout Session's status is.

Every call goes through a function or URL the Merchant supplies, so the SDK never holds a key and never talks to Transxact.

It never accepts an amount: a price set in the app can be edited by the Customer, so the Merchant backend alone decides it. It generates the `Idempotency-Key` (platform ADR-0009), one per attempt, and passes it through for the Merchant backend to forward, so a retried request after a lost response replays the same Checkout Session.

It is hand-written, not Fern-generated, for the same reason as the React SDK: there is nothing in the OpenAPI spec to generate from, because the app's surface is the Merchant's own endpoints, not Transxact's. Fern also has no Dart generator in this project. Its only runtime dependencies are `http` (the URL shorthands) and `url_launcher` (the in-app browser).

The SDK never infers an outcome from the return link. Both the success and cancel URLs get `session_id`, and the hosted page follows the cancel URL for failed and expired sessions too. It always confirms through the Merchant backend, polling while the Checkout Session is `pending`. Orders are fulfilled from webhooks, never from the return link.

Return links must be https app links (platform mobile guide): custom URL schemes are rejected by the API. Catching the link is left to the host app, so the package carries no deep-link dependency or platform setup of its own.

## Considered Options

- **A pure-Dart server client** (typed models, retries, webhook verification, for Dart backends): a different audience and a key held server-side. It can ship later as its own package without breaking this one.
- **An embedded WebView checkout**: conflicts with the M-PAiSA frame-breaking, and loses the trusted-browser chrome that Custom Tabs and `SFSafariViewController` give the Customer.
- **A bundled deep-link handler**: ties the package to one plugin and to per-platform setup the host app already owns.
- **A headless wallet UI**: needs the raw, Merchant-built-UI API that platform ADR-0003 deferred, plus a client-safe key type contradicting platform ADR-0011.
