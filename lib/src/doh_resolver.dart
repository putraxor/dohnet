import 'dart:io';
import 'package:dns_client/dns_client.dart';

/// DNS-over-HTTPS (DoH) resolver with caching.
///
/// Uses Google DNS via IP (`https://8.8.8.8/resolve`) to avoid DNS poisoning
/// by ISPs. The resolved IPs are cached to minimize redundant lookups.
///
/// Example:
/// ```dart
/// final resolver = DohResolver();
/// final ip = await resolver.resolve('example.com');
/// print(ip); // 93.184.216.34
/// ```
class DohResolver {
  static final DohResolver _instance = DohResolver._internal();

  /// Returns the global singleton instance.
  factory DohResolver() => _instance;

  DohResolver._internal()
    : _dnsClient = DnsOverHttps(
        'https://8.8.8.8/resolve',
        timeout: const Duration(seconds: 10),
      );

  /// Creates a [DohResolver] with a custom [DnsClient] implementation.
  ///
  /// This is useful for testing or for using a different DoH provider.
  DohResolver.custom(this._dnsClient);

  final DnsClient _dnsClient;
  final Map<String, String> _cache = {};

  /// Resolves [hostname] to an IP address string via DoH.
  ///
  /// Returns `null` if resolution fails.
  Future<String?> resolve(String hostname) async {
    // Return cached IP if available
    if (_cache.containsKey(hostname)) return _cache[hostname];

    // Skip resolution for IP addresses already
    if (_isIpAddress(hostname)) {
      _cache[hostname] = hostname;
      return hostname;
    }

    try {
      final addresses = await _dnsClient.lookup(hostname);
      if (addresses.isNotEmpty) {
        // Prefer IPv4 for compatibility
        final ipv4 = addresses.where((a) => a.type == InternetAddressType.IPv4);
        final addr = ipv4.isNotEmpty ? ipv4.first : addresses.first;
        _cache[hostname] = addr.address;
        return addr.address;
      }
    } catch (_) {
      // Resolution failed, return null
    }
    return null;
  }

  /// Clears the DNS cache.
  void clearCache() => _cache.clear();

  /// Removes a single entry from the cache.
  void removeFromCache(String hostname) => _cache.remove(hostname);

  /// Checks if [value] is already an IP address.
  static bool _isIpAddress(String value) {
    try {
      InternetAddress(value);
      return true;
    } catch (_) {
      return false;
    }
  }
}
