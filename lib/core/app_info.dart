/// The app's own version, in one place.
///
/// Must match `version:` in pubspec.yaml: the update checker compares this
/// against the latest GitHub release, so a stale value here makes every
/// install claim an update is available. `test/app_info_test.dart` fails
/// the build if the two drift apart, so bump both together.
class AppInfo {
  const AppInfo._();

  static const String version = '1.0.11';
  static const String buildNumber = '13';
  static const String applicationId = 'com.nischalpandey.kharcha';
}
