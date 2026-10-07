import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;

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

  /// The release's APK for this phone, when it has one.
  final String? apkUrl;

  /// The APK's size in bytes as the release states it.
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
  UpdateService({http.Client? client, String? abi})
    : _client = client ?? http.Client(),
      _abi = abi ?? deviceAbi();

  final http.Client _client;

  /// The kind of processor this phone has, as Android names it.
  final String? _abi;

  /// Android's name for the processor this build is running on, or null
  /// when it is not one a release is made for.
  static String? deviceAbi() {
    final abi = Abi.current();
    if (abi == Abi.androidArm64) return 'arm64-v8a';
    if (abi == Abi.androidArm) return 'armeabi-v7a';
    if (abi == Abi.androidX64) return 'x86_64';
    return null;
  }

  static const List<String> _abis = <String>[
    'arm64-v8a',
    'armeabi-v7a',
    'x86_64',
    'x86',
  ];

  /// The APK among a release's [assets] that this phone should download.
  ///
  /// A release may carry one APK for every phone, or smaller ones named for
  /// one kind of processor each (`kharcha-v2.4-arm64-v8a.apk`). The one made
  /// for this phone's processor is preferred, then the one for every phone.
  /// One made for a different processor is never picked: it would download
  /// and then refuse to install.
  ///
  /// Only a file GitHub serves is accepted, whatever the release says.
  static ({String url, int? size})? pickApk(Object? assets, {String? abi}) {
    if (assets is! List) return null;
    ({String url, int? size})? universal;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = '${asset['name'] ?? ''}'.toLowerCase();
      final url = asset['browser_download_url'];
      if (!name.endsWith('.apk') || url is! String) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
        continue;
      }
      final size = asset['size'];
      final found = (url: url, size: size is int && size > 0 ? size : null);
      final madeFor = _abis.where(name.contains).toList();
      if (madeFor.isEmpty) {
        universal ??= found;
      } else if (abi != null && madeFor.contains(abi)) {
        return found;
      }
    }
    return universal;
  }

  static const String _repo = 'nischalsir/kharcha';
  static const String _releasesUrl =
      'https://api.github.com/repos/$_repo/releases/latest';
  static const String _fallbackPage =
      'https://github.com/$_repo/releases/latest';

  /// The latest published release, whatever its version, or null when it
  /// could not be read (offline, malformed).
  ///
  /// GitHub's API is asked first, because it also has the release notes and
  /// the files. It only answers sixty times an hour for one internet
  /// address, though, and that address is often shared (a home's Wi-Fi, a
  /// whole mobile network), so the answer is regularly "rate limit
  /// exceeded". When the API cannot be read, the release page is asked
  /// instead: see [_fromReleasePage].
  Future<UpdateInfo?> fetchLatest() async =>
      await _fromApi() ?? await _fromReleasePage();

  Future<UpdateInfo?> _fromApi() async {
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
      final picked = pickApk(data['assets'], abi: _abi);
      final apk = picked?.url;
      final apkSize = picked?.size;
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

  /// The latest release as the website names it, with no API involved.
  ///
  /// `github.com/<repo>/releases/latest` answers with a redirect to the
  /// newest release's own page, whose address ends in its tag. That is the
  /// version. The APK's address follows from the tag, because
  /// `tool/release.ps1` names every release's file `kharcha-<tag>.apk`.
  /// The release notes are not known this way, so they are left empty.
  Future<UpdateInfo?> _fromReleasePage() async {
    try {
      final request = http.Request('GET', Uri.parse(_fallbackPage))
        ..followRedirects = false;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 10));
      // Only where it points is wanted, not the page.
      unawaited(response.stream.drain<void>().catchError((_) {}));
      final location = response.headers['location'];
      final redirect = response.statusCode >= 300 && response.statusCode < 400;
      if (!redirect || location == null) return null;
      final uri = Uri.parse(_fallbackPage).resolve(location);
      const marker = '/releases/tag/';
      final at = uri.path.indexOf(marker);
      if (uri.scheme != 'https' || uri.host != 'github.com' || at < 0) {
        return null;
      }
      final tag = Uri.decodeComponent(uri.path.substring(at + marker.length));
      // A tag is a version and nothing else: it is about to be put into an
      // address.
      if (!RegExp(r'^v?\d+(\.\d+){1,2}$').hasMatch(tag)) return null;
      final apk =
          'https://github.com/$_repo/releases/download/$tag/kharcha-$tag.apk';
      return UpdateInfo(
        version: normalizeVersion(tag),
        downloadUrl: apk,
        apkUrl: apk,
      );
    } catch (_) {
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
