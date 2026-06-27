import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dohnet/dohnet.dart';

/// Example: WebSocket connections using DoH-based DNS resolution.
///
/// Run:
///   dart run example/ws_example.dart
Future<void> main() async {
  print('=== dohnet Example (WebSocket) ===\n');

  // ── Top-level connectWs: no client boilerplate ─────────────────────
  print('Connecting via connectWs()...');
  try {
    final ws = await connectWs(
      'wss://ws.postman-echo.com/raw',
      headers: {'Origin': 'https://ws.postman-echo.com'},
    );

    ws.pingInterval = const Duration(seconds: 30);
    print('   Connected!');

    await _pingPong(ws);
    await ws.close();
    print('   Connection closed.');
  } on HandshakeException catch (e) {
    print('✗ TLS handshake failed: $e');
    print('  → Try with a DohnetClient and custom badCertificateCallback.');
  } on SocketException catch (e) {
    print('✗ Network error: $e');
  }

  print('');

  // ── Explicit client (for custom config) ────────────────────────────
  print('Connecting via DohnetClient.connectWs()...');
  final client = DohnetClient()..badCertificateCallback = (_) => true;

  try {
    final ws = await client.connectWs(
      'wss://ws.postman-echo.com/raw',
      headers: {
        'Origin': 'https://ws.postman-echo.com',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    ws.pingInterval = const Duration(seconds: 30);
    print('   Connected via client.connectWs()!');

    await _pingPong(ws);
    await ws.close();
    print('   Connection closed.');
  } on HandshakeException catch (e) {
    print('✗ TLS handshake still failed: $e');
  } on SocketException catch (e) {
    print('✗ Network error: $e');
  } finally {
    client.close();
  }
}

Future<void> _pingPong(WebSocket ws) async {
  final message = jsonEncode({
    'action': 'ping',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  });

  ws.add(message);
  print('   Sent: $message');

  final completer = Completer<String>();
  ws.listen(
    (data) {
      if (!completer.isCompleted) completer.complete(data as String);
    },
    onError: (error) {
      if (!completer.isCompleted) completer.completeError(error);
    },
    cancelOnError: false,
  );

  final response = await completer.future.timeout(const Duration(seconds: 10));
  print('   Received: $response');
}
