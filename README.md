# dohnet

Dart HTTP & WebSocket client library with **DNS-over-HTTPS (DoH)** resolution.

Bypasses DNS poisoning / blocking by ISPs — resolves domain names via Google DoH (using raw IP `8.8.8.8` to avoid DNS-level blocking), then connects directly to the resolved IP while preserving the original hostname for proper TLS SNI and HTTP `Host` headers.

Like `package:http` — simple top-level functions, no `close()` needed.

## Usage

### Top-level functions (no `close()` needed)

```dart
import 'package:dohnet/dohnet.dart';

final res = await get(Uri.parse('https://example.com'));
print(res.statusCode); // 200
print(res.body);       // <html>...

final ws = await connectWs('wss://example.com/ws');
ws.listen((data) => print(data));
```

### With an explicit client

```dart
final client = DohnetClient();
client.badCertificateCallback = (cert) => true;

final res = await client.get(Uri.parse('https://example.com'));
print(res.statusCode);
print(res.body);

final ws = await client.connectWs('wss://example.com/ws');

client.close(); // only needed when creating an explicit client
```

### Prefetch — warm the DNS cache early

Great for Flutter: prefetch domains on your splash screen so real requests connect instantly.

```dart
// In main() or splash screen
await DohnetClient.prefetch('api.binance.com');
await DohnetClient.prefetchAll([
  'api.binance.com',
  'stream.binance.com',
]);

// Later — DNS is cached, connection is instant
final res = await get(Uri.parse('https://api.binance.com/...'));
```

### Resolver

```dart
final resolver = DohResolver();
final ip = await resolver.resolve('example.com');
print(ip); // 93.184.216.34
```

## Classes

| Class | Description |
|-------|-------------|
| `DohnetClient` | HTTP + WebSocket client with DoH resolution |
| `DohnetResponse` | Simple response with `statusCode`, `body`, `bodyBytes`, `headers` |
| `DohResolver` | Singleton DNS resolver via Google DoH, with caching |
| `DohWebSocket` | Legacy helper (use `client.connectWs()` instead) |

## Examples

```bash
dart run example/http_example.dart
dart run example/ws_example.dart
dart run example/binance_example.dart
```

## Tests

```bash
dart test
```
