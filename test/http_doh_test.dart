import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dohnet/dohnet.dart';
import 'package:test/test.dart';

/// Creates a mock [DnsLookupFn] from predefined address records.
DnsLookupFn mockLookup(Map<String, List<InternetAddress>> records) {
  final ttl = 3600; // 1 hour for tests
  return (String hostname) async {
    final addresses = records[hostname];
    if (addresses == null || addresses.isEmpty) return null;
    final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
    final addr = ipv4.isNotEmpty ? ipv4.first : addresses.first;
    return DnsLookupResult(ip: addr.address, ttlSeconds: ttl);
  };
}

void main() {
  group('DohResolver', () {
    late DnsLookupFn mockDns;
    late DohResolver resolver;

    setUp(() {
      mockDns = mockLookup({
        'example.com': [InternetAddress('93.184.216.34')],
        'google.com': [
          InternetAddress('142.250.80.46'),
          InternetAddress('2607:f8b0:4000:804::200e'),
        ],
      });
      resolver = DohResolver.custom(mockDns);
    });

    tearDown(() {
      resolver.clearCache();
    });

    test('resolves hostname to IPv4 address', () async {
      final ip = await resolver.resolve('example.com');
      expect(ip, equals('93.184.216.34'));
    });

    test('prefers IPv4 over IPv6 when both are available', () async {
      final ip = await resolver.resolve('google.com');
      expect(ip, equals('142.250.80.46'));
    });

    test('returns null for unresolvable hostname', () async {
      final ip = await resolver.resolve('nonexistent.domain.test');
      expect(ip, isNull);
    });

    test('caches resolved IPs', () async {
      // Use a mutable map so we can verify caching works.
      final records = <String, List<InternetAddress>>{
        'example.com': [InternetAddress('93.184.216.34')],
      };
      final cachedResolver = DohResolver.custom(mockLookup(records));

      final ip1 = await cachedResolver.resolve('example.com');
      expect(ip1, equals('93.184.216.34'));

      // Mutate the underlying data — cache should still return the old value.
      records['example.com'] = [InternetAddress('1.2.3.4')];

      final ip2 = await cachedResolver.resolve('example.com');
      expect(ip2, equals('93.184.216.34'));
    });

    test('clearCache removes all entries', () async {
      final records = <String, List<InternetAddress>>{
        'example.com': [InternetAddress('93.184.216.34')],
      };
      final cachedResolver = DohResolver.custom(mockLookup(records));

      await cachedResolver.resolve('example.com');
      expect(
        cachedResolver.resolve('example.com'),
        completion('93.184.216.34'),
      );

      cachedResolver.clearCache();

      records['example.com'] = [InternetAddress('1.2.3.4')];
      final ip = await cachedResolver.resolve('example.com');
      expect(ip, equals('1.2.3.4'));
    });

    test('returns the input if it is already an IP address', () async {
      final ip = await resolver.resolve('8.8.8.8');
      expect(ip, equals('8.8.8.8'));
    });

    test('handles IPv6 loopback', () async {
      final ip = await resolver.resolve('::1');
      expect(ip, equals('::1'));
    });

    test('singleton returns the same instance', () {
      final a = DohResolver();
      final b = DohResolver();
      expect(a, same(b));
    });

    test('cacheSize reports correct number of entries', () async {
      expect(resolver.cacheSize, equals(0));
      await resolver.resolve('example.com');
      expect(resolver.cacheSize, equals(1));
      await resolver.resolve('google.com');
      expect(resolver.cacheSize, equals(2));
    });

    test('removeFromCache removes a single entry', () async {
      await resolver.resolve('example.com');
      expect(resolver.cacheSize, equals(1));
      resolver.removeFromCache('example.com');
      expect(resolver.cacheSize, equals(0));
    });
  });

  group('DohnetClient', () {
    test('can be constructed with default resolver', () {
      final client = DohnetClient();
      expect(client, isA<DohnetClient>());
      client.close();
    });

    test('can be constructed with custom resolver', () {
      final resolver = DohResolver.custom((_) async => null);
      final client = DohnetClient(resolver: resolver);
      expect(client, isA<DohnetClient>());
      client.close();
    });

    test('DohnetResponse exposes basic properties', () {
      final response = DohnetResponse(
        statusCode: 200,
        headers: {'content-type': 'text/plain'},
        body: 'ok',
        bodyBytes: Uint8List.fromList(utf8.encode('ok')),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'text/plain');
      expect(response.body, 'ok');
      expect(response.bodyBytes, [111, 107]);
    });
  });

  group('Top-level convenience functions', () {
    test('get returns a DohnetResponse', () async {
      expect(get, isA<Function>());
      expect(post, isA<Function>());
      expect(put, isA<Function>());
      expect(delete, isA<Function>());
      expect(head, isA<Function>());
      expect(connectWs, isA<Function>());
    });
  });

  group('Prefetch', () {
    test('DohnetClient.prefetch and prefetchAll are callable', () async {
      expect(DohnetClient.prefetch, isA<Function>());
      expect(DohnetClient.prefetchAll, isA<Function>());

      // prefetch on an IP address is a no-op (skips lookup)
      await DohnetClient.prefetch('8.8.8.8');
      await DohnetClient.prefetchAll(['8.8.8.8', '1.1.1.1']);
    });

    test('top-level prefetch and prefetchAll are callable', () async {
      expect(prefetch, isA<Function>());
      expect(prefetchAll, isA<Function>());

      await prefetch('8.8.8.8');
      await prefetchAll(['8.8.8.8', '1.1.1.1']);
    });
  });

  group('DohWebSocket (legacy)', () {
    test('throws SocketException for unresolvable hostname', () async {
      final resolver = DohResolver.custom((_) async => null);
      await expectLater(
        DohWebSocket.connect(
          'wss://nonexistent.example.com/ws',
          resolver: resolver,
        ),
        throwsA(isA<SocketException>()),
      );
    });

    test('throws SocketException for empty host', () async {
      final resolver = DohResolver.custom((_) async => null);
      await expectLater(
        DohWebSocket.connect('wss:///ws', resolver: resolver),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
