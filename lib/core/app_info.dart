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

  static const String version = '2.1.0';
  static const String buildNumber = '37';

  /// A version as it is shown to people and named in a release: `1.1` for
  /// `1.1.0`, `1.3.1` as it is. Android and pubspec.yaml need all three
  /// numbers; a trailing `.0` says nothing, so it is left off everywhere
  /// else. New features move the middle number, fixes the last.
  ///
  /// A major release is the exception: `2.0.0` is the name it is announced
  /// by, and it keeps all three numbers.
  static String short(String version) {
    final parts = version.split('.');
    if (parts.length != 3 || parts[2] != '0' || parts[1] == '0') {
      return version;
    }
    return '${parts[0]}.${parts[1]}';
  }

  /// [version] as it is shown.
  static String get displayVersion => short(version);
  static const String applicationId = 'com.nischalpandey.kharcha';
}
