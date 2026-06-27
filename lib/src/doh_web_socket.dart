import 'dart:io';

import 'doh_resolver.dart';

/// WebSocket client that uses DNS-over-HTTPS (DoH) for domain resolution.
///
/// Two usage modes:
///
/// **1. Simple mode (no customClient)** — resolves the hostname via DoH,
/// replaces the URL host with the IP, and sets the `Host` header. Works for
/// servers that accept IP-based connections (e.g. Binance).
///
/// **2. Custom client mode** — pass an [HttpClient] that has its
/// [HttpClient.connectionFactory] configured for DoH (e.g. the `.inner`
/// property of [DohnetClient]). The connection factory handles DNS
/// resolution via DoH and TLS with an `onBadCertificate` callback.
///
/// Example (simple mode):
/// ```dart
/// final ws = await DohWebSocket.connect(
///   'wss://stream.binance.com/stream',
///   headers: {'Origin': 'https://www.binance.com'},
/// );
/// ```
///
/// Example (custom client mode, bypasses TLS cert issues):
/// ```dart
/// final httpClient = DohnetClient();
/// final ws = await DohWebSocket.connect(
///   'wss://example.com/ws',
///   customClient: httpClient.inner,
/// );
/// ```
class DohWebSocket {
  /// Connects to the WebSocket at [url] using DoH-based DNS resolution.
  ///
  /// Parameters:
  /// - [url]: WebSocket URL (e.g. `wss://example.com/ws`).
  /// - [resolver]: Optional custom [DohResolver]. Defaults to singleton.
  /// - [protocols]: WebSocket sub-protocols.
  /// - [headers]: Custom HTTP headers (e.g. `Origin`, `User-Agent`).
  /// - [compression]: Compression options.
  /// - [customClient]: An [HttpClient] with a DoH-aware
  ///   [HttpClient.connectionFactory]. When provided, the connection factory
  ///   handles DNS resolution and TLS setup, avoiding hostname/IP mismatches.
  ///
  /// When [customClient] is **not** provided, the method uses a simple
  /// IP-based connection. The returned [WebSocket] has no ping interval
  /// configured — callers should set it after connecting:
  /// ```dart
  /// ws.pingInterval = Duration(seconds: 30);
  /// ```
  static Future<WebSocket> connect(
    String url, {
    DohResolver? resolver,
    Iterable<String>? protocols,
    Map<String, dynamic>? headers,
    CompressionOptions compression = const CompressionOptions(),
    HttpClient? customClient,
  }) async {
    final r = resolver ?? DohResolver();

    // ---- Custom client mode ----
    // The HttpClient already has a DoH-aware connectionFactory that handles
    // both DNS resolution and TLS (with onBadCertificate). WebSocket.connect
    // will use it for the underlying TCP/TLS connection.
    if (customClient != null) {
      return WebSocket.connect(
        url,
        protocols: protocols,
        headers: headers,
        compression: compression,
        customClient: customClient,
      );
    }

    // ---- Simple IP-based mode ----
    // Resolve hostname via DoH, connect to the IP, send Host header.
    final uri = Uri.parse(url);
    final hostname = uri.host;
    final ip = await r.resolve(hostname);

    if (ip == null) {
      throw SocketException(
        'DohWebSocket: DNS resolution failed for $hostname',
      );
    }

    // Build a new URL with the resolved IP.
    final wsScheme = uri.scheme == 'wss' ? 'wss' : 'ws';
    final ipUri = Uri(
      scheme: wsScheme,
      host: ip,
      port: uri.port,
      path: uri.path,
      query: uri.query,
    );

    // Merge user-supplied headers with the mandatory Host header.
    final mergedHeaders = <String, dynamic>{
      if (headers != null) ...headers,
      'Host': hostname,
    };

    return WebSocket.connect(
      ipUri.toString(),
      protocols: protocols,
      headers: mergedHeaders,
      compression: compression,
    );
  }
}
