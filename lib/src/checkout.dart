import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'errors.dart';
import 'guards.dart';
import 'hosted_url.dart';
import 'idempotency_key.dart';
import 'types.dart';
import 'version.dart';

/// Opens the Customer's checkout page. Returns whether it opened.
typedef UrlOpener = Future<bool> Function(Uri url);

Future<bool> _openInAppBrowser(Uri url) =>
    launchUrl(url, mode: LaunchMode.inAppBrowserView);

const _maxRetryAfter = Duration(seconds: 60);

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
    this.requestTimeout = const Duration(seconds: 30),
    this.maxRetries = 2,
    this.retryBaseDelay = const Duration(milliseconds: 500),
    this.allowedHostedUrlHosts,
    this.onLog,
    http.Client? client,
    UrlOpener? openUrl,
  }) : _ownsClient = client == null,
       _client = client ?? http.Client(),
       _open = openUrl ?? _openInAppBrowser,
       _random = Random() {
    if (requestTimeout <= Duration.zero ||
        maxRetries < 0 ||
        polling.interval <= Duration.zero ||
        polling.maxInterval < polling.interval ||
        polling.timeout <= Duration.zero ||
        polling.retries < 0 ||
        polling.jitter < 0 ||
        polling.jitter > 1) {
      throw ArgumentError(
        'requestTimeout, polling.interval and polling.timeout must be '
        'positive, polling.maxInterval at least polling.interval, retries '
        'not negative, and jitter between 0 and 1.',
      );
    }
    for (final value in headers.values) {
      assertNoSecretKey('headers', value);
    }
    for (final uri in [createSessionUri, retrieveSessionUri]) {
      assertNoSecretKey('a backend URL', uri);
    }
  }

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

  /// How long one request to the Merchant backend may take.
  final Duration requestTimeout;

  /// How many times [pay] retries a transient failure of [createSessionUri]
  /// (timeout, network, HTTP 408/429/5xx), always with the same
  /// `Idempotency-Key`.
  final int maxRetries;

  /// The first retry wait; it doubles each time, up to `polling.maxInterval`.
  final Duration retryBaseDelay;

  /// If set, a `hostedUrl` must be on one of these exact hostnames.
  final List<String>? allowedHostedUrlHosts;
  final TransxactLogger? onLog;

  final bool _ownsClient;
  final http.Client _client;
  final UrlOpener _open;
  final Random _random;
  bool _paying = false;

  /// Releases the HTTP client, if this object created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Asks the Merchant backend to create a Checkout Session, then opens its
  /// `hostedUrl` in an in-app browser.
  ///
  /// [payload] identifies what is being bought (e.g. `{'orderId': 'o_1'}`);
  /// it may not carry an amount, currency or quote, nor a secret key.
  /// [idempotencyKey] defaults to a fresh one per attempt; pass the key of an
  /// earlier attempt to retry that attempt and get the same session back.
  /// Returns null if a payment is already starting.
  Future<CreatedCheckoutSession?> pay({
    Object? payload,
    String? idempotencyKey,
  }) async {
    if (_paying) return null;
    _paying = true;
    try {
      assertNoAmount(payload);
      assertNoSecretKey('payload', jsonEncode(payload ?? {}));
      final key = idempotencyKey ?? newIdempotencyKey();
      final Map<String, dynamic> body;
      if (createSession != null) {
        body = await _guard(() => createSession!(key));
      } else if (createSessionUri != null) {
        final encoded = jsonEncode(payload ?? {});
        body = await _retrying(
          () => _request(
            'POST',
            createSessionUri!,
            headers: {
              ...headers,
              'Content-Type': 'application/json',
              'Idempotency-Key': key,
            },
            body: encoded,
          ),
        );
      } else {
        throw TransxactException(
          TransxactErrorCode.configMissing,
          'No way to reach the Merchant backend: pass createSession or '
          'createSessionUri.',
        );
      }
      final url = validateHostedUrl(
        body['hostedUrl'],
        allowedHosts: allowedHostedUrlHosts,
      );
      final opened = await _open(url);
      if (!opened) {
        throw TransxactException(
          TransxactErrorCode.launchFailed,
          'The checkout page could not be opened.',
        );
      }
      final id = body['id'];
      return CreatedCheckoutSession(
        hostedUrl: url.toString(),
        id: id is String ? id : null,
        idempotencyKey: key,
      );
    } finally {
      _paying = false;
    }
  }

  /// Asks the Merchant backend what a Checkout Session's status is.
  Future<CheckoutSession> fetchSession(String sessionId) =>
      _fetch(sessionId, null);

  Future<CheckoutSession> _fetch(String sessionId, Future<void>? abort) async {
    assertSessionId(sessionId);
    final Map<String, dynamic> body;
    if (retrieveSession != null) {
      body = await _guard(() => retrieveSession!(sessionId));
    } else if (retrieveSessionUri != null) {
      final uri = retrieveSessionUri!.replace(
        queryParameters: {
          ...retrieveSessionUri!.queryParameters,
          'session_id': sessionId,
        },
      );
      body = await _request('GET', uri, headers: headers, abort: abort);
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
    if (id is String && id != sessionId) {
      throw TransxactException(
        TransxactErrorCode.invalidResponse,
        "The Merchant backend answered with a different Checkout Session than "
        'the one asked for.',
      );
    }
    return CheckoutSession(id: sessionId, status: statuses.first, raw: body);
  }

  /// Confirms what actually happened to a Checkout Session, polling while it
  /// is still `pending`.
  ///
  /// Arriving back from checkout proves nothing (both the success and cancel
  /// URLs get `session_id`), so the Merchant backend is always asked. Cancel
  /// the subscription to stop polling: the pending request is aborted and no
  /// further lookup is made. A transient failure (timeout, network, HTTP
  /// 408/429/5xx) is retried with backoff up to `polling.retries` times in a
  /// row, within `polling.timeout`.
  Stream<CheckoutReturnUpdate> watchSession(String sessionId) {
    late final StreamController<CheckoutReturnUpdate> controller;
    final abort = Completer<void>();

    Future<void> poll() async {
      final started = DateTime.now();
      var delay = polling.interval;
      var failures = 0;
      controller.add(const CheckoutReturnUpdate(CheckoutReturnState.loading));
      while (!abort.isCompleted) {
        final CheckoutSession session;
        try {
          session = await _fetch(sessionId, abort.future);
          failures = 0;
        } catch (error) {
          if (abort.isCompleted) break;
          final left = polling.timeout - DateTime.now().difference(started);
          if (_isTransient(error) &&
              failures < polling.retries &&
              left > Duration.zero) {
            final wait = _backoff(polling.interval, failures, error);
            failures++;
            await _sleep(wait < left ? wait : left, abort.future);
            continue;
          }
          controller.add(
            CheckoutReturnUpdate(CheckoutReturnState.error, error: error),
          );
          break;
        }
        if (abort.isCompleted) break;
        if (session.status != CheckoutSessionStatus.pending) {
          controller.add(
            CheckoutReturnUpdate(CheckoutReturnState.settled, session: session),
          );
          break;
        }
        final remaining = polling.timeout - DateTime.now().difference(started);
        if (remaining <= Duration.zero) {
          controller.add(
            CheckoutReturnUpdate(
              CheckoutReturnState.timedOut,
              session: session,
            ),
          );
          break;
        }
        controller.add(
          CheckoutReturnUpdate(CheckoutReturnState.polling, session: session),
        );
        await _sleep(delay < remaining ? delay : remaining, abort.future);
        delay = delay * 2 > polling.maxInterval
            ? polling.maxInterval
            : delay * 2;
      }
      await controller.close();
    }

    controller = StreamController<CheckoutReturnUpdate>(
      onListen: poll,
      onCancel: () {
        if (!abort.isCompleted) abort.complete();
      },
    );
    return controller.stream;
  }

  /// Runs one of the Merchant's own callbacks under [requestTimeout].
  Future<Map<String, dynamic>> _guard(
    Future<Map<String, dynamic>> Function() call,
  ) async {
    try {
      return await call().timeout(requestTimeout);
    } on TimeoutException catch (e) {
      throw TransxactException(
        TransxactErrorCode.timeout,
        'Your callback did not answer within ${requestTimeout.inSeconds}s.',
        cause: e,
      );
    }
  }

  /// One request to the Merchant backend, under [requestTimeout], abortable.
  Future<Map<String, dynamic>> _request(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    String? body,
    Future<void>? abort,
  }) async {
    final trigger = Completer<void>();
    if (abort != null) {
      unawaited(
        abort.then((_) {
          if (!trigger.isCompleted) trigger.complete();
        }),
      );
    }
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: trigger.future,
    );
    request.headers.addAll({
      'User-Agent': 'transxact_flutter/$sdkVersion',
      'X-Transxact-SDK': 'transxact_flutter/$sdkVersion',
      ...headers,
    });
    // A POST that is redirected may be replayed elsewhere; fail instead.
    if (method == 'POST') request.followRedirects = false;
    if (body != null) request.body = body;
    final where = '$method ${describeUrl(uri)}';
    final http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(requestTimeout);
    } on TimeoutException catch (e) {
      if (!trigger.isCompleted) trigger.complete();
      onLog?.call('$where timed out');
      throw TransxactException(
        TransxactErrorCode.timeout,
        'The Merchant backend did not answer $where within '
        '${requestTimeout.inSeconds}s.',
        cause: e,
      );
    } on http.RequestAbortedException catch (e) {
      throw TransxactException(
        TransxactErrorCode.cancelled,
        'The request $where was cancelled.',
        cause: e,
      );
    } catch (e) {
      onLog?.call('$where failed to connect');
      throw TransxactException(
        TransxactErrorCode.network,
        'Could not reach the Merchant backend for $where.',
        cause: e,
      );
    }
    onLog?.call('$where -> ${response.statusCode}');
    return _parseJson(response, where);
  }

  Map<String, dynamic> _parseJson(http.Response response, String where) {
    Object? json;
    var isJson = false;
    try {
      json = jsonDecode(response.body);
      isJson = true;
    } catch (_) {
      // Not JSON; decided below.
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = isJson && json is Map ? json['error'] : null;
      final apiCode = error is Map && error['code'] is String
          ? error['code'] as String
          : null;
      throw TransxactException(
        TransxactErrorCode.httpError,
        'The Merchant backend answered $where with HTTP '
        '${response.statusCode}.',
        status: response.statusCode,
        body: isJson ? json : response.body,
        apiCode: apiCode,
        requestId: response.headers['x-request-id'],
        retryAfter: _retryAfter(response.headers['retry-after']),
      );
    }
    if (json is! Map<String, dynamic>) {
      throw TransxactException(
        TransxactErrorCode.invalidResponse,
        "The Merchant backend's response to $where is not a JSON object.",
        requestId: response.headers['x-request-id'],
      );
    }
    return json;
  }

  /// Runs [attempt], retrying transient failures with the same inputs.
  Future<T> _retrying<T>(Future<T> Function() attempt) async {
    var failures = 0;
    while (true) {
      try {
        return await attempt();
      } catch (error) {
        if (failures >= maxRetries || !_isTransient(error)) rethrow;
        await _sleep(_backoff(retryBaseDelay, failures, error), null);
        failures++;
      }
    }
  }

  Duration _backoff(Duration base, int failures, Object error) {
    var wait = base * pow(2, failures).toInt();
    if (wait > polling.maxInterval) wait = polling.maxInterval;
    final spread = polling.jitter * (_random.nextDouble() * 2 - 1);
    wait = Duration(microseconds: (wait.inMicroseconds * (1 + spread)).round());
    final asked = error is TransxactException ? error.retryAfter : null;
    if (asked != null && asked > wait) {
      wait = asked > _maxRetryAfter ? _maxRetryAfter : asked;
    }
    return wait;
  }
}

bool _isTransient(Object error) {
  if (error is! TransxactException) return false;
  switch (error.code) {
    case TransxactErrorCode.timeout:
    case TransxactErrorCode.network:
      return true;
    case TransxactErrorCode.httpError:
      final status = error.status ?? 0;
      return status == 408 || status == 429 || status >= 500;
    default:
      return false;
  }
}

Duration? _retryAfter(String? header) {
  final seconds = int.tryParse(header?.trim() ?? '');
  return seconds == null || seconds < 0 ? null : Duration(seconds: seconds);
}

/// Waits [duration], or less if [abort] completes first. The timer is
/// cancelled, so nothing is left pending.
Future<void> _sleep(Duration duration, Future<void>? abort) {
  final done = Completer<void>();
  final timer = Timer(duration, () {
    if (!done.isCompleted) done.complete();
  });
  abort?.then((_) {
    timer.cancel();
    if (!done.isCompleted) done.complete();
  });
  return done.future;
}
