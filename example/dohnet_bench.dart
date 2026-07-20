import 'dart:async';
import 'dart:io';
import 'package:dohnet/dohnet.dart';

const n = 5;
const url = 'https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1h&limit=3';

Future<void> main() async {
  print('═════════════════════════════════════════════');
  print('  dohnet — Latency Benchmark');
  print('═════════════════════════════════════════════\n');

  print('[1] Dohnet sequential x$n');
  await _benchDohnetSequential();

  print('\n[2] Native sequential x$n');
  await _benchNativeSequential();

  print('\n[3] Dohnet concurrent x$n');
  await _benchDohnetConcurrent();

  print('\n[4] Native concurrent x$n');
  await _benchNativeConcurrent();

  print('\n[5] Dohnet keep-alive (cold + $n warm)');
  await _benchDohnetKeepAlive();

  print('\nDone.');
}

DohnetClient _makeDohClient() {
  final c = DohnetClient();
  c.badCertificateCallback = (_) => true;
  c.connectionTimeout = const Duration(seconds: 10);
  return c;
}

Future<void> _benchDohnetSequential() async {
  final client = _makeDohClient();
  final times = <int>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    try {
      final res = await client.get(Uri.parse(url));
      sw.stop();
      times.add(sw.elapsedMilliseconds);
      print('   $i: ${res.statusCode} — ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      sw.stop();
      print('   $i: ERROR — ${sw.elapsedMilliseconds}ms  $e');
    }
  }
  client.close();
  if (times.isNotEmpty) {
    print('   avg ${times.reduce((a,b)=>a+b) ~/ times.length}ms');
  }
}

Future<void> _benchNativeSequential() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final times = <int>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      await res.drain();
      sw.stop();
      times.add(sw.elapsedMilliseconds);
      print('   $i: ${res.statusCode} — ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      sw.stop();
      print('   $i: ERROR — ${sw.elapsedMilliseconds}ms  $e');
    }
  }
  client.close();
  if (times.isNotEmpty) {
    print('   avg ${times.reduce((a,b)=>a+b) ~/ times.length}ms');
  }
}

Future<void> _benchDohnetConcurrent() async {
  final client = _makeDohClient();
  final sw = Stopwatch()..start();
  try {
    final results = await Future.wait(
      List.generate(n, (_) => client.get(Uri.parse(url))),
    );
    sw.stop();
    for (var i = 0; i < results.length; i++) {
      print('   $i: ${results[i].statusCode}');
    }
    print('   total ${sw.elapsedMilliseconds}ms');
  } catch (e) {
    sw.stop();
    print('   ERROR — ${sw.elapsedMilliseconds}ms  $e');
  }
  client.close();
}

Future<void> _benchNativeConcurrent() async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);
  final sw = Stopwatch()..start();
  try {
    final results = await Future.wait(
      List.generate(n, (_) async {
        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close();
        await res.drain();
        return res.statusCode;
      }),
    );
    sw.stop();
    for (var i = 0; i < results.length; i++) {
      print('   $i: ${results[i]}');
    }
    print('   total ${sw.elapsedMilliseconds}ms');
  } catch (e) {
    sw.stop();
    print('   ERROR — ${sw.elapsedMilliseconds}ms  $e');
  }
  client.close();
}

Future<void> _benchDohnetKeepAlive() async {
  final client = _makeDohClient();

  // Cold (first connection)
  final swC = Stopwatch()..start();
  await client.get(Uri.parse(url));
  swC.stop();
  print('   cold: ${swC.elapsedMilliseconds}ms');

  // Warm (should reuse pooled connection)
  final times = <int>[];
  for (var i = 0; i < n; i++) {
    final sw = Stopwatch()..start();
    await client.get(Uri.parse(url));
    sw.stop();
    times.add(sw.elapsedMilliseconds);
    print('   warm $i: ${sw.elapsedMilliseconds}ms');
  }
  client.close();
  if (times.isNotEmpty) {
    final avg = times.reduce((a,b)=>a+b) ~/ times.length;
    final min = times.reduce((a,b)=>a<b?a:b);
    final max = times.reduce((a,b)=>a>b?a:b);
    print('   avg ${avg}ms  min ${min}ms  max ${max}ms');
  }
}
