# transxact_flutter

Flutter helpers for taking payments with [Transxact](https://transxact.io) hosted Checkout Sessions — M-PAiSA and MyCash, in FJD.

`transxact_flutter` is **client-only**. It never holds a Transxact key and never calls Transxact: every request goes to _your_ server (the **Merchant backend**), which uses [`@transxact/node`](https://www.npmjs.com/package/@transxact/node) (or the PHP SDK) and your secret key. A `sk_` key can never live in a mobile app. The package covers the two app legs of a payment:

1. **Pay** — ask the Merchant backend to create a Checkout Session, then open its hosted URL in an in-app browser (Chrome Custom Tabs on Android, `SFSafariViewController` on iOS).
2. **Return** — when the Customer comes back, ask the Merchant backend what actually happened.

It never takes an amount. Prices are decided by the Merchant backend, where the Customer can't edit them.

## Install

```bash
flutter pub add transxact_flutter
```

## Quickstart

### 1. Configure

Point the SDK at your Merchant backend, with URLs:

```dart
final transxact = Transxact(
  createSessionUri: Uri.parse('https://shop.example/api/checkout'),
  retrieveSessionUri: Uri.parse('https://shop.example/api/checkout'),
  headers: {'Authorization': 'Bearer $yourAppUserToken'}, // your own auth, optional
);
```

or with your own functions, when your backend needs a different request shape (GraphQL, RPC, an existing API client):

```dart
final transxact = Transxact(
  createSession: (idempotencyKey) async {
    final response = await myApi.startPayment(idempotencyKey: idempotencyKey);
    return response.json; // must include hostedUrl
  },
  retrieveSession: (sessionId) async {
    final response = await myApi.paymentStatus(sessionId);
    return response.json; // must include status
  },
);
```

A function beats a URL. The SDK supplies the `Idempotency-Key` (one per attempt, so a retry after a lost response replays the same Checkout Session), validates that `hostedUrl` is `https`, and ignores repeat taps while a payment is starting.

### 2. Pay button

```dart
CheckoutButton(
  transxact: transxact,
  payload: {'orderId': order.id}, // what is bought; never an amount
  onCreated: (created) => pendingSessionId = created.id, // keep it to check the result later
  onError: (error) => showError(context, error),
  child: const Text('Pay with M-PAiSA or MyCash'),
)
```

`onCreated` runs once the hosted page has opened. Or call `await transxact.pay(payload: {...})` from your own button; it returns the same `CreatedCheckoutSession`.

### 3. Return screen

Transxact sends the Customer back to your `successUrl` or `cancelUrl` with `?session_id=cs_…` appended. Read it from the app link (see [Mobile setup](#mobile-setup)) and watch the session:

```dart
CheckoutReturnBuilder(
  transxact: transxact,
  sessionId: sessionId,
  builder: (context, update, refresh) {
    switch (update.state) {
      case CheckoutReturnState.error:
        return TextButton(
          onPressed: refresh,
          child: const Text("Couldn't check your payment — try again"),
        );
      case CheckoutReturnState.timedOut:
        return const Text("Still confirming your payment. We'll email you when it's done.");
      case CheckoutReturnState.settled:
        return switch (update.session!.status) {
          CheckoutSessionStatus.succeeded => const Text('Paid — thank you!'),
          CheckoutSessionStatus.failed => const Text("The payment didn't go through."),
          _ => const Text('The payment was cancelled.'),
        };
      case CheckoutReturnState.loading:
      case CheckoutReturnState.polling:
        return const Text('Confirming your payment…');
    }
  },
)
```

`CheckoutReturnBuilder` starts the lookup when it appears and stops it when it is removed. If you prefer streams, use `transxact.watchSession(sessionId)` directly.

`state` is what the lookup is doing; `session.status` is the payment. They are deliberately separate, so "our request failed" (`error`) is never confused with "the payment failed" (`failed`). The stream polls while the session is `pending` (1.5s, backing off to 8s, giving up after 60s; set `polling: PollingOptions(...)`). Cancel the subscription (or dispose the `StreamBuilder`) to stop polling.

### 4. Merchant backend

Your server creates the session and reports its status. With Node, using `@transxact/node` 0.4.45 or later (the same endpoints serve `@transxact/react`):

```ts
import { TransxactApiClient, TransxactApiError } from "@transxact/node";

const transxact = new TransxactApiClient({ token: process.env.TRANSXACT_SECRET_KEY! });

// POST /api/checkout — the app sends what is being bought; the price is looked up here.
export async function POST(request: Request) {
    const { orderId } = await request.json();
    const order = await findOrder(orderId); // your own lookup
    if (!order) return Response.json({ error: "unknown_order" }, { status: 404 });

    const session = await transxact.checkoutSessions.create({
        idempotencyKey: request.headers.get("Idempotency-Key") ?? crypto.randomUUID(),
        amount: order.totalCents,
        currency: "FJD",
        successUrl: "https://shop.example/checkout/return", // an https app link, see below
        cancelUrl: "https://shop.example/checkout/return",
        metadata: { orderId },
    });
    return Response.json({ id: session.id, hostedUrl: session.hostedUrl });
}

// GET /api/checkout?session_id=cs_…
export async function GET(request: Request) {
    const id = new URL(request.url).searchParams.get("session_id");
    if (!id) return Response.json({ error: "missing_session_id" }, { status: 400 });
    try {
        const session = await transxact.checkoutSessions.retrieve({ id });
        return Response.json({ id: session.id, status: session.status });
    } catch (error) {
        const status = error instanceof TransxactApiError ? (error.statusCode ?? 502) : 502;
        return Response.json({ error: "lookup_failed" }, { status });
    }
}
```

Use an `sk_test_` key while developing: Test mode runs simulated payments on a practice screen and moves no money.

## Mobile setup

This part lives in your app, not in the package.

1. **`successUrl` and `cancelUrl` must be `https://` links that open your app** (a universal link on iOS, an app link on Android). Custom URL schemes such as `myapp://` are rejected by the API.
   - Android: add an `<intent-filter android:autoVerify="true">` for your host and publish `/.well-known/assetlinks.json`.
   - iOS: add an Associated Domains entry (`applinks:shop.example`) and publish `/.well-known/apple-app-site-association`.
2. **Catch the link** with a package such as [`app_links`](https://pub.dev/packages/app_links). Read the `session_id` query parameter and call `transxact.watchSession(sessionId)`.
3. **Check on resume too.** Closing Custom Tabs or `SFSafariViewController` by hand sends the app no callback. Keep the id that `pay()` returns and call `watchSession` when the app returns to the foreground (`WidgetsBindingObserver.didChangeAppLifecycleState`).
4. **Android 11+ package visibility.** `url_launcher` needs this in `android/app/src/main/AndroidManifest.xml`, inside `<manifest>`:

   ```xml
   <queries>
     <intent>
       <action android:name="android.intent.action.VIEW" />
       <data android:scheme="https" />
     </intent>
   </queries>
   ```

5. For local development against an emulator, an `http://` `hostedUrl` is accepted on `localhost`, `127.0.0.1`, `10.0.2.2` and `*.localhost` only.

## The return link is a hint, not proof

Transxact appends `session_id` to **both** `successUrl` and `cancelUrl`, and sends the Customer to `cancelUrl` for failed and expired Checkout Sessions too. Landing on a link tells you nothing about the outcome, which is why `watchSession` always asks the Merchant backend.

Even then, the return screen is only for showing the Customer something. **Fulfil orders from Transxact's webhooks (or a server-side lookup), never from the redirect** — a Customer may never come back to the app. Check each webhook's `Transxact-Signature` on your server with `verifyWebhookSignature` from `@transxact/node/webhooks` ([guide](https://docs.transxact.io/guides/verifying-webhooks)).

## API

### `Transxact`

| Parameter | Description |
| --- | --- |
| `createSession` | `Future<Map<String, dynamic>> Function(String idempotencyKey)`. Must return a map with `hostedUrl` (and optionally `id`). |
| `createSessionUri` | Shorthand: POSTs `payload` as JSON with an `Idempotency-Key` header. |
| `retrieveSession` | `Future<Map<String, dynamic>> Function(String sessionId)`. Must return a map with `status`. |
| `retrieveSessionUri` | Shorthand: GETs with `session_id` appended to the query. |
| `headers` | Extra headers for the URL shorthands, e.g. your own auth. |
| `polling` | `PollingOptions(interval, maxInterval, timeout)`. |

- `pay({payload})` → `Future<CreatedCheckoutSession?>`: creates the session and opens `hostedUrl`. Returns `null` if a payment is already starting.
- `fetchSession(id)` → `Future<CheckoutSession>`: one lookup.
- `watchSession(id)` → `Stream<CheckoutReturnUpdate>`: `loading`, `polling`, then `settled`, `timedOut` or `error`. Cancelling the subscription stops polling.

### Widgets

- `CheckoutButton({transxact, child, payload, onCreated, onError})`: a pay button that is disabled with a spinner while the session is created. `onCreated` receives the `CreatedCheckoutSession` (`id`, `hostedUrl`) once the hosted page has opened.
- `CheckoutReturnBuilder({transxact, sessionId, builder})`: runs `watchSession` for you. `builder(context, update, refresh)` is called for every `CheckoutReturnUpdate`; call `refresh` to start the lookup again. Changing `sessionId` restarts it.

### Errors

The SDK throws `TransxactException` with a `code`: `configMissing`, `httpError` (with `status` and `body`) or `invalidResponse`. Errors thrown by your own `createSession` / `retrieveSession` functions pass through unchanged.

## License

Apache-2.0
