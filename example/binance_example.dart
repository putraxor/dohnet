import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dohnet/dohnet.dart';

/// Example: Binance REST API + WebSocket via DoH.
///
/// 1. REST API — GET ticker price BTCUSDT via https://api.binance.com
/// 2. WebSocket — Stream kline 5m BTCUSDT & ETHUSDT via wss://stream.binance.com
///
/// Keduanya menggunakan DoH untuk resolve DNS, bypassing ISP blocking.
///
/// Run:
///   dart run example/binance_example.dart
Future<void> main() async {
  print('=== Binance REST API + WebSocket via DoH ===\n');

  // ── Prefetch DNS cache supaya koneksi cepet ─────────────────────────
  print('Prefetch DNS...');
  await prefetchAll(['api.binance.com', 'stream.binance.com']);
  print('   DNS cache ready!\n');

  // ── Part 1: REST API — top-level functions, no close() needed ──────
  print('━━━━ Part 1: REST API ━━━━');
  try {
    // Harga BTCUSDT
    print('1. GET https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT');
    var res = await get(
      Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT'),
      headers: {'User-Agent': 'dohnet/1.0'},
    );
    print('   Status: ${res.statusCode}');
    print('   Response: ${jsonDecode(res.body)}');

    // 24hr ticker ETHUSDT
    print('\n2. GET https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT');
    res = await get(
      Uri.parse('https://api.binance.com/api/v3/ticker/24hr?symbol=ETHUSDT'),
      headers: {'User-Agent': 'dohnet/1.0'},
    );
    final ticker = jsonDecode(res.body);
    print('   Status: ${res.statusCode}');
    print('   Symbol: ${ticker['symbol']}');
    print('   Price:  ${ticker['lastPrice']}');
    print('   High:   ${ticker['highPrice']}');
    print('   Low:    ${ticker['lowPrice']}');
    print('   Volume: ${ticker['volume']}');
    print('   Change: ${ticker['priceChangePercent']}%');
  } on SocketException catch (e) {
    print('✗ Network error: $e');
  } on HttpException catch (e) {
    print('✗ HTTP error: $e');
  }

  // ── Part 2: WebSocket — via client.connectWs() ─────────────────────
  print('\n━━━━ Part 2: WebSocket ━━━━');
  const host = 'stream.binance.com';
  final symbols = ['btcusdt', 'ethusdt'];
  final streams = symbols.map((s) => '$s@kline_5m').join('/');
  final url = 'wss://$host/stream?streams=$streams';

  final client = DohnetClient();
  try {
    final ws = await client.connectWs(
      url,
      headers: {
        'Origin': 'https://www.binance.com',
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      },
    );

    ws.pingInterval = const Duration(seconds: 30);
    print('   Connected to Binance WebSocket!');

    // Collect kline data for 15 seconds
    await _collectKlines(ws, const Duration(seconds: 15));
    await ws.close();
    print('   WebSocket closed.');
  } on SocketException catch (e) {
    print('✗ Socket error: $e');
  } finally {
    client.close();
  }
}

Future<void> _collectKlines(WebSocket ws, Duration duration) async {
  final sub = ws.listen(
    (raw) {
      try {
        final Map<String, dynamic> msg = jsonDecode(raw as String);
        final data = msg['data'];
        if (data is! Map) return;
        final k = data['k'];
        if (k is! Map) return;

        final symbol = k['s'] ?? '';
        final event = data['e'] ?? '?';
        final open = double.tryParse('${k['o']}')?.toStringAsFixed(2) ?? '?';
        final close = double.tryParse('${k['c']}')?.toStringAsFixed(2) ?? '?';
        final high = double.tryParse('${k['h']}')?.toStringAsFixed(2) ?? '?';
        final low = double.tryParse('${k['l']}')?.toStringAsFixed(2) ?? '?';

        print('   [$symbol] $event — O:$open H:$high L:$low C:$close');
      } catch (_) {}
    },
    onError: (e) => print('   Stream error: $e'),
    onDone: () => print('   Stream closed.'),
  );

  await Future.delayed(duration);
  await sub.cancel();
  print('   (collected for $duration)');
}
