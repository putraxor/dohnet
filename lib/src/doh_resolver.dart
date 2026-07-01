import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

/// Result of a DNS lookup with TTL information.
class DnsLookupResult {
  final String ip;
  final int ttlSeconds;

  const DnsLookupResult({required this.ip, required this.ttlSeconds});
}

/// Function signature for custom DNS lookup implementations.
///
/// Receives a [hostname] and returns the resolved IP with TTL, or `null`
/// if resolution fails.
typedef DnsLookupFn = Future<DnsLookupResult?> Function(String hostname);

/// DNS-over-HTTPS (DoH) resolver with TTL-based caching and LRU eviction.
///
/// Uses Google DNS (`https://dns.google/resolve`) via the JSON API to bypass
/// ISP DNS poisoning. Results are cached respecting the upstream DNS TTL,
/// with a fallback of 5 minutes when TTL is unavailable.
///
/// Cache behavior:
/// - Entries expire when their TTL elapses (re-resolved on next access).
/// - Maximum 500 entries — the least recently used entry is evicted when full.
/// - A periodic timer sweeps expired entries every 5 minutes.
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

  DohResolver._internal() : _lookupFn = _defaultDoHLookup;

  /// Creates a [DohResolver] with a custom lookup function.
  ///
  /// Useful for testing or for using a different DoH provider.
  DohResolver.custom(this._lookupFn);

  final DnsLookupFn _lookupFn;

  /// Default TTL applied when the upstream DNS response does not include one.
  static const Duration _fallbackTTL = Duration(minutes: 5);

  /// Soft limit for the number of cached entries.
  static const int _maxCacheSize = 500;

  /// DNS cache — [LinkedHashMap] maintains insertion order for LRU eviction.
  final Map<String, _CachedEntry> _cache = LinkedHashMap();

  /// Periodic cleanup timer for expired entries.
  Timer? _cleanupTimer;

  /// Resolves [hostname] to an IP address string via DoH.
  ///
  /// Returns `null` if resolution fails.
  Future<String?> resolve(String hostname) async {
    // Return immediately if already an IP address.
    if (_isIpAddress(hostname)) return hostname;

    // ── Cache hit ──────────────────────────────────────────────────
    final entry = _cache[hostname];
    if (entry != null) {
      if (!entry.isExpired) {
        // Promote to most-recently-used position for LRU ordering.
        _cache.remove(hostname);
        _cache[hostname] = entry;
        entry.touch();
        return entry.ip;
      }
      // Expired → discard; will re-resolve below.
      _cache.remove(hostname);
    }

    // ── Cache miss or expired → look up ────────────────────────────
    final result = await _lookupFn(hostname);
    if (result != null) {
      _addToCache(hostname, result.ip, result.ttlSeconds);
      return result.ip;
    }
    return null;
  }

  /// Inserts [hostname] → [ip] with the given [ttlSeconds].
  ///
  /// Evicts the least recently used entry when [_maxCacheSize] is reached.
  void _addToCache(String hostname, String ip, int ttlSeconds) {
    if (_cache.length >= _maxCacheSize) {
      // LinkedHashMap: first key = oldest / least recently used.
      _cache.remove(_cache.keys.first);
    }
    _cache[hostname] = _CachedEntry(ip: ip, ttlSeconds: ttlSeconds);
    _ensureCleanupTimer();
  }

  /// Starts a periodic timer that purges expired entries.
  void _ensureCleanupTimer() {
    if (_cleanupTimer != null) return;
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _cache.removeWhere((_, e) => e.isExpired),
    );
  }

  /// Default DNS lookup via [Google DoH JSON API](https://developers.google.com/speed/public-dns/docs/doh#json).
  ///
  /// Uses the hostname `dns.google` so that the system resolver handles
  /// bootstrapping — no circular dependency on our own cache.
  /// Requests A records (IPv4) and returns the first result with its TTL.
  static Future<DnsLookupResult?> _defaultDoHLookup(String hostname) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(
        'https://dns.google/resolve'
        '?name=${Uri.encodeQueryComponent(hostname)}&type=A',
      );
      final request = await client.getUrl(uri);
      request.headers.set('accept', 'application/dns-json');
      final response = await request.close();
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['Status'] != 0) return null; // NXDOMAIN, SERVFAIL, etc.

      final answers = json['Answer'] as List<dynamic>?;
      if (answers == null || answers.isEmpty) return null;

      for (final ans in answers) {
        if (ans['type'] == 1) {
          // A record (IPv4)
          return DnsLookupResult(
            ip: ans['data'] as String,
            ttlSeconds: (ans['TTL'] as int?) ?? _fallbackTTL.inSeconds,
          );
        }
      }
      return null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// Removes all entries from the cache and cancels the cleanup timer.
  void clearCache() {
    _cache.clear();
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Removes a single entry from the cache.
  void removeFromCache(String hostname) => _cache.remove(hostname);

  /// Returns the number of entries currently in the cache.
  int get cacheSize => _cache.length;

  /// Returns `true` when [value] is a valid IPv4 or IPv6 address.
  static bool _isIpAddress(String value) {
    try {
      InternetAddress(value);
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// A cached DNS record with TTL-based expiration.
class _CachedEntry {
  final String ip;
  final DateTime expiresAt;
  DateTime lastAccessed;

  _CachedEntry({required this.ip, required int ttlSeconds})
    : expiresAt = DateTime.now().add(Duration(seconds: ttlSeconds)),
      lastAccessed = DateTime.now();

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  void touch() => lastAccessed = DateTime.now();
}
