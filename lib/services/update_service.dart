import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/app_info.dart';

/// A published release: its version, where to get it, and what changed.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    this.apkUrl,
    this.apkSize,
    this.notes = '',
  });

  final String version;

  /// The release's APK when it has one, otherwise the release page.
  final String downloadUrl;

  /// The release's APK, when it has one. This is what the app downloads to
  /// update itself; without it the update is opened in the browser.
  final String? apkUrl;

  /// The APK's size in bytes as the release states it, to tell a complete
  /// download from one that was cut short.
  final int? apkSize;

  /// A short, plain-text summary of the release notes. May be empty.
  final String notes;
}

/// Where releases are published and how their versions compare.
///
/// The latest GitHub release is the one place update information is
/// configured: its tag is the version, its APK asset the download, and its
/// description the release notes. Nothing about a release is hard-coded in
/// the app.
class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _repo = 'nischalsir/kharcha';
  static const String _releasesUrl =
      'https://api.github.com/repos/$_repo/releases/latest';
  static const String _fallbackPage =
      'https://github.com/$_repo/releases/latest';

  /// The latest published release, whatever its version, or null when it
  /// could not be read (offline, rate limited, malformed).
  Future<UpdateInfo?> fetchLatest() async {
    try {
      final response = await _client
          .get(
            Uri.parse(_releasesUrl),
            headers: <String, String>{
              'Accept': 'application/vnd.github.v3+json',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      final tag = data['tag_name'];
      if (tag is! String || tag.isEmpty) return null;
      final version = normalizeVersion(tag);
      if (parseVersion(version) == null) return null;

      // Link straight to the APK so "Download" starts the download, instead
      // of dropping the user on a web page to hunt for the file.
      String? apk;
      int? apkSize;
      final assets = data['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = '${asset['name'] ?? ''}'.toLowerCase();
          final url = asset['browser_download_url'];
          if (name.endsWith('.apk') && url is String && url.isNotEmpty) {
            apk = url;
            final size = asset['size'];
            if (size is int && size > 0) apkSize = size;
            break;
          }
        }
      }
      final page = data['html_url'];
      final body = data['body'];
      return UpdateInfo(
        version: version,
        downloadUrl: apk ?? (page is String ? page : _fallbackPage),
        apkUrl: apk,
        apkSize: apkSize,
        notes: body is String ? summarizeNotes(body) : '',
      );
    } catch (_) {
      // The update check is never worth interrupting the user for.
      return null;
    }
  }

  /// The latest release if it is newer than the installed app, or null when
  /// up to date (or the check could not be made).
  Future<UpdateInfo?> checkForUpdate() async {
    final latest = await fetchLatest();
    if (latest == null) return null;
    return isNewer(latest.version, AppInfo.version) ? latest : null;
  }

  /// `v1.2.3` and `1.2.3+45` both become `1.2.3`.
  static String normalizeVersion(String raw) {
    var value = raw.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    final plus = value.indexOf('+');
    return plus < 0 ? value : value.substring(0, plus);
  }

  /// The numeric parts of a version, or null when it is not a version.
  /// Anything after a `-` (a pre-release label) is ignored.
  static List<int>? parseVersion(String raw) {
    final core = normalizeVersion(raw).split('-').first;
    if (core.isEmpty) return null;
    final parts = <int>[];
    for (final piece in core.split('.')) {
      final number = int.tryParse(piece);
      if (number == null || number < 0) return null;
      parts.add(number);
    }
    return parts;
  }

  /// Negative when [a] is older than [b], zero when equal, positive when
  /// newer. Compared number by number, so 1.10.0 is newer than 1.9.0; a
  /// missing part counts as zero. A string that is not a version is older
  /// than any that is.
  static int compareVersions(String a, String b) {
    final left = parseVersion(a);
    final right = parseVersion(b);
    if (left == null || right == null) {
      if (left == null && right == null) return 0;
      return left == null ? -1 : 1;
    }
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l < r ? -1 : 1;
    }
    return 0;
  }

  static bool isNewer(String latest, String current) =>
      parseVersion(latest) != null && compareVersions(latest, current) > 0;

  /// Turns a release description into a few plain lines for the update
  /// prompt: the first bullets of its first section, without the markdown.
  /// Three at most: the prompt is there to say a version is ready, and the
  /// whole list is one tap away on the release page.
  static String summarizeNotes(String body, {int maxLines = 3}) {
    final lines = <String>[];
    var sections = 0;
    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        sections++;
        // "What's new" is the first section; installing notes come after.
        if (sections > 1) break;
        continue;
      }
      var text = line
          .replaceAll(RegExp(r'\*\*|__|`'), '')
          .replaceAllMapped(
            RegExp(r'\[([^\]]+)\]\([^)]*\)'),
            (match) => match.group(1) ?? '',
          );
      final bullet = RegExp(r'^[-*+]\s+').firstMatch(text);
      if (bullet != null) text = '• ${text.substring(bullet.end)}';
      // Keep each point to its headline: "Title. Explanation" -> "Title."
      final stop = text.indexOf('. ');
      if (bullet != null && stop > 0) text = text.substring(0, stop + 1);
      lines.add(text);
      if (lines.length >= maxLines) break;
    }
    return lines.join('\n');
  }
}
