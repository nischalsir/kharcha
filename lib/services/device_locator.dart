import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

/// The phone's own approximate location, through the platform's location
/// services. Only the coarse permission is declared, so this is city-block
/// accuracy at best, which is all the weather needs.
class GeolocatorDeviceLocator implements DeviceLocator {
  const GeolocatorDeviceLocator();

  /// Whether the app may read the location right now, without asking.
  static Future<bool> isPermitted() async {
    try {
      final permission = await Geolocator.checkPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AppLocation?> locate({required bool ask}) async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && ask) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    // The last known fix is instant and good enough for weather; a fresh one
    // is only requested when the phone has none.
    final position =
        await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 8),
          ),
        );

    return AppLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      placeName: await _placeName(position.latitude, position.longitude),
      fromDevice: true,
    );
  }

  /// The town for a coordinate, using the platform's own geocoder. Null when
  /// it has no answer; the weather is still shown, just without a name.
  static Future<String?> _placeName(double latitude, double longitude) async {
    try {
      final places = await Geocoding().placemarkFromCoordinates(
        latitude,
        longitude,
      );
      for (final place in places) {
        for (final name in <String?>[
          place.locality,
          place.subAdministrativeArea,
          place.administrativeArea,
        ]) {
          if (name != null && name.trim().isNotEmpty) return name.trim();
        }
      }
    } catch (_) {
      // No geocoder on this device, or no network.
    }
    return null;
  }
}
