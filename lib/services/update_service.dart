import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';
import '../core/l10n/app_l10n.dart';

/// A newer release than the one installed.
class UpdateInfo {
  const UpdateInfo({required this.version, required this.downloadUrl});

  final String version;

  /// The release's APK when it has one, otherwise the release page.
  final String downloadUrl;
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _repo = 'nischalsir/kharcha';
  static const String _releasesUrl =
      'https://api.github.com/repos/$_repo/releases/latest';
  static const String _fallbackPage =
      'https://github.com/$_repo/releases/latest';

  /// The latest GitHub release if it is newer than the installed app, or null
  /// when up to date (or the check could not be made).
  Future<UpdateInfo?> checkForUpdate() async {
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
      final version = tag.startsWith('v') ? tag.substring(1) : tag;
      if (!_isNewer(version, AppInfo.version)) return null;

      // Link straight to the APK so "Update" starts the download, instead of
      // dropping the user on a web page to hunt for the file.
      String? apk;
      final assets = data['assets'];
      if (assets is List) {
        for (final asset in assets) {
          if (asset is! Map) continue;
          final name = '${asset['name'] ?? ''}'.toLowerCase();
          final url = asset['browser_download_url'];
          if (name.endsWith('.apk') && url is String && url.isNotEmpty) {
            apk = url;
            break;
          }
        }
      }
      final page = data['html_url'];
      return UpdateInfo(
        version: version,
        downloadUrl: apk ?? (page is String ? page : _fallbackPage),
      );
    } catch (_) {
      // The update check is never worth interrupting the user for.
      return null;
    }
  }

  /// Shows an update dialog if a newer version is available.
  Future<void> maybeShowUpdateDialog(BuildContext context) async {
    final update = await checkForUpdate();
    if (update == null || !context.mounted) return;
    await showUpdateDialog(context, update);
  }

  static Future<void> showUpdateDialog(BuildContext context, UpdateInfo update) {
    return showDialog<void>(
      context: context,
      builder: (context) => _UpdateDialog(update: update),
    );
  }

  static bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final l = i < latestParts.length ? (latestParts[i] ?? 0) : 0;
      final c = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({required this.update});

  final UpdateInfo update;

  /// Opens the download in the browser. Launched directly: gating on
  /// `canLaunchUrl` returns false on Android 11+ unless the manifest declares
  /// the intent, which made this button silently do nothing.
  Future<void> _download(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = L10n.t(
      context,
      'Could not open the browser. Download link copied.',
      'ब्राउजर खोल्न सकिएन। डाउनलोड लिङ्क कपी भयो।',
    );
    Navigator.of(context).pop();
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(update.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened) return;
    await Clipboard.setData(ClipboardData(text: update.downloadUrl));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(L10n.t(context, 'Update available', 'अपडेट उपलब्ध छ')),
          ),
        ],
      ),
      content: Text(
        L10n.t(
          context,
          'Version ${update.version} is available. You are on '
              '${AppInfo.version}. The download starts in your browser; open '
              'the file when it finishes to install.',
          'संस्करण ${update.version} उपलब्ध छ। तपाईं ${AppInfo.version} मा '
              'हुनुहुन्छ। डाउनलोड ब्राउजरमा सुरु हुन्छ; सकिएपछि फाइल खोलेर '
              'इन्स्टल गर्नुहोस्।',
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.t(context, 'Later', 'पछि')),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded),
          label: Text(L10n.t(context, 'Download', 'डाउनलोड')),
          onPressed: () => _download(context),
        ),
      ],
    );
  }
}
