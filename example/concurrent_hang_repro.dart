import 'dart:async';
import 'package:dohnet/dohnet.dart';

Future<void> main() async {
  print('══════════════════════════════════════════════════════');
  print('  dohnet — Concurrent Hang Reproduction (no DNS warm)');
  print('══════════════════════════════════════════════════════\n');

  final targets = [
    _Target('api.binance.com', 'GET',
        'https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=5m&limit=1',
        const {}),
  ];

  for (final c in [1, 3, 5, 10]) {
    await _testConcurrency(c, targets);
  }

  print('\n══════════════════════════════════════════════════════');
  print('  Done.');
  print('══════════════════════════════════════════════════════');
}

Future<void> _testConcurrency(int n, List<_Target> targets) async {
  print('━━━ Concurrency = $n ━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  final sw = Stopwatch()..start();
  int ok = 0, errors = 0, hangs = 0;

  final client = DohnetClient();
  client.badCertificateCallback = (_) => true;
  client.connectionTimeout = const Duration(seconds: 15);

  final allFutures = <Future<void>>[];
  for (final t in targets) {
    for (var i = 0; i < n; i++) {
      allFutures.add(_request(client, t).then((r) {
        if (r == 'ok') ok++;
        if (r == 'error') errors++;
      }));
    }
  }

  try {
    await Future.wait(allFutures).timeout(const Duration(seconds: 30));
  } on TimeoutException {
    hangs = allFutures.length - ok - errors;
  }

  sw.stop();
  final total = n * targets.length;
  print('   $ok/$total OK  $errors err  $hangs hang  (${sw.elapsedMilliseconds}ms)');

  if (hangs > 0) {
    print('   ⚠ HANG DETECTED');
  }

  client.close();
}

Future<String> _request(DohnetClient client, _Target t) async {
  try {
    final uri = Uri.parse(t.url);
    final res = await client.get(uri, headers: t.headers);
    return res.statusCode == 200 ? 'ok' : 'error';
  } catch (_) {
    return 'error';
  }
}

class _Target {
  final String host;
  final String method;
  final String url;
  final Map<String, String> headers;
  const _Target(this.host, this.method, this.url, this.headers);
}
