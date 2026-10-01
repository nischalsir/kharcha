import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpHeaders;

import '../core/config/env.dart';

/// A resolved latitude/longitude pair used by the weather accent, with the
/// name of the place when it is known.
class AppLocation {
  const AppLocation({
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.fromDevice = false,
  });

  final double latitude;
  final double longitude;

  /// The town or city, e.g. "Kathmandu". Null when it could not be named.
  final String? placeName;

  /// True when this came from the phone's own location rather than a guess
  /// from the network address.
  final bool fromDevice;
}

/// Reads the phone's location. Kept behind an interface so the service can be
/// tested, and used on platforms that have no location plugin, without one.
abstract class DeviceLocator {
  /// The device's approximate location, or null when it is not permitted or
  /// not available. With [ask] the user may be shown the system permission
  /// prompt; without it nothing is ever shown.
  Future<AppLocation?> locate({required bool ask});
}

/// Resolves where the device roughly is, for the weather.
///
/// Resolution order:
///
/// 1. Explicit `WEATHER_LAT` / `WEATHER_LON` dart-defines, when set. These act
///    as a manual override, e.g. to pin the weather to a home town.
/// 2. The phone's own approximate location, when the user has allowed it.
/// 3. IP-based geolocation (geojs, falling back to ipwho.is and freeipapi).
///    City-level and sometimes a neighbouring city, which is why the device's
///    location is preferred when it is available.
///
/// Every step is optional: failures return `null` and the app simply renders
/// without weather. The lookup never blocks or throws.
class LocationService {
  LocationService({this._device});

  final DeviceLocator? _device;

  AppLocation? _cached;
  DateTime? _attemptedAt;
  Future<AppLocation?>? _inflight;

  /// How long to remember a failed lookup, so a slow network doesn't trigger a
  /// geolocation request every time a screen opens.
  static const Duration _backoff = Duration(minutes: 10);

  /// Where the device is. With [askPermission] the user may be asked to allow
  /// location access; callers pass it only in response to the user opening a
  /// screen that shows weather, never from the background.
  Future<AppLocation?> locate({bool askPermission = false}) {
    final lat = Env.weatherLat;
    final lon = Env.weatherLon;
    if (lat != null && lon != null) {
      return Future<AppLocation?>.value(
        AppLocation(latitude: lat, longitude: lon),
      );
    }
    final cached = _cached;
    // A network guess is replaced as soon as the real location is allowed.
    if (cached != null && (cached.fromDevice || !askPermission)) {
      return Future<AppLocation?>.value(cached);
    }
    final attempted = _attemptedAt;
    if (!askPermission &&
        attempted != null &&
        DateTime.now().difference(attempted) < _backoff) {
      return Future<AppLocation?>.value();
    }
    if (askPermission) return _resolve(ask: true);
    return _inflight ??= _resolve(ask: false)
        .whenComplete(() => _inflight = null);
  }

  Future<AppLocation?> _resolve({required bool ask}) async {
    _attemptedAt = DateTime.now();

    final device = _device;
    if (device != null) {
      try {
        final located = await device.locate(ask: ask);
        if (located != null) {
          _cached = located;
          return located;
        }
      } catch (_) {
        // No plugin on this platform, or the lookup failed: use the network.
      }
    }
    // Keep a guess that is already known rather than asking the network again.
    final cached = _cached;
    if (cached != null) return cached;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
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
      return parseIpLocation(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  /// Reads a location out of any of the IP geolocation providers' replies.
  /// They agree on `latitude`/`longitude` but name the city differently.
  static AppLocation? parseIpLocation(Object? json) {
    if (json is! Map) return null;
    double? number(Object? value) => value is num
        ? value.toDouble()
        : value is String
        ? double.tryParse(value)
        : null;
    final lat = number(json['latitude']);
    final lon = number(json['longitude']);
    if (lat == null || lon == null || (lat == 0 && lon == 0)) return null;
    String? place;
    for (final key in const <String>['city', 'cityName', 'region']) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        place = value.trim();
        break;
      }
    }
    return AppLocation(latitude: lat, longitude: lon, placeName: place);
  }
}
