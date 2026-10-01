/// The app's own version, in one place.
///
/// Must match `version:` in pubspec.yaml: the update checker compares this
/// against the latest GitHub release, so a stale value here makes every
/// install claim an update is available. `test/app_info_test.dart` fails
/// the build if the two drift apart, so bump both together.
class AppInfo {
  /// The name of the app's assistant, the flame mascot. Used wherever the
  /// app speaks about it, so it is spelt one way everywhere.
  static const String assistantName = 'Flamey';

  const AppInfo._();

  static const String version = '1.0.21';
  static const String buildNumber = '23';
  static const String applicationId = 'com.nischalpandey.kharcha';
}
