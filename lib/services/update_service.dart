import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/l10n/app_l10n.dart';
import '../screens/settings/version_screen.dart';

class UpdateService {
  UpdateService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const String _repo = 'nischalsir/kharcha';
  static const String _releasesUrl = 'https://api.github.com/repos/$_repo/releases/latest';

  /// Checks if a newer version is available on GitHub.
  /// Returns the latest version string if an update is available, null otherwise.
  Future<String?> checkForUpdate() async {
    try {
      final response = await _client.get(
        Uri.parse(_releasesUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestTag = data['tag_name'] as String?; // e.g., "v1.0.1"
        if (latestTag != null && latestTag.isNotEmpty) {
          final latestVersion = latestTag.startsWith('v')
              ? latestTag.substring(1)
              : latestTag;
          if (_isNewer(latestVersion, VersionScreen.appVersion)) {
            return latestVersion;
          }
        }
      }
    } catch (_) {
      // Silently fail - update check is non-critical
    }
    return null;
  }

  /// Shows an update dialog if a newer version is available.
  Future<void> maybeShowUpdateDialog(BuildContext context) async {
    final latest = await checkForUpdate();
    if (latest == null || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _UpdateDialog(
        currentVersion: VersionScreen.appVersion,
        latestVersion: latest,
        releaseUrl: 'https://github.com/$_repo/releases/latest',
      ),
    );
  }

  bool _isNewer(String latest, String current) {
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
  const _UpdateDialog({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(L10n.t(context, 'Update Available', 'अपडेट उपलब्ध छ')),
        ],
      ),
      content: Text(
        L10n.t(
          context,
          'A new version ($latestVersion) is available. You are on $currentVersion. '
          'Tap "Update Now" to download the latest APK.',
          'नयाँ संस्करण ($latestVersion) उपलब्ध छ। तपाईं $currentVersion मा हुनुहुन्छ। '
          'नयाँ APK डाउनलोड गर्न "अहिले अपडेट गर्नुहोस्" थिच्नुहोस्।',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.t(context, 'Later', 'पछि')),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded),
          label: Text(L10n.t(context, 'Update Now', 'अहिले अपडेट गर्नुहोस्')),
          onPressed: () async {
            Navigator.of(context).pop();
            final uri = Uri.parse(releaseUrl);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
        ),
      ],
    );
  }
}