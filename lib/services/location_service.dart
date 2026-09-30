import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders;

import '../core/config/env.dart';

/// A resolved latitude/longitude pair used by the weather accent.
class AppLocation {
  const AppLocation({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Resolves the device's approximate location without any OS permissions.
///
/// Resolution order:
///
/// 1. Explicit `WEATHER_LAT` / `WEATHER_LON` dart-defines, when set. These act
///    as a manual override, e.g. to pin the weather to a home town.
/// 2. IP-based geolocation (geojs, falling back to ipwho.is and freeipapi).
///
/// All providers are key-less and HTTPS-only, return city-level accuracy (which
/// is more than enough for weather), and are cached in memory for the process
/// lifetime. Failures return `null` and the app simply renders without weather
/// — the lookup never blocks or throws.
class LocationService {
  AppLocation? _cached;
  DateTime? _attemptedAt;
  Future<AppLocation?>? _inflight;

  /// How long to remember a failed lookup, so a slow network doesn't trigger a
  /// geolocation request every time a screen opens.
  static const Duration _backoff = Duration(minutes: 10);

  Future<AppLocation?> locate() {
    final lat = Env.weatherLat;
    final lon = Env.weatherLon;
    if (lat != null && lon != null) {
      return Future<AppLocation?>.value(
        AppLocation(latitude: lat, longitude: lon),
      );
    }
    final cached = _cached;
    if (cached != null) return Future<AppLocation?>.value(cached);
    final attempted = _attemptedAt;
    if (attempted != null &&
        DateTime.now().difference(attempted) < _backoff) {
      return Future<AppLocation?>.value();
    }
    return _inflight ??= _resolve().whenComplete(() => _inflight = null);
  }

  Future<AppLocation?> _resolve() async {
    _attemptedAt = DateTime.now();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      for (final uri in <Uri>[
        Uri.https('get.geojs.io', '/v1/ip/geo.json'),
        Uri.https('ipwho.is', '/'),
        Uri.https('freeipapi.com', '/api/json'),
      ]) {
        final location = await _tryEndpoint(client, uri);
        if (location != null) {
          _cached = location;
          return location;
        }
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<AppLocation?> _tryEndpoint(HttpClient client, Uri uri) async {
    try {
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'KharchaApp/1.0 (weather accent)',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final lat = (json['latitude'] as num?)?.toDouble();
      final lon = (json['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null || (lat == 0 && lon == 0)) return null;
      return AppLocation(latitude: lat, longitude: lon);
    } catch (_) {
      return null;
    }
  }
}
