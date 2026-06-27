import 'dart:io';
import 'package:dohnet/dohnet.dart';

/// Example: HTTP GET/POST requests using DoH-based DNS resolution.
///
/// Run:
///   dart run example/http_example.dart
Future<void> main() async {
  print('=== dohnet Example (HTTP/HTTPS) ===\n');

  // ── Top-level functions: no close() needed ──────────────────────────
  try {
    // GET https://httpbin.org/ip
    print('1. GET https://httpbin.org/ip');
    var response = await get(Uri.parse('https://httpbin.org/ip'));
    print('   Status: ${response.statusCode}');
    print('   Body: ${response.body}\n');

    // GET https://api.github.com/
    print('2. GET https://api.github.com/');
    response = await get(
      Uri.parse('https://api.github.com/'),
      headers: {'User-Agent': 'dohnet/1.0'},
    );
    print('   Status: ${response.statusCode}');
    print(
      '   Body (snippet): ${response.body.substring(0, response.body.length.clamp(0, 150))}\n',
    );

    // POST with JSON body
    print('3. POST https://httpbin.org/post');
    response = await post(
      Uri.parse('https://httpbin.org/post'),
      body: {'hello': 'doh'},
    );
    print('   Status: ${response.statusCode}');
    print('   Body: ${response.body}\n');
  } on SocketException catch (e) {
    print('✗ Network error: $e');
    print('  (expected if the test environment has no network)');
  } on HttpException catch (e) {
    print('✗ HTTP error: $e');
  }
}
