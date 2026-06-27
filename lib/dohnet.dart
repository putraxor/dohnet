/// Library for HTTP and WebSocket clients with DNS-over-HTTPS (DoH)
/// resolution to bypass DNS poisoning and blocking by ISPs.
///
/// Provides:
/// - [DohResolver] — Resolve hostnames to IPs via Google DoH.
/// - [DohnetClient] — HTTP + WebSocket client using DoH resolution.
///
/// ## Top-level convenience functions (like `package:http`)
///
/// No need to manage client lifecycle:
/// ```dart
/// import 'package:dohnet/dohnet.dart' as dohnet;
///
/// final res = await dohnet.get(Uri.parse('https://example.com'));
/// print(res.body);
///
/// final ws = await dohnet.connectWs('wss://example.com/ws');
/// ```
///
/// ## Explicit client (for custom config)
///
/// ```dart
/// final client = DohnetClient();
/// client.badCertificateCallback = (cert) => true;
/// final res = await client.get(Uri.parse('https://example.com'));
/// client.close();
/// ```
library;

export 'src/doh_resolver.dart';
export 'src/dohnet_client.dart';
export 'src/doh_web_socket.dart' show DohWebSocket;

import 'dart:io';

import 'src/dohnet_client.dart';

// ---------------------------------------------------------------------------
// Top-level convenience functions (like package:http)
// Uses a shared singleton — no need to call close().
// ---------------------------------------------------------------------------

final DohnetClient _sharedClient = DohnetClient();

/// Pre-warms the DNS cache by resolving [hostname] via the shared DoH resolver.
Future<void> prefetch(String hostname) => DohnetClient.prefetch(hostname);

/// Resolves multiple [hostnames] in parallel to warm the DNS cache.
Future<void> prefetchAll(Iterable<String> hostnames) =>
    DohnetClient.prefetchAll(hostnames);

/// Sends a GET request using the shared DoH client.
Future<DohnetResponse> get(Uri url, {Map<String, String>? headers}) =>
    _sharedClient.get(url, headers: headers);

/// Sends a POST request using the shared DoH client.
Future<DohnetResponse> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) => _sharedClient.post(url, headers: headers, body: body);

/// Sends a PUT request using the shared DoH client.
Future<DohnetResponse> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) => _sharedClient.put(url, headers: headers, body: body);

/// Sends a PATCH request using the shared DoH client.
Future<DohnetResponse> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) => _sharedClient.patch(url, headers: headers, body: body);

/// Sends a DELETE request using the shared DoH client.
Future<DohnetResponse> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
}) => _sharedClient.delete(url, headers: headers, body: body);

/// Sends a HEAD request using the shared DoH client.
Future<DohnetResponse> head(Uri url, {Map<String, String>? headers}) =>
    _sharedClient.head(url, headers: headers);

/// Connects to a WebSocket at [url] using the shared DoH client.
Future<WebSocket> connectWs(
  String url, {
  Iterable<String>? protocols,
  Map<String, dynamic>? headers,
  CompressionOptions compression = const CompressionOptions(),
}) => _sharedClient.connectWs(
  url,
  protocols: protocols,
  headers: headers,
  compression: compression,
);
