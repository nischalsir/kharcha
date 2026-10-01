import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient;

import 'package:flutter/foundation.dart';

import 'location_service.dart';

/// Optional, key-less current-weather lookup (Open-Meteo).
///
/// Weather is a *nice-to-have* accent for the AI mood card, never a blocker:
/// when the request fails callers simply get `null` and the app renders
/// without it. Results are cached in memory so the Home screen never hammers
/// the network.
///
/// Coordinates may be pinned explicitly via [latitude]/[longitude]; otherwise
/// they are resolved automatically through [LocationService] (explicit
/// `WEATHER_LAT`/`WEATHER_LON` defines first, then IP geolocation).
class AiWeather {
  const AiWeather({
    required this.temperatureC,
    required this.code,
    required this.label,
    required this.emoji,
    required this.hint,
    this.place,
  });

  final double temperatureC;
  final int code;
  final String label;
  final String emoji;
  final String hint;

  /// The town the reading is for, e.g. "Kathmandu". Null when unknown.
  final String? place;
}

class WeatherService {
  WeatherService({
    this.latitude,
    this.longitude,
    LocationService? locationService,
  }) : _locationService = locationService ?? LocationService();

  final double? latitude;
  final double? longitude;
  final LocationService _locationService;

  static const Duration _ttl = Duration(minutes: 30);

  AiWeather? _cached;
  DateTime? _fetchedAt;
  Future<AiWeather?>? _inflight;

  /// The current weather. With [askPermission] the user may be asked for
  /// location access first, and the reading is fetched again for wherever
  /// that turns out to be instead of being served from the cache.
  Future<AiWeather?> current({bool askPermission = false}) {
    if (kIsWeb) return Future<AiWeather?>.value();
    if (askPermission) return _fetch(askPermission: true);
    final fetchedAt = _fetchedAt;
    if (_cached != null &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < _ttl) {
      return Future<AiWeather?>.value(_cached);
    }
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<AiWeather?> _fetch({bool askPermission = false}) async {
    double? lat = latitude;
    double? lon = longitude;
    String? place;
    if (lat == null || lon == null) {
      final located = await _locationService.locate(
        askPermission: askPermission,
      );
      lat = located?.latitude;
      lon = located?.longitude;
      place = located?.placeName;
    }
    if (lat == null || lon == null) return null;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '$lat',
        'longitude': '$lon',
        'current': 'temperature_2m,weather_code',
        'timezone': 'auto',
      });
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>?;
      if (current == null) return null;
      final temp = (current['temperature_2m'] as num?)?.toDouble() ?? 0;
      final code = (current['weather_code'] as num?)?.toInt() ?? 0;
      _cached = _describe(temp, code, place);
      _fetchedAt = DateTime.now();
      return _cached;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  AiWeather _describe(double temp, int code, String? place) {
    final (String label, String emoji, String hint) = switch (code) {
      0 => ('Clear', '☀️', 'Great weather — a walk beats a cab today.'),
      1 || 2 || 3 => ('Partly cloudy', '🌤️', 'Mild weather out there.'),
      >= 51 && <= 67 => ('Rainy', '🌧️', 'Rainy day — skip the delivery fee.'),
      >= 71 && <= 77 => ('Snowy', '❄️', 'Snowy day, stay warm and indoors.'),
      >= 80 && <= 82 => ('Showers', '🌦️', 'Showers around — plan ahead.'),
      >= 95 => ('Stormy', '⛈️', 'Stormy out — stay safe.'),
      _ => ('Cloudy', '☁️', 'A calm day for budgeting.'),
    };
    return AiWeather(
      temperatureC: temp,
      code: code,
      label: label,
      emoji: emoji,
      hint: hint,
      place: place,
    );
  }
}
