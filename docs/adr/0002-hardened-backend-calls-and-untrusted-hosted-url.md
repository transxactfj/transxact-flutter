# Harden the calls to the Merchant backend, and treat `hostedUrl` as untrusted

ADR-0001 makes this package client-only: every call goes to the Merchant backend, and the SDK never holds a key. That keeps the SDK small, but it also means the SDK sits on a mobile network between an app and a backend it does not control. This ADR records the hardening of those calls, which mirrors the hardening in `@transxact/react` and follows the platform's error contract (`{ "error": { "code", "message" } }`, where `code` is stable and `message` is not). It refines ADR-0001; it does not replace it.

## Rules are enforced, not just documented

ADR-0001 says the SDK never takes an amount and never accepts an `sk_` key. Those rules are now checked at runtime:

- `pay` throws `invalidRequest` for an `amount`, `currency`, `quote` or `price` key anywhere in the payload (matched case-insensitively, ignoring separators, so `Amount_Cents` is caught and `priceId` is not).
- Any `sk_live_` or `sk_test_` string in `headers`, a backend URL or the payload is refused. Headers and URLs are checked in the constructor.
- A session id must be well formed (`[A-Za-z0-9_-]`, 1 to 128 characters) before it is sent, and an answer for a different id than the one asked for is `invalidResponse`.

## Idempotency

One `Idempotency-Key` per checkout attempt still holds. What an "attempt" is has been made explicit:

- `pay()` generates a fresh key. Retries of a transient failure inside that call reuse it, so a lost response replays the same Checkout Session.
- `pay(idempotencyKey:)` accepts the key from an earlier result (`CreatedCheckoutSession.idempotencyKey`), so an app can retry an attempt after being killed. A plain second `pay()` is a new attempt with a new key.
- A 409 `idempotency_key_reused` is a developer error and is never retried.

## Timeouts, retries and cancellation

- Every request, and each of the Merchant's own `createSession` / `retrieveSession` callbacks, is bounded by `requestTimeout` (30 s by default). Requests are abortable, so cancelling `watchSession` aborts the one in flight and cancels the wait between lookups.
- Timeouts, network failures and HTTP 408, 429 and 5xx are transient. They are retried with exponential backoff and jitter. Polling retries up to `polling.retries` times in a row (3 by default) within `polling.timeout`; `pay` retries up to `maxRetries` times (2 by default), always with the same key. Other 4xx are never retried.
- `Retry-After` is honoured when it is a number of seconds, capped at 60 s. The HTTP-date form is not parsed, because that needs `dart:io`, which would cost the package its web support. The platform sends no `Retry-After` today, but its Cloudflare edge may.
- The Node SDK does not retry thrown network errors. This package does, because a mobile network drops far more often than a server's.
- A POST is never redirected, so a create request cannot be replayed elsewhere.

## Errors and redaction

`TransxactException` gains the codes `timeout`, `network`, `cancelled`, `launchFailed` and `invalidRequest`, and the fields `apiCode`, `requestId` and `retryAfter`. Callers branch on `code` and `apiCode`, never on `message`.

Messages name the request path only: no host, credentials or query string, because the query string carries the `session_id`. `body` is whatever the backend answered and may be sensitive, so it is for logs, not for the Customer. The SDK is silent unless `onLog` is set, and then logs only method, path and status. Requests carry `User-Agent` and `X-Transxact-SDK` headers with the SDK version.

## `hostedUrl` is untrusted

The Merchant backend is trusted, but a compromised or misconfigured one must not be able to send the Customer anywhere. `validateHostedUrl` therefore:

- requires https, or http on loopback for development (the rule in `AGENTS.md`);
- rejects credentials in the URL, which would otherwise let `https://pay.transxact.io@evil.example` pass as a trusted host;
- requires an exact hostname match when `allowedHostedUrlHosts` is set;
- never echoes the URL in an error.

`pay` throws `launchFailed` when the browser does not open, instead of returning a session the Customer cannot see.

The http loopback exception (including `10.0.2.2`, the Android emulator's host) stays on in release builds, because gating it on `kDebugMode` would change the rule above and make the pure-Dart validator depend on Flutter. An app that wants it off sets `allowedHostedUrlHosts`.

## Unknown statuses stay errors

The platform has four statuses: `pending`, `succeeded`, `failed` and `cancelled`. An unpaid session past `expiresAt` becomes `cancelled`; there is no `expired` status. A status outside those four is still `invalidResponse`, not a guessed state, because misreading a payment outcome costs more than showing an error.

## Considered Options

- **Retrying `createSession` and `retrieveSession` callbacks.** Rejected: the SDK cannot tell a transient failure from any other exception thrown by the Merchant's own code. Callbacks are bounded by `requestTimeout` and otherwise pass through unchanged.
- **Adding `CheckoutSessionStatus.unknown`.** Rejected for now: it would change every exhaustive `switch` in apps, and the platform's set of statuses is closed.
- **A default `allowedHostedUrlHosts` of the Transxact checkout host.** Rejected: the hostname is the platform's to change, and test and live environments differ. It is opt-in, as in `@transxact/react`.
- **Gating loopback on `kDebugMode`.** Rejected, see above.
- **Pinning TLS certificates.** Rejected: the platform sits behind Cloudflare, whose certificates rotate, and the Merchant backend's certificate is the Merchant's. The system trust store applies.
