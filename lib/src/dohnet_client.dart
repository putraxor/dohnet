import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'doh_resolver.dart';

/// A simple HTTP client that uses DNS-over-HTTPS (DoH) for domain resolution.
///
/// Designed like `package:http` — just call [get], [post], etc. and get a
/// [DohnetResponse] back.
///
/// Example:
/// ```dart
/// final client = DohnetClient();
/// final response = await client.get(Uri.parse('https://example.com'));
/// print(response.statusCode);
/// print(response.body);
/// client.close();
/// ```
class DohnetClient {
  final HttpClient _client;
  final DohResolver _resolver;

  /// Callback to override certificate validation.
  ///
  /// When connecting via IP, the TLS certificate's hostname won't match the
  /// resolved IP address, so you typically need to accept it. Defaults to
  /// accepting all certificates.
  bool Function(X509Certificate)? badCertificateCallback;

  /// Creates a [DohnetClient].
  ///
  /// If [resolver] is not provided, the global [DohResolver] singleton is used.
  /// If [context] is provided, it is passed to the underlying [HttpClient] for
  /// custom TLS configuration.
  ///
  /// By default [badCertificateCallback] accepts all certificates because the
  /// connection will use the resolved IP, not the original hostname, causing a
  /// hostname mismatch in most server certificates.
  DohnetClient({DohResolver? resolver, SecurityContext? context})
    : _resolver = resolver ?? DohResolver(),
      _client = HttpClient(context: context) {
    _setupConnectionFactory();
  }

  void _setupConnectionFactory() {
    print('${DateTime.now()} [INFO] DohnetClient v200726 initialized');
    _client.connectionFactory = (Uri url, String? proxyHost, int? proxyPort) async {
      final hostname = url.host;

      // Proxy → connect to proxy directly (no DoH).
      if (proxyHost != null) {
        final proxyPort_ = proxyPort ?? (url.port != 0 ? url.port : 80);
        return _connect(proxyHost, proxyPort_, secure: false);
      }

      // Resolve port — Dart Uri returns 0 for unknown schemes like `wss`.
      final port = url.port != 0
          ? url.port
          : _isSecureScheme(url.scheme)
          ? 443
          : 80;

      // Already an IP — no DoH needed.
      if (_isIpAddress(hostname)) {
        return _connect(hostname, port, secure: _isSecureScheme(url.scheme), sniHostname: hostname);
      }

      // Resolve via DoH.
      final ip = await _resolver.resolve(hostname);
      if (ip == null) {
        throw SocketException('DohnetClient: DNS resolution failed for $hostname');
      }

      return _connect(ip, port, secure: _isSecureScheme(url.scheme), sniHostname: hostname);
    };
  }

  /// Whether the scheme requires TLS.
  static bool _isSecureScheme(String scheme) => scheme == 'https' || scheme == 'wss';

  /// Creates a TCP or TLS connection task.
  ///
  /// If [secure] is true, connects with TLS using [sniHostname] as the
  /// Server Name Indication (SNI). This is critical when connecting via a
  /// resolved IP address — CDNs and many servers reject connections with
  /// an IP as SNI. Defaults to [host] if [sniHostname] is null.
  ///
  /// **Timeouts:** Both [Socket.connect] and [SecureSocket.secure] use
  /// [connectionTimeout] so the operation never hangs forever.
  ///
  /// **Cleanup:** When [HttpClient] cancels or disposes the connection, the
  /// cleanup callback closes the underlying socket so file descriptors are
  /// not leaked.
  Future<ConnectionTask<Socket>> _connect(String host, int port, {required bool secure, String? sniHostname}) async {
    final timeout = _connectTimeout;

    if (secure) {
      // Connect via TCP first, then upgrade to TLS with the correct SNI.
      // This ensures CDNs like Cloudflare receive the real hostname instead
      // of a raw IP (which would be rejected).
      final rawFuture = Socket.connect(host, port, timeout: timeout);
      // Chain the TLS handshake so it completes before ConnectionTask
      // signals "ready". Without `.then()`, SecureSocket.secure returns
      // immediately and defers the handshake until first write, which
      // can trigger race conditions inside HttpClient.
      final socketFuture = rawFuture.then(
        (raw) => SecureSocket.secure(
          raw,
          host: sniHostname ?? host,
          onBadCertificate: badCertificateCallback ?? (_) => true,
        ).timeout(timeout),
      );
      return ConnectionTask.fromSocket(socketFuture, _cleanup(socketFuture));
    }
    final socketFuture = Socket.connect(host, port, timeout: timeout);
    return ConnectionTask.fromSocket(socketFuture, _cleanup(socketFuture));
  }

  /// Returns a cleanup callback that closes the socket when it becomes
  /// available. Called by [HttpClient] when the connection is no longer
  /// needed.
  static void Function() _cleanup(Future<Socket> s) => () {
    s.then((socket) => socket.close());
  };

  /// Resolved connection timeout (or a safe default when null).
  Duration get _connectTimeout => connectionTimeout ?? const Duration(seconds: 30);

  // --------------------------------------------------------------------------
  // WebSocket
  // --------------------------------------------------------------------------

  /// Connects to a WebSocket at [url] using DoH-based DNS resolution.
  ///
  /// Uses this client's underlying [HttpClient] which has a DoH-aware
  /// [connectionFactory] and respects [badCertificateCallback].
  ///
  /// Example:
  /// ```dart
  /// final ws = await client.connectWs(
  ///   'wss://stream.binance.com/stream',
  ///   headers: {'Origin': 'https://www.binance.com'},
  /// );
  /// ws.pingInterval = Duration(seconds: 30);
  /// ```
  Future<WebSocket> connectWs(
    String url, {
    Iterable<String>? protocols,
    Map<String, dynamic>? headers,
    CompressionOptions compression = const CompressionOptions(),
  }) {
    return WebSocket.connect(
      url,
      protocols: protocols,
      headers: headers,
      compression: compression,
      customClient: _client,
    );
  }

  // --------------------------------------------------------------------------
  // High-level HTTP methods
  // --------------------------------------------------------------------------

  /// Sends a GET request to [url].
  ///
  /// Optional [headers] are added to the request.
  Future<DohnetResponse> get(Uri url, {Map<String, String>? headers}) => _send('GET', url, headers: headers);

  /// Sends a POST request to [url].
  ///
  /// Optional [headers] are added to the request.
  /// If [body] is provided, it is written as the request body:
  /// - `String` → sent as-is.
  /// - `List<int>` → sent as raw bytes.
  /// - Other objects → JSON-encoded and `Content-Type: application/json` is set.
  Future<DohnetResponse> post(Uri url, {Map<String, String>? headers, Object? body}) =>
      _send('POST', url, headers: headers, body: body);

  /// Sends a PUT request to [url].
  ///
  /// See [post] for how [body] is handled.
  Future<DohnetResponse> put(Uri url, {Map<String, String>? headers, Object? body}) =>
      _send('PUT', url, headers: headers, body: body);

  /// Sends a PATCH request to [url].
  ///
  /// See [post] for how [body] is handled.
  Future<DohnetResponse> patch(Uri url, {Map<String, String>? headers, Object? body}) =>
      _send('PATCH', url, headers: headers, body: body);

  /// Sends a DELETE request to [url].
  ///
  /// See [post] for how [body] is handled.
  Future<DohnetResponse> delete(Uri url, {Map<String, String>? headers, Object? body}) =>
      _send('DELETE', url, headers: headers, body: body);

  /// Sends a HEAD request to [url].
  ///
  /// Optional [headers] are added to the request.
  Future<DohnetResponse> head(Uri url, {Map<String, String>? headers}) => _send('HEAD', url, headers: headers);

  /// Sends an HTTP request with the given [method] to [url].
  ///
  /// This is the general-purpose method underpinning all the named helpers.
  /// See [post] for how [body] is handled.
  Future<DohnetResponse> send(String method, Uri url, {Map<String, String>? headers, Object? body}) =>
      _send(method, url, headers: headers, body: body);

  Future<DohnetResponse> _send(String method, Uri url, {Map<String, String>? headers, Object? body}) async {
    final request = await _client.openUrl(method, url);

    if (headers != null) {
      headers.forEach((key, value) => request.headers.set(key, value));
    }

    if (body != null) {
      if (body is String) {
        request.write(body);
      } else if (body is List<int>) {
        request.add(body);
      } else {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
    }

    final response = await request.close();
    final chunks = <int>[];
    await for (final chunk in response) {
      chunks.addAll(chunk);
    }
    final bytes = Uint8List.fromList(chunks);

    return DohnetResponse(
      statusCode: response.statusCode,
      headers: _headersToMap(response.headers),
      body: utf8.decode(bytes),
      bodyBytes: bytes,
    );
  }

  /// Converts dart:io [HttpHeaders] to a plain map.
  static Map<String, String> _headersToMap(HttpHeaders headers) {
    final map = <String, String>{};
    headers.forEach((name, values) {
      map[name] = values.join(', ');
    });
    return map;
  }

  // --------------------------------------------------------------------------
  // Properties
  // --------------------------------------------------------------------------

  /// The user-agent string used by the client.
  String? get userAgent => _client.userAgent;
  set userAgent(String? value) => _client.userAgent = value;

  /// The idle timeout for persistent connections.
  Duration get idleTimeout => _client.idleTimeout;
  set idleTimeout(Duration value) => _client.idleTimeout = value;

  /// The connection timeout.
  Duration? get connectionTimeout => _client.connectionTimeout;
  set connectionTimeout(Duration? value) => _client.connectionTimeout = value;

  /// Access the underlying [HttpClient] for advanced use.
  HttpClient get inner => _client;

  // --------------------------------------------------------------------------
  // Prefetch
  // --------------------------------------------------------------------------

  /// Pre-warms the DNS cache by resolving [hostname] via DoH.
  ///
  /// Subsequent HTTP/WebSocket calls to this host will skip DNS resolution
  /// and connect immediately. Ideal for Flutter — call this at app startup
  /// or on a splash screen.
  ///
  /// Uses the shared [DohResolver] singleton, so the cached IP is available
  /// to all [DohnetClient] instances that use the default resolver.
  ///
  /// ```dart
  /// await DohnetClient.prefetch('api.binance.com');
  /// await DohnetClient.prefetchAll([
  ///   'api.binance.com',
  ///   'stream.binance.com',
  /// ]);
  /// ```
  static Future<void> prefetch(String hostname) async {
    await DohResolver().resolve(hostname);
  }

  /// Resolves multiple [hostnames] in parallel to warm the DNS cache.
  static Future<void> prefetchAll(Iterable<String> hostnames) async {
    await Future.wait(hostnames.map(prefetch));
  }

  // --------------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------------

  /// Closes the underlying HTTP client.
  void close({bool force = false}) => _client.close(force: force);

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  static bool _isIpAddress(String value) {
    try {
      InternetAddress(value);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A simple HTTP response.
///
/// Contains the [statusCode], response [headers], and the body as both a
/// decoded [String] and raw [bodyBytes].
class DohnetResponse {
  /// The HTTP status code (e.g. 200, 404, 500).
  final int statusCode;

  /// Response headers as a map of header-name → value.
  final Map<String, String> headers;

  /// The response body decoded as UTF-8.
  final String body;

  /// The raw response body bytes.
  final Uint8List bodyBytes;

  const DohnetResponse({required this.statusCode, required this.headers, required this.body, required this.bodyBytes});

  @override
  String toString() => 'DohnetResponse($statusCode, ${bodyBytes.length} bytes)';
}
