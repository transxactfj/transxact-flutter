import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'errors.dart';
import 'hosted_url.dart';
import 'idempotency_key.dart';
import 'types.dart';

/// Opens the Customer's checkout page. Returns whether it opened.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _openInAppBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.inAppBrowserView);

/// Client-only: never holds a Transxact key and never calls Transxact. Every
/// request goes to the Merchant backend, through a function or URL the
/// Merchant supplies. A function beats a URL. The SDK never takes an amount:
/// the Merchant backend alone decides the price.
class Transxact {
  Transxact({
    this.createSession,
    this.createSessionUri,
    this.retrieveSession,
    this.retrieveSessionUri,
    this.headers = const {},
    this.polling = const PollingOptions(),
    http.Client? client,
    UrlOpener? openUrl,
  }) : _client = client ?? http.Client(),
       _open = openUrl ?? _openInAppBrowser;

  final CreateSession? createSession;

  /// POSTed with a JSON body (the `payload` given to [pay]) and an
  /// `Idempotency-Key` header.
  final Uri? createSessionUri;
  final RetrieveSession? retrieveSession;

  /// GETed with `session_id` appended as a query parameter.
  final Uri? retrieveSessionUri;

  /// Extra headers for requests to the Merchant backend, e.g. your own auth.
  final Map<String, String> headers;
  final PollingOptions polling;

  final http.Client _client;
  final UrlOpener _open;
  bool _paying = false;

  /// Asks the Merchant backend to create a Checkout Session, then opens its
  /// `hostedUrl` in an in-app browser.
  ///
  /// [payload] identifies what is being bought (e.g. `{'orderId': 'o_1'}`);
  /// never send an amount from the app. Returns null if a payment is already
  /// starting.
  Future<CreatedCheckoutSession?> pay({Object? payload}) async {
    if (_paying) return null;
    _paying = true;
    try {
      final key = newIdempotencyKey();
      final Map<String, dynamic> body;
      if (createSession != null) {
        body = await createSession!(key);
      } else if (createSessionUri != null) {
        final response = await _client.post(
          createSessionUri!,
          headers: {
            ...headers,
            'Content-Type': 'application/json',
            'Idempotency-Key': key,
          },
          body: jsonEncode(payload ?? {}),
        );
        body = _parseJson(response, createSessionUri!);
      } else {
        throw TransxactException(
          TransxactErrorCode.configMissing,
          'No way to reach the Merchant backend: pass createSession or '
          'createSessionUri.',
        );
      }
      final url = validateHostedUrl(body['hostedUrl']);
      await _open(url);
      final id = body['id'];
      return CreatedCheckoutSession(
        hostedUrl: url.toString(),
        id: id is String ? id : null,
      );
    } finally {
      _paying = false;
    }
  }

  /// Asks the Merchant backend what a Checkout Session's status is.
  Future<CheckoutSession> fetchSession(String sessionId) async {
    final Map<String, dynamic> body;
    if (retrieveSession != null) {
      body = await retrieveSession!(sessionId);
    } else if (retrieveSessionUri != null) {
      final uri = retrieveSessionUri!.replace(
        queryParameters: {
          ...retrieveSessionUri!.queryParameters,
          'session_id': sessionId,
        },
      );
      body = _parseJson(await _client.get(uri, headers: headers), uri);
    } else {
      throw TransxactException(
        TransxactErrorCode.configMissing,
        'No way to reach the Merchant backend: pass retrieveSession or '
        'retrieveSessionUri.',
      );
    }
    final statuses = CheckoutSessionStatus.values.where(
      (s) => s.name == body['status'],
    );
    if (statuses.isEmpty) {
      throw TransxactException(
        TransxactErrorCode.invalidResponse,
        "The Merchant backend's response is not a Checkout Session with a "
        'valid status.',
      );
    }
    final id = body['id'];
    return CheckoutSession(
      id: id is String ? id : sessionId,
      status: statuses.first,
      raw: body,
    );
  }

  /// Confirms what actually happened to a Checkout Session, polling while it
  /// is still `pending`.
  ///
  /// Arriving back from checkout proves nothing (both the success and cancel
  /// URLs get `session_id`), so the Merchant backend is always asked. Cancel
  /// the subscription to stop polling.
  Stream<CheckoutReturnUpdate> watchSession(String sessionId) async* {
    final started = DateTime.now();
    var delay = polling.interval;
    yield const CheckoutReturnUpdate(CheckoutReturnState.loading);
    while (true) {
      final CheckoutSession session;
      try {
        session = await fetchSession(sessionId);
      } catch (error) {
        yield CheckoutReturnUpdate(CheckoutReturnState.error, error: error);
        return;
      }
      if (session.status != CheckoutSessionStatus.pending) {
        yield CheckoutReturnUpdate(
          CheckoutReturnState.settled,
          session: session,
        );
        return;
      }
      final remaining = polling.timeout - DateTime.now().difference(started);
      if (remaining <= Duration.zero) {
        yield CheckoutReturnUpdate(
          CheckoutReturnState.timedOut,
          session: session,
        );
        return;
      }
      yield CheckoutReturnUpdate(CheckoutReturnState.polling, session: session);
      await Future<void>.delayed(delay < remaining ? delay : remaining);
      delay = delay * 2 > polling.maxInterval ? polling.maxInterval : delay * 2;
    }
  }

  Map<String, dynamic> _parseJson(http.Response response, Uri url) {
    Object? json;
    var isJson = false;
    try {
      json = jsonDecode(response.body);
      isJson = true;
    } catch (_) {
      // Not JSON; decided below.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw TransxactException(
        TransxactErrorCode.httpError,
        'The Merchant backend answered $url with HTTP ${response.statusCode}.',
        status: response.statusCode,
        body: isJson ? json : response.body,
      );
    }
    if (json is! Map<String, dynamic>) {
      throw TransxactException(
        TransxactErrorCode.invalidResponse,
        "The Merchant backend's response to $url is not a JSON object.",
      );
    }
    return json;
  }
}
