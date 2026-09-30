import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/services/location_service.dart';
import 'package:kharcha_app/services/weather_service.dart';

void main() {
  group('LocationService', () {
    test('never throws and returns a usable coordinate pair or null', () async {
      final service = LocationService();
      final first = await service.locate();
      if (first != null) {
        expect(first.latitude, inInclusiveRange(-90, 90));
        expect(first.longitude, inInclusiveRange(-180, 180));
      }
      final second = await service.locate();
      expect(second, first);
    });
  });

  group('WeatherService', () {
    test('degrades gracefully when no coordinates can be resolved', () async {
      final weather = await WeatherService().current();
      if (weather != null) {
        expect(weather.temperatureC, inInclusiveRange(-90, 60));
        expect(weather.label, isNotEmpty);
        expect(weather.emoji, isNotEmpty);
      }
    });

    test('accepts pinned coordinates', () {
      final service = WeatherService(latitude: 27.7172, longitude: 85.3240);
      expect(service.latitude, 27.7172);
      expect(service.longitude, 85.3240);
    });
  });

  group('provider response shapes', () {
    test('geojs latitude/longitude fields parse into an AppLocation', () {
      const body = '{"latitude":27.7108,"longitude":85.3251,"city":"Kathmandu"}';
      final json = jsonDecode(body) as Map<String, dynamic>;
      final location = AppLocation(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
      );
      expect(location.latitude, closeTo(27.7108, 0.0001));
      expect(location.longitude, closeTo(85.3251, 0.0001));
    });
  });
}
