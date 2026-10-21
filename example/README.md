# transxact_flutter example

A small app showing both legs of a payment: a pay button, and a return screen that confirms the result.

## Run it with no setup

```bash
flutter run
```

Without a backend the app uses an in-memory fake that returns `https://transxact.io` as the checkout page and reports the session as `pending` for two lookups, then `succeeded`. Tap **Pay with M-PAiSA or MyCash**, close the browser, and the return screen appears when the app resumes.

## Run it against a real Merchant backend (Test mode)

1. Start the sample backend with an `sk_test_` key (see the header of `backend/server.mjs`):

   ```bash
   cd backend
   npm install @transxact/node
   TRANSXACT_SECRET_KEY=sk_test_... node server.mjs
   ```

2. Run the app, pointing it at the backend (`10.0.2.2` is the Android emulator's address for your computer):

   ```bash
   flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8787/api/checkout
   ```

Test mode runs simulated payments on a Transxact practice screen and moves no money. The secret key stays on the server; the app only ever sees a session id, a `hostedUrl` and a status.

## What it leaves out

Catching the https app link the hosted page returns the Customer to. That needs per-app Android and iOS setup (see "Mobile setup" in the package README), so the example checks again when the app resumes instead. Note the sample backend's `RETURN_URL` is a placeholder: a real app needs a real app link.
