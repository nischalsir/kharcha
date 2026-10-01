import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha_app/services/location_service.dart';
import 'package:kharcha_app/services/weather_service.dart';

/// A stand-in for the phone's location services.
class _FakeDevice implements DeviceLocator {
  _FakeDevice({this.permitted = true, this.grantsWhenAsked = false});

  bool permitted;
  final bool grantsWhenAsked;
  final List<bool> asks = <bool>[];

  @override
  Future<AppLocation?> locate({required bool ask}) async {
    asks.add(ask);
    if (!permitted && ask && grantsWhenAsked) permitted = true;
    if (!permitted) return null;
    return const AppLocation(
      latitude: 28.2096,
      longitude: 83.9856,
      placeName: 'Pokhara',
      fromDevice: true,
    );
  }
}

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

    test('the phone’s own location is used when it is allowed', () async {
      final device = _FakeDevice();
      final location = await LocationService(device: device).locate();

      expect(location?.placeName, 'Pokhara');
      expect(location?.fromDevice, isTrue);
      // Opening a screen is not a reason to prompt.
      expect(device.asks, <bool>[false]);
    });

    test('the permission prompt is only reached when asked for', () async {
      final device = _FakeDevice(permitted: false, grantsWhenAsked: true);
      final service = LocationService(device: device);

      await service.locate();
      expect(device.asks, <bool>[false]);

      final allowed = await service.locate(askPermission: true);
      expect(device.asks.last, isTrue);
      expect(allowed?.placeName, 'Pokhara');
    });

    test(
      'a device location is remembered instead of looked up again',
      () async {
        final device = _FakeDevice();
        final service = LocationService(device: device);
        await service.locate();
        await service.locate();
        await service.locate(askPermission: true);

        expect(device.asks, hasLength(1));
      },
    );

    test('a locator that throws is treated as unavailable', () async {
      final service = LocationService(device: _ThrowingDevice());
      // Falls through to the network guess, which may or may not answer here;
      // what matters is that nothing escapes.
      await expectLater(service.locate(), completes);
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

  group('network location replies', () {
    test('geojs: latitude and longitude as strings, with a city', () {
      final location = LocationService.parseIpLocation(
        jsonDecode(
          '{"latitude":"27.7108","longitude":"85.3251","city":"Kathmandu"}',
        ),
      );
      expect(location?.latitude, closeTo(27.7108, 0.0001));
      expect(location?.longitude, closeTo(85.3251, 0.0001));
      expect(location?.placeName, 'Kathmandu');
      expect(location?.fromDevice, isFalse);
    });

    test('freeipapi names the city differently', () {
      final location = LocationService.parseIpLocation(
        jsonDecode(
          '{"latitude":26.45,"longitude":87.27,"cityName":"Biratnagar"}',
        ),
      );
      expect(location?.placeName, 'Biratnagar');
    });

    test('a reply without a city still gives coordinates', () {
      final location = LocationService.parseIpLocation(
        jsonDecode('{"latitude":27.7,"longitude":85.3,"city":""}'),
      );
      expect(location, isNotNull);
      expect(location?.placeName, isNull);
    });

    test('a failed lookup or a 0,0 answer is no location', () {
      expect(
        LocationService.parseIpLocation(jsonDecode('{"success":false}')),
        isNull,
      );
      expect(
        LocationService.parseIpLocation(
          jsonDecode('{"latitude":0,"longitude":0}'),
        ),
        isNull,
      );
      expect(LocationService.parseIpLocation(jsonDecode('[]')), isNull);
    });
  });
}

class _ThrowingDevice implements DeviceLocator {
  @override
  Future<AppLocation?> locate({required bool ask}) =>
      throw StateError('no location plugin');
}
