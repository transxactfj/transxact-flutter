# Security policy

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub's
[private vulnerability reporting](https://github.com/transxactfj/transxact-flutter/security/advisories/new)
for this repository. Include the affected version, what you did, and what you saw.

## Supported versions

Only the latest published minor version of `transxact_flutter` receives security fixes.

## Scope and design

`transxact_flutter` runs inside your app and never handles Transxact secret keys. Anything that needs a secret key
(creating and retrieving Checkout Sessions) belongs on your Merchant backend, which the SDK calls through the URLs or
functions you provide. The SDK refuses to send an `sk_` key or an amount, and only opens a `hostedUrl` that is `https`
(or `http` on loopback), carries no credentials, and, if you set `allowedHostedUrlHosts`, is on one of those hosts.
See `docs/adr/0001-client-only-flutter-sdk.md`.
