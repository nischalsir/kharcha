import 'package:geolocator/geolocator.dart';

/// Where one of the phone's permissions stands for this app.
enum AccessState {
  /// Given.
  allowed,

  /// Not given, and Android will show its prompt when asked.
  notAllowed,

  /// Not given, and Android will no longer ask: it can only be changed on
  /// the app's page in the phone's settings.
  blocked,
}

/// The phone's location permission, for Settings > App Permissions.
///
/// Kharcha uses the approximate location for one thing: the weather for the
/// user's town on the Calendar. It is asked for here, when the user chooses
/// to, and nowhere else.
class LocationAccess {
  const LocationAccess();

  static AccessState _of(LocationPermission permission) => switch (permission) {
    LocationPermission.always ||
    LocationPermission.whileInUse => AccessState.allowed,
    LocationPermission.deniedForever => AccessState.blocked,
    _ => AccessState.notAllowed,
  };

  /// Reads the permission without asking for it.
  Future<AccessState> status() async {
    try {
      return _of(await Geolocator.checkPermission());
    } catch (_) {
      return AccessState.notAllowed;
    }
  }

  /// Shows Android's prompt, where Android will show one.
  Future<AccessState> request() async {
    try {
      return _of(await Geolocator.requestPermission());
    } catch (_) {
      return AccessState.notAllowed;
    }
  }

  /// Opens Kharcha's page in the phone's settings.
  Future<bool> openSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
