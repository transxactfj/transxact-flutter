// A minimal Merchant backend for the example app. NOT part of the package.
//
//   cd example/backend
//   npm install
//   TRANSXACT_SECRET_KEY=sk_test_... node server.mjs
//
// Then run the app with:
//   flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8787/api/checkout
// (10.0.2.2 is the Android emulator's address for your computer.)
//
// Use an sk_test_ key: Test mode runs simulated payments and moves no money. The secret key stays here,
// on the server, never in the app. Only an id, hostedUrl and status ever reach the app.
import { createServer } from "node:http";
import { randomUUID } from "node:crypto";
import { TransxactApiClient, TransxactApiError } from "@transxact/node";

const transxact = new TransxactApiClient({ token: process.env.TRANSXACT_SECRET_KEY });

// Your own price list. The app only says WHAT is bought; the amount is decided here.
const ORDERS = { order_1001: { totalCents: 2500 } };

// Return links must be https; this one is a placeholder. Replace it with an app link that opens your app.
const RETURN_URL = "https://shop.example/checkout/return";

function send(res, status, body) {
    res.writeHead(status, { "Content-Type": "application/json" });
    res.end(JSON.stringify(body));
}

async function readJson(req) {
    let text = "";
    for await (const chunk of req) text += chunk;
    return text ? JSON.parse(text) : {};
}

createServer(async (req, res) => {
    const url = new URL(req.url, "http://localhost");
    if (url.pathname !== "/api/checkout") return send(res, 404, { error: "not_found" });

    try {
        if (req.method === "POST") {
            const { orderId } = await readJson(req);
            const order = ORDERS[orderId];
            if (!order) return send(res, 404, { error: "unknown_order" });
            const session = await transxact.checkoutSessions.create({
                idempotencyKey: req.headers["idempotency-key"] ?? randomUUID(),
                amount: order.totalCents,
                currency: "FJD",
                successUrl: RETURN_URL,
                cancelUrl: RETURN_URL,
                metadata: { orderId },
            });
            return send(res, 200, { id: session.id, hostedUrl: session.hostedUrl });
        }
        if (req.method === "GET") {
            const id = url.searchParams.get("session_id");
            if (!id) return send(res, 400, { error: "missing_session_id" });
            const session = await transxact.checkoutSessions.retrieve({ id });
            return send(res, 200, { id: session.id, status: session.status });
        }
        send(res, 405, { error: "method_not_allowed" });
    } catch (error) {
        const status = error instanceof TransxactApiError ? (error.statusCode ?? 502) : 502;
        send(res, status, { error: "request_failed" });
    }
}).listen(8787, () => console.log("Merchant backend on http://localhost:8787/api/checkout"));
